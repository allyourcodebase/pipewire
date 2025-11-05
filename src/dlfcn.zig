const std = @import("std");

const log = std.log.scoped(.dl);
const assert = std.debug.assert;

pub const Lib = struct {
    name: []const u8,
    symbols: std.StaticStringMap(*anyopaque),

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("@\"{f}\"", .{std.zig.fmtString(self.name)});
    }
};

const main_program = "@SELF";
const libs: std.StaticStringMap(Lib) = .initComptime(.{
    .{
        main_program,
        Lib{
            .name = main_program,
            .symbols = .initComptime(.{}),
        },
    },
    .{
        "pipewire-0.3/plugins/support/libspa-support.so",
        Lib{
            .name = "spa-support",
            .symbols = .initComptime(.{
                // Implement!
                // .{ "spa_handle_factory_enum", null },
            }),
        },
    },
});

export fn dlopen(path: ?[*:0]const c_char, flags: Flags) callconv(.c) ?*anyopaque {
    comptime assert(@sizeOf(c_char) == @sizeOf(u8));
    const path_u8: [*:0]const u8 = if (path) |p| @ptrCast(p) else main_program;
    const span = std.mem.span(path_u8);
    const lib = if (libs.getIndex(span)) |index| &libs.kvs.values[index] else null;
    log.info("dlopen(\"{f}\", {f}) -> {?f}", .{ std.zig.fmtString(span), flags, lib });
    return @ptrCast(@constCast(lib));
}

export fn dlclose(handle: ?*anyopaque) callconv(.c) c_int {
    const lib: *const Lib = @ptrCast(@alignCast(handle.?));
    log.info("dlclose({f})", .{lib});
    return 0;
}

export fn dlsym(noalias handle: ?*anyopaque, noalias name_c: ?[*:0]c_char) ?*anyopaque {
    const lib: *const Lib = @ptrCast(@alignCast(handle.?));
    const name = std.mem.span(@as([*:0]u8, @ptrCast(name_c.?)));
    const symbol = lib.symbols.get(name) orelse null;
    log.info("dlsym({f}, \"{f}\") -> 0x{x}", .{
        lib,
        std.zig.fmtString(name),
        @intFromPtr(symbol),
    });
    return symbol;
}

export fn dlerror() ?[*:0]const u8 {
    return null;
}

export fn dlinfo(noalias handle: ?*anyopaque, request: c_int, noalias info: ?*anyopaque) c_int {
    const lib: *const Lib = @ptrCast(@alignCast(handle.?)); // XXX: null allowed?
    log.info("dlinfo({f}, {}, {x})", .{ lib, request, @intFromPtr(info) });
    @panic("unimplemented");
}

const Flags = packed struct(c_int) {
    lazy: bool,
    now: bool,
    noload: bool,
    _pad0: u5 = 0,
    global: bool,
    _pad1: u3 = 0,
    nodelete: bool,
    _pad2: std.meta.Int(.unsigned, @bitSizeOf(c_int) - 13) = 0,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeAll(".{");
        var first = true;
        inline for (@typeInfo(@This()).@"struct".fields) |field| {
            const val = @field(self, field.name);
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
                else => comptime unreachable,
            }
        }
        if (!first) try writer.writeAll(" ");
        try writer.writeAll("}");
    }
};
