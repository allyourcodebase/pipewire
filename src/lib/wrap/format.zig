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
