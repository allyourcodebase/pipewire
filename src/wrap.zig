const std = @import("std");

const log = std.log.scoped(.dl);
const assert = std.debug.assert;

const c = @cImport({
    @cInclude("spa/support/plugin.h");
    @cInclude("spa/support/log.h");
    @cInclude("dlfcn.h");
});

const plugins = struct {
    const SpaHandleFactoryEnum = fn (?*anyopaque, factory: ?*anyopaque) callconv(.c) c_int;

    extern const spa_support__spa_handle_factory_enum: SpaHandleFactoryEnum;
    extern const spa_videoconvert__spa_handle_factory_enum: SpaHandleFactoryEnum;

    extern const spa_support__spa_log_topic_enum: c.spa_log_topic_enum;
    extern const spa_videoconvert__spa_log_topic_enum: c.spa_log_topic_enum;
};

const modules = struct {
    const PipewireModuleInit = fn (_: ?*anyopaque, _: ?*anyopaque) callconv(.c) void;

    extern const pipewire_module_protocol_native__pipewire__module_init: PipewireModuleInit;
    extern const pipewire_module_client_node__pipewire__module_init: PipewireModuleInit;
    extern const pipewire_module_client_device__pipewire__module_init: PipewireModuleInit;
    extern const pipewire_module_adapter__pipewire__module_init: PipewireModuleInit;
    extern const pipewire_module_metadata__pipewire__module_init: PipewireModuleInit;
    extern const pipewire_module_session_manager__pipewire__module_init: PipewireModuleInit;
};

const fops = struct {
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

const libs: std.StaticStringMap(Lib) = .initComptime(.{
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
            .name = "spa-support",
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

export fn __wrap_dlopen(path: ?[*:0]const u8, mode: std.c.RTLD) callconv(.c) ?*anyopaque {
    const span = if (path) |p| std.mem.span(p) else Lib.main_program_name;
    const lib = if (libs.getIndex(span)) |index| &libs.kvs.values[index] else null;
    log.debug("dlopen(\"{f}\", {f}) -> {?f}", .{
        std.zig.fmtString(span),
        FmtFlags(std.c.RTLD).init(mode),
        lib,
    });
    return @ptrCast(@constCast(lib));
}

export fn __wrap_dlclose(handle: ?*anyopaque) callconv(.c) c_int {
    const lib: *const Lib = @ptrCast(@alignCast(handle.?));
    log.debug("dlclose({f})", .{lib});
    return 0;
}

export fn __wrap_dlsym(noalias handle: ?*anyopaque, noalias name: [*:0]u8) ?*anyopaque {
    const lib: *const Lib = @ptrCast(@alignCast(handle.?));
    const span = std.mem.span(name);
    var msg: ?[:0]const u8 = null;
    const symbol = b: {
        if (handle == c.RTLD_NEXT) {
            break :b lib.symbols.get(Lib.rtld_next_name).?;
        }
        const symbol = lib.symbols.get(span) orelse {
            msg = "symbol not found";
            break :b null;
        };
        break :b symbol;
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

var err: ?[*:0]const u8 = null;
export fn __wrap_dlerror() ?[*:0]const u8 {
    const result = err;
    err = null;
    return result;
}

export fn __wrap_dlinfo(
    noalias handle: ?*anyopaque,
    request: c_int,
    noalias info: ?*anyopaque,
) c_int {
    const lib: *const Lib = @ptrCast(@alignCast(handle.?));
    log.debug("dlinfo({f}, {}, {x})", .{ lib, request, @intFromPtr(info) });
    @panic("unimplemented");
}

const Lib = struct {
    const main_program_name = "@SELF";
    const rtld_next_name = "@RTLD_NEXT";

    name: []const u8,
    symbols: std.StaticStringMap(*anyopaque),

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("@\"{f}\"", .{std.zig.fmtString(self.name)});
    }

    fn sym(val: anytype) *anyopaque {
        return @ptrCast(@constCast(val));
    }
};

fn FmtFlags(T: type) type {
    return struct {
        val: T,

        fn init(val: T) @This() {
            return .{ .val = val };
        }

        pub fn format(self: anytype, writer: *std.Io.Writer) std.Io.Writer.Error!void {
            try writer.writeAll(".{");
            var first = true;
            inline for (@typeInfo(@TypeOf(self.val)).@"struct".fields) |field| {
                const val = @field(self.val, field.name);
                switch (@typeInfo(field.type)) {
                    .bool => if (val) {
                        if (!first) {
                            try writer.writeAll(",");
                        }
                        first = false;
                        try writer.writeAll(" ");
                        try writer.print(".{s} = true", .{field.name});
                    },
                    .int => if (val != 0) {
                        if (!first) {
                            try writer.writeAll(", ");
                            first = false;
                        }
                        try writer.print(".{s} = {x}", .{ field.name, val });
                    },
                    else => if (!std.meta.eql(val, std.mem.zeroes(field.type))) {
                        try writer.print(".{s} = {any}", .{ field.name, val });
                    },
                }
            }
            if (!first) try writer.writeAll(" ");
            try writer.writeAll("}");
        }
    };
}

export fn __wrap_stat(pathname_c: [*:0]const u8, statbuf: *std.os.linux.Stat) usize {
    const pathname = std.mem.span(pathname_c);
    const result, const strategy = b: {
        if (std.mem.endsWith(u8, pathname, ".so")) {
            statbuf.* = std.mem.zeroInit(std.os.linux.Stat, .{ .mode = std.c.S.IFREG });
            break :b .{ 0, "faked" };
        } else {
            break :b .{ std.os.linux.stat(pathname_c, statbuf), "real" };
        }
    };
    log.debug("stat(\"{f}\", {*}) -> {} (statbuf.* == {f}) ({s})", .{
        std.zig.fmtString(pathname),
        statbuf,
        result,
        FmtFlags(std.os.linux.Stat).init(statbuf.*),
        strategy,
    });
    return result;
}
