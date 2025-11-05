const std = @import("std");

const log = std.log.scoped(.dl); // XXX: use this
const gpa = std.heap.smp_allocator;
const assert = std.debug.assert;

export fn dlopen(path: ?[*:0]const c_char, flags: c_int) callconv(.c) ?*anyopaque {
    comptime assert(@sizeOf(c_char) == @sizeOf(u8));
    const path_u8: ?[*:0]const u8 = @ptrCast(path);
    log.info("dlopen({?s}, {})", .{ path_u8, flags });

    const span = std.mem.span(path_u8 orelse return null);
    const handle = gpa.dupeZ(u8, span) catch return null;
    return handle.ptr;
}

export fn dlclose(handle: ?*anyopaque) callconv(.c) c_int {
    comptime assert(@sizeOf(c_char) == @sizeOf(u8));
    const path: [*:0]const u8 = @ptrCast(handle.?);
    log.info("dlclose({s})", .{path});

    gpa.free(std.mem.span(path));
    return 0;
}

export fn dlsym(noalias handle: *anyopaque, noalias symbol_c: ?[*:0]c_char) ?*anyopaque {
    const path: ?[*:0]u8 = @ptrCast(handle);
    const symbol: ?[*:0]u8 = @ptrCast(symbol_c);
    log.info("dlsym({?s}, {?s})", .{ path, symbol });

    log.err("dlsym unimplemented!", .{});
    return null;
}

export fn dlerror() ?[*:0]const u8 {
    return null;
}
