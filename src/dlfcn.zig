const std = @import("std");

const log = std.log.scoped(.dl);
const assert = std.debug.assert;

const support = struct {
    pub const c = @cImport({
        @cInclude("spa/support/plugin.h");
        @cInclude("spa/support/log.h");
    });

    extern const spa_log_topic_enum: c.spa_log_topic_enum;
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
        "pipewire-0.3/plugins/support/libspa-support.so",
        Lib{
            .name = "spa-support",
            .symbols = .initComptime(.{
                .{ "spa_handle_factory_enum", Lib.sym(&support.c.spa_handle_factory_enum) },
                .{ "spa_log_topic_enum", Lib.sym(&support.spa_log_topic_enum) },
            }),
        },
    },
});

export fn dlopen(path: ?[*:0]const u8, mode: std.c.RTLD) callconv(.c) ?*anyopaque {
    const span = if (path) |p| std.mem.span(p) else Lib.main_program_name;
    const lib = if (libs.getIndex(span)) |index| &libs.kvs.values[index] else null;
    log.info("dlopen(\"{f}\", {f}) -> {?f}", .{ std.zig.fmtString(span), FmtMode.init(mode), lib });
    return @ptrCast(@constCast(lib));
}

export fn dlclose(handle: ?*anyopaque) callconv(.c) c_int {
    const lib: *const Lib = @ptrCast(@alignCast(handle.?));
    log.info("dlclose({f})", .{lib});
    return 0;
}

export fn dlsym(noalias handle: ?*anyopaque, noalias name: [*:0]u8) ?*anyopaque {
    const lib: *const Lib = @ptrCast(@alignCast(handle.?));
    const span = std.mem.span(name);
    var msg: ?[:0]const u8 = null;
    const symbol = lib.symbols.get(span) orelse b: {
        msg = "symbol not found";
        break :b null;
    };
    log.info("dlsym({f}, \"{f}\") -> 0x{x} ({s})", .{
        lib,
        std.zig.fmtString(span),
        @intFromPtr(symbol),
        if (msg) |m| m else "success",
    });
    if (msg) |m| err = m;
    return symbol;
}

var err: ?[*:0]const u8 = null;
export fn dlerror() ?[*:0]const u8 {
    const result = err;
    err = null;
    return result;
}

export fn dlinfo(noalias handle: ?*anyopaque, request: c_int, noalias info: ?*anyopaque) c_int {
    const lib: *const Lib = @ptrCast(@alignCast(handle.?)); // XXX: null allowed?
    log.info("dlinfo({f}, {}, {x})", .{ lib, request, @intFromPtr(info) });
    @panic("unimplemented");
}

pub const Lib = struct {
    const main_program_name = "@SELF";

    name: []const u8,
    symbols: std.StaticStringMap(*anyopaque),

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("@\"{f}\"", .{std.zig.fmtString(self.name)});
    }

    pub fn sym(val: anytype) *anyopaque {
        return @ptrCast(@constCast(val));
    }
};

pub const FmtMode = struct {
    val: std.c.RTLD,

    pub fn init(val: std.c.RTLD) @This() {
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
                else => comptime unreachable,
            }
        }
        if (!first) try writer.writeAll(" ");
        try writer.writeAll("}");
    }
};
