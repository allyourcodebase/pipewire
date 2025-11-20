const std = @import("std");

/// The translated pipewire headers.
pub const c = @import("c");

/// The wrapped standard calls that make it possible to link pipewire statically.
pub const wrap = @import("wrap/root.zig");

comptime {
    // Force the compiler to reference all declarations in `wrap` since they contain externs.
    for (std.meta.declarations(wrap)) |decl| {
        _ = &@field(wrap, decl.name);
    }
}
