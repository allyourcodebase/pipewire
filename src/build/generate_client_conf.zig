//! Generates the pipewire client config. We can almost use `addConfigHeader` for this with the
//! `autoconf_at` style, but not quite as it adds a c style comment to the first line (explaining
//! that the file is generated) which isn't allowed by this syntax.

const std = @import("std");
const options = @import("options");
const assert = std.debug.assert;

pub fn main(init: std.process.Init) !void {
    const gpa = init.arena.allocator();
    const io = init.io;

    var args = try init.minimal.args.iterateAllocator(gpa);
    defer args.deinit();
    _ = args.skip();
    const input_path = args.next().?;
    const output_path = args.next().?;
    assert(args.next() == null);

    const cwd = std.Io.Dir.cwd();

    const input = try cwd.openFile(io, input_path, .{});
    defer input.close(io);

    var input_buf: [4096]u8 = undefined;
    var reader = input.readerStreaming(io, &input_buf);

    const output = try cwd.createFile(io, output_path, .{});
    defer output.close(io);

    var output_buf: [4096]u8 = undefined;
    var writer = output.writerStreaming(io, &output_buf);

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
    try output.sync(io);
}
