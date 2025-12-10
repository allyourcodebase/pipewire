//! Pipewire has two different plugin systems that make heavy use of `dlopen`, which requires a
//! dynamic linker. However, since it ships with the necessary plugins, there's no reason we can't
//! just bake these into the executable and then stub out `dlopen` to avoid a dependency on the
//! dynamic linker.

const std = @import("std");

const log = std.log.scoped(.wrap_dlfcn);
const fmtFlags = @import("format.zig").fmtFlags;

const c = @cImport({
    @cInclude("spa/support/plugin.h");
    @cInclude("spa/support/log.h");
    @cInclude("dlfcn.h");
});

/// The last error.
var err: ?[*:0]const u8 = null;

/// Look up a library in the hard coded library table.
pub export fn __wrap_dlopen(path: ?[*:0]const u8, mode: std.c.RTLD) callconv(.c) ?*anyopaque {
    const span = if (path) |p| std.mem.span(p) else Lib.main_program_name;
    const lib = if (libs.getIndex(span)) |index| &libs.kvs.values[index] else null;
    log.debug("dlopen(\"{f}\", {f}) -> {?f}", .{ std.zig.fmtString(span), fmtFlags(mode), lib });
    return @ptrCast(@constCast(lib));
}

/// Close is a noop.
pub export fn __wrap_dlclose(handle: ?*anyopaque) callconv(.c) c_int {
    const lib: *const Lib = @ptrCast(@alignCast(handle.?));
    log.debug("dlclose({f})", .{lib});
    return 0;
}

/// Look up a symbol in a hard coded library table.
pub export fn __wrap_dlsym(
    noalias handle: ?*anyopaque,
    noalias name: [*:0]u8,
) callconv(.c) ?*anyopaque {
    const lib: *const Lib = if (handle == c.RTLD_DEFAULT)
        @panic("unimplemented")
    else if (handle == c.RTLD_NEXT)
        &libs.get(Lib.rtld_next_name).?
    else
        @ptrCast(@alignCast(handle.?));
    const span = std.mem.span(name);
    var msg: ?[:0]const u8 = null;
    const symbol = lib.symbols.get(span) orelse b: {
        msg = "symbol not found";
        break :b null;
    };
    log.debug("dlsym({f}, \"{f}\") -> 0x{x} ({s})", .{
        lib,
        std.zig.fmtString(span),
        @intFromPtr(symbol),
        if (msg) |m| m else "success",
    });
    if (msg) |m| err = m;
    return symbol;
}

/// Get the last error. Since `dlopen` is allowed to return null on success if the symbol's
/// value is zero, `dlerror` is a necessary part of the `dlopen` interface.
pub export fn __wrap_dlerror() callconv(.c) ?[*:0]const u8 {
    const result = err;
    err = null;
    return @ptrCast(result);
}

/// We don't support `dlinfo` as pipewire doesn't currently use it. If it's called, crash.
pub export fn __wrap_dlinfo(
    noalias handle: ?*anyopaque,
    request: c_int,
    noalias info: ?*anyopaque,
) callconv(.c) c_int {
    const lib: *const Lib = @ptrCast(@alignCast(handle.?));
    log.debug("dlinfo({f}, {}, {x})", .{ lib, request, @intFromPtr(info) });
    @panic("unimplemented");
}

/// A fake dynamic library.
pub const Lib = struct {
    /// You're allowed to pass null as the path to dlopen, in which case you're supposed to get a
    /// handle to the main program. Pipewire does not appear to use this functionality, so the
    /// corresponding table under this name is empty.
    const main_program_name = "@SELF";
    /// `RTLD_NEXT` is a special handle you can pass to `dlsym` instead of a handle acquired by
    /// `dlopen`. The exact behavior would be difficult to emulate precisely, but in practice
    /// Pipewire just uses this functionality to stub out some file system calls, which we provide
    /// in a separate table.
    const rtld_next_name = "@RTLD_NEXT";

    /// The name of the library, for debug output.
    name: []const u8,
    /// The library's symbols.
    symbols: std.StaticStringMap(?*anyopaque),

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("@\"{f}\"", .{std.zig.fmtString(self.name)});
    }

    fn sym(val: anytype) *anyopaque {
        return @ptrCast(@constCast(val));
    }
};

/// A fake dynamic symbol table.
pub const libs: std.StaticStringMap(Lib) = .initComptime(.{
    .{
        Lib.main_program_name,
        Lib{
            .name = Lib.main_program_name,
            .symbols = .initComptime(.{}),
        },
    },
    .{
        Lib.rtld_next_name,
        Lib{
            .name = Lib.rtld_next_name,
            .symbols = .initComptime(.{
                .{
                    "OPENAT64",
                    Lib.sym(&fops.OPENAT64),
                },
                .{
                    "dup",
                    Lib.sym(&fops.dup),
                },
                .{
                    "close",
                    Lib.sym(&fops.close),
                },
                .{
                    "ioctl",
                    Lib.sym(&fops.ioctl),
                },
                .{
                    "mmap64",
                    Lib.sym(&fops.mmap64),
                },
                .{
                    "munmap",
                    Lib.sym(&fops.munmap),
                },
            }),
        },
    },
    .{
        "pipewire-0.3/plugins/support/libspa-support.so",
        Lib{
            .name = "libspa-support",
            .symbols = .initComptime(.{
                .{
                    "spa_handle_factory_enum",
                    Lib.sym(&plugins.spa_support__spa_handle_factory_enum),
                },
                .{
                    "spa_log_topic_enum",
                    Lib.sym(&plugins.spa_support__spa_log_topic_enum),
                },
            }),
        },
    },
    .{
        "pipewire-0.3/plugins/videoconvert/libspa-videoconvert.so",
        Lib{
            .name = "libspa-videoconvert",
            .symbols = .initComptime(.{
                .{
                    "spa_handle_factory_enum",
                    Lib.sym(&plugins.spa_videoconvert__spa_handle_factory_enum),
                },
                .{
                    "spa_log_topic_enum",
                    Lib.sym(&plugins.spa_videoconvert__spa_log_topic_enum),
                },
            }),
        },
    },
    .{
        "pipewire-0.3/modules/libpipewire-module-protocol-native.so",
        Lib{
            .name = "libpipewire-module-protocol-native",
            .symbols = .initComptime(.{
                .{
                    "pipewire__module_init",
                    Lib.sym(&modules.pipewire_module_protocol_native__pipewire__module_init),
                },
            }),
        },
    },
    .{
        "pipewire-0.3/modules/libpipewire-module-client-node.so",
        Lib{
            .name = "libpipewire-module-client-node",
            .symbols = .initComptime(.{
                .{
                    "pipewire__module_init",
                    Lib.sym(&modules.pipewire_module_client_node__pipewire__module_init),
                },
            }),
        },
    },
    .{
        "pipewire-0.3/modules/libpipewire-module-client-device.so",
        Lib{
            .name = "libpipewire-module-client-device",
            .symbols = .initComptime(.{
                .{
                    "pipewire__module_init",
                    Lib.sym(&modules.pipewire_module_client_device__pipewire__module_init),
                },
            }),
        },
    },
    .{
        "pipewire-0.3/modules/libpipewire-module-adapter.so",
        Lib{
            .name = "libpipewire-module-adapter",
            .symbols = .initComptime(.{
                .{
                    "pipewire__module_init",
                    Lib.sym(&modules.pipewire_module_adapter__pipewire__module_init),
                },
            }),
        },
    },
    .{
        "pipewire-0.3/modules/libpipewire-module-metadata.so",
        Lib{
            .name = "libpipewire-module-metadata",
            .symbols = .initComptime(.{
                .{
                    "pipewire__module_init",
                    Lib.sym(&modules.pipewire_module_metadata__pipewire__module_init),
                },
            }),
        },
    },
    .{
        "pipewire-0.3/modules/libpipewire-module-session-manager.so",
        Lib{
            .name = "libpipewire-module-session-manager",
            .symbols = .initComptime(.{
                .{
                    "pipewire__module_init",
                    Lib.sym(&modules.pipewire_module_session_manager__pipewire__module_init),
                },
            }),
        },
    },
});

/// Pipewire plugin externs. Note that these symbols have been namespaced with the preprocessor, as
/// the upstream pipewire source usese the same symbol names for these across all plugins which
/// would result in duplicate symbols when linking statically.
pub const plugins = struct {
    const SpaHandleFactoryEnum = fn (?*anyopaque, factory: ?*anyopaque) callconv(.c) c_int;

    extern const spa_support__spa_handle_factory_enum: SpaHandleFactoryEnum;
    extern const spa_videoconvert__spa_handle_factory_enum: SpaHandleFactoryEnum;

    extern const spa_support__spa_log_topic_enum: c.spa_log_topic_enum;
    extern const spa_videoconvert__spa_log_topic_enum: c.spa_log_topic_enum;
};

/// Pipewire module externs. Note that these symbols have been namespaced with the preprocessor, as
/// the upstream pipewire source usese the same symbol names for these across all plugins which
/// would result in duplicate symbols when linking statically.
pub const modules = struct {
    const PipewireModuleInit = fn (_: ?*anyopaque, _: ?*anyopaque) callconv(.c) void;

    extern const pipewire_module_protocol_native__pipewire__module_init: PipewireModuleInit;
    extern const pipewire_module_client_node__pipewire__module_init: PipewireModuleInit;
    extern const pipewire_module_client_device__pipewire__module_init: PipewireModuleInit;
    extern const pipewire_module_adapter__pipewire__module_init: PipewireModuleInit;
    extern const pipewire_module_metadata__pipewire__module_init: PipewireModuleInit;
    extern const pipewire_module_session_manager__pipewire__module_init: PipewireModuleInit;
};

/// The `fops` functions pipewire stubs out using `RTLD_NEXT`. We forward to the implementations
/// under the `linux` namespace as these are direct system calls, we don't want to call the externs
/// as pipewire has overriden these and is using this API to get the originals.
pub const fops = struct {
    fn OPENAT64(
        dirfd: c_int,
        path: [*:0]const u8,
        oflag: c_int,
        mode: std.c.mode_t,
    ) callconv(.c) c_int {
        return @intCast(std.os.linux.openat(dirfd, path, @bitCast(oflag), mode));
    }

    fn dup(oldfd: c_int) callconv(.c) c_int {
        return @intCast(std.os.linux.dup(oldfd));
    }

    fn close(fd: c_int) callconv(.c) c_int {
        return @intCast(std.os.linux.close(fd));
    }

    fn ioctl(fd: c_int, request: c_ulong, arg: *anyopaque) callconv(.c) c_int {
        return @intCast(std.os.linux.ioctl(fd, @intCast(request), @intFromPtr(arg)));
    }

    fn mmap64(
        addr: ?[*]u8,
        length: usize,
        prot: c_int,
        flags: c_int,
        fd: c_int,
        offset: i64,
    ) callconv(.c) *anyopaque {
        return @ptrFromInt(std.os.linux.mmap(
            addr,
            length,
            @intCast(prot),
            @bitCast(flags),
            fd,
            offset,
        ));
    }

    fn munmap(addr: [*]const u8, length: usize) callconv(.c) c_int {
        return @intCast(std.os.linux.munmap(addr, length));
    }
};
