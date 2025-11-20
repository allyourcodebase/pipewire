//! Wraps various standard calls to make it possible to link statically with pipewire.

const std = @import("std");
const assert = std.debug.assert;

pub const dlfcn = @import("dlfcn.zig");
pub const fcntl = @import("fcntl.zig");

// Check type assumptions.
comptime {
    assert(@sizeOf(c_char) == @sizeOf(u8));
}
