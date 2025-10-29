const std = @import("std");
const options = @import("options");

const assert = std.debug.assert;

/// Generate the pipewire config. We can almost use `addConfigHeader` for this with the
/// `autoconf_at` style, but not quite as it adds a c style comment to the first line (explaining
/// that the file is generated) which isn't allowed by this syntax.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = false }){};
    defer if (gpa.deinit() != .ok) @panic("leak detected");
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const input_path = args[1];
    const output_path = args[2];
    assert(args.len == 3);

    const cwd = std.fs.cwd();

    const input = try cwd.openFile(input_path, .{});
    defer input.close();

    var input_buf: [4096]u8 = undefined;
    var reader = input.readerStreaming(&input_buf);

    const output = try cwd.createFile(output_path, .{});
    defer output.close();

    var output_buf: [4096]u8 = undefined;
    var writer = output.writerStreaming(&output_buf);

    while (true) {
        _ = reader.interface.streamDelimiter(&writer.interface, '@') catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        reader.interface.toss(1);
        const name = try reader.interface.takeSentinel('@');
        inline for (@typeInfo(options).@"struct".decls) |decl| {
            if (std.mem.eql(u8, name, decl.name)) {
                try writer.interface.writeAll(@field(options, decl.name));
                break;
            }
        } else std.debug.panic("missing option {s}", .{name});
    }

    try writer.interface.flush();
    try output.sync();
}
