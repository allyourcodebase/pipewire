const std = @import("std");

pub const c = @import("c");
pub const wrap = @import("wrap.zig");

// Imports are lazy, but we need the wrap imports to get processed since they declare externs.
comptime {
    for (std.meta.declarations(wrap)) |decl| {
        _ = &@field(wrap, decl.name);
    }
}
