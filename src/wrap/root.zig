//! Wraps various standard calls to make it possible to link statically with pipewire.

const std = @import("std");
const assert = std.debug.assert;

pub const dlfcn = @import("dlfcn.zig");
pub const fs = @import("fs.zig");

comptime {
    // Check type assumptions.
    assert(@sizeOf(c_char) == @sizeOf(u8));

    // Reference all decls since they include exports.
    for (std.meta.declarations(@This())) |decl| {
        _ = &@field(@This(), decl.name);
    }
}
