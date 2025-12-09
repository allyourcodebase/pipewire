pub const std = @import("std");

pub fn fmtFlags(val: anytype) FmtFlags(@TypeOf(val)) {
    return .init(val);
}

/// Formats flags, skipping any values that are 0 for brevity.
pub fn FmtFlags(T: type) type {
    return struct {
        val: T,

        fn init(val: T) @This() {
            return .{ .val = val };
        }

        fn prefix(writer: *std.Io.Writer, first: *bool) !void {
            if (!first.*) {
                try writer.writeAll(",");
            }
            try writer.writeAll(" ");
            first.* = false;
        }

        pub fn format(self: anytype, writer: *std.Io.Writer) std.Io.Writer.Error!void {
            var first = true;
            try writer.writeAll(".{");
            inline for (@typeInfo(@TypeOf(self.val)).@"struct".fields) |field| {
                const val = @field(self.val, field.name);
                switch (@typeInfo(field.type)) {
                    .bool => if (val) {
                        try prefix(writer, &first);
                        try writer.print(".{s} = true", .{field.name});
                    },
                    .int => if (val != 0) {
                        try prefix(writer, &first);
                        try writer.print(".{s} = {x}", .{ field.name, val });
                    },
                    .@"enum" => {
                        if (val != enumFromInt(field.type, 0)) {
                            try writer.print(".{s} = {t}", .{ field.name, val });
                        }
                    },
                    else => if (!std.meta.eql(val, std.mem.zeroes(field.type))) {
                        try prefix(writer, &first);
                        try writer.print(".{s} = {any}", .{ field.name, val });
                    },
                }
            }
            if (!first) try writer.writeAll(" ");
            try writer.writeAll("}");
        }
    };
}

// https://codeberg.org/ziglang/zig/pulls/30156
pub fn enumFromInt(comptime E: type, integer: anytype) ?E {
    const enum_info = @typeInfo(E).@"enum";
    if (!enum_info.is_exhaustive) {
        if (std.math.cast(enum_info.tag_type, integer)) |tag| {
            return @enumFromInt(tag);
        }
        return null;
    }
    // We don't directly iterate over the fields of E, as that
    // would require an inline loop. Instead, we create an array of
    // values that is comptime-know, but can be iterated at runtime
    // without requiring an inline loop.
    // This generates better machine code.
    for (std.enums.values(E)) |value| {
        if (@intFromEnum(value) == integer) return value;
    }
    return null;
}
