// `pipewire/src/examples/audio-src.c` translated to Zig.

const std = @import("std");
const example_options = @import("example_options");
const log = std.log;
const tau: f32 = std.math.tau;

// Configure logging
pub const std_options: std.Options = .{
    .logFn = logFn,
};

// Normal code wouldn't need this conditional, we're just demonstrating both the static library and
// the Zig module here. Prefer the Zig module when possible. We wrap the C module in a struct just
// to make it look like the Zig module so that the rest of the file can use it as is.
const pw = if (example_options.use_zig_module)
    @import("pipewire")
else
    struct {
        pub const c = @import("pipewire");
    };

const dbg_ctx = pw.Logger.dbgCtx(.info, pw.Logger.scope);

const global = struct {
    const sample_rate = 44100;
    const channel_count = 2;
    const volume = 0.1;

    var accumulator: f32 = 0;

    var runtime_log_level: std.log.Level = .info;

    var loop: ?*pw.c.pw_main_loop = null;
    var stream: ?*pw.c.pw_stream = null;
};

pub fn main() !void {
    // If we're linking with the Zig module, set up logging.
    var logger = if (example_options.use_zig_module) pw.Logger.init() else {};
    if (example_options.use_zig_module) {
        pw.c.pw_log_set(&logger);
        pw.c.pw_log_set_level(pw.Logger.default_level);
    }

    // Configure our runtime log level
    const log_level_env_var = "AUDIO_SRC_LOG_LEVEL";
    if (std.posix.getenv(log_level_env_var)) |level_str| {
        const levels: std.StaticStringMap(std.log.Level) = .initComptime(.{
            .{ "debug", .debug },
            .{ "info", .info },
            .{ "warn", .warn },
            .{ "err", .err },
        });
        if (levels.get(level_str)) |level| {
            global.runtime_log_level = level;
        } else {
            log.err("{s}: unknown level \"{s}\"", .{ log_level_env_var, level_str });
        }
    }

    pw.c.pw_init(0, null);
    defer pw.c.pw_deinit();

    // make a main loop. If you already have another main loop, you can add
    // the fd of this pipewire mainloop to it.
    global.loop = pw.c.pw_main_loop_new(null).?;
    defer pw.c.pw_main_loop_destroy(global.loop);

    // Create a simple stream, the simple stream manages the core and remote
    // objects for you if you don't need to deal with them.
    //
    // If you plan to autoconnect your stream, you need to provide at least
    // media, category and role properties.
    //
    // Pass your events and a user_data pointer as the last arguments. This
    // will inform you about the stream state. The most important event
    // you need to listen to is the process event where you need to produce
    // the data.
    const props = pw.c.pw_properties_new(
        pw.c.PW_KEY_MEDIA_TYPE,
        "Audio",
        pw.c.PW_KEY_MEDIA_CATEGORY,
        "Playback",
        pw.c.PW_KEY_MEDIA_ROLE,
        "Music",
        @as(?*anyopaque, null),
    ).?;

    // Set stream target if given on command line
    var args: std.process.ArgIterator = .init();
    _ = args.skip();
    if (args.next()) |arg| check(pw.c.pw_properties_set(props, pw.c.PW_KEY_TARGET_OBJECT, arg));

    global.stream = pw.c.pw_stream_new_simple(
        pw.c.pw_main_loop_get_loop(global.loop),
        "audio-src",
        props,
        &.{
            .version = pw.c.PW_VERSION_STREAM_EVENTS,
            .process = &onProcess,
        },
        null,
    ).?;
    defer pw.c.pw_stream_destroy(global.stream);

    var buffer: [1024]u8 align(@alignOf(u32)) = undefined;
    var b = std.mem.zeroInit(pw.c.spa_pod_builder, .{
        .data = &buffer,
        .size = buffer.len,
    });

    // Make one parameter with the supported formats.
    var params: [1]?*const pw.c.spa_pod = undefined;
    var f: pw.c.spa_pod_frame = undefined;
    check(pw.c.spa_pod_builder_push_object(
        &b,
        &f,
        pw.c.SPA_TYPE_OBJECT_Format,
        pw.c.SPA_PARAM_EnumFormat,
    ));

    check(pw.c.spa_pod_builder_prop(&b, pw.c.SPA_FORMAT_mediaType, 0));
    check(pw.c.spa_pod_builder_id(&b, pw.c.SPA_MEDIA_TYPE_audio));

    check(pw.c.spa_pod_builder_prop(&b, pw.c.SPA_FORMAT_mediaSubtype, 0));
    check(pw.c.spa_pod_builder_id(&b, pw.c.SPA_MEDIA_SUBTYPE_raw));

    check(pw.c.spa_pod_builder_prop(&b, pw.c.SPA_FORMAT_AUDIO_format, 0));
    check(pw.c.spa_pod_builder_id(&b, pw.c.SPA_AUDIO_FORMAT_F32));

    check(pw.c.spa_pod_builder_prop(&b, pw.c.SPA_FORMAT_AUDIO_rate, 0));
    check(pw.c.spa_pod_builder_int(&b, global.sample_rate));

    check(pw.c.spa_pod_builder_prop(&b, pw.c.SPA_FORMAT_AUDIO_channels, 0));
    check(pw.c.spa_pod_builder_int(&b, global.channel_count));

    const format: *const pw.c.spa_pod = @ptrCast(@alignCast(pw.c.spa_pod_builder_pop(&b, &f)));
    if (example_options.use_zig_module) {
        check(pw.c.spa_debugc_format(dbg_ctx, 2, null, format));
    }
    params[0] = format;

    // Now connect this stream. We ask that our process function is
    // called in a realtime thread.
    check(pw.c.pw_stream_connect(
        global.stream,
        pw.c.PW_DIRECTION_OUTPUT,
        pw.c.PW_ID_ANY,
        pw.c.PW_STREAM_FLAG_AUTOCONNECT |
            pw.c.PW_STREAM_FLAG_MAP_BUFFERS |
            pw.c.PW_STREAM_FLAG_RT_PROCESS,
        &params,
        1,
    ));

    // and wait while we let things run
    check(pw.c.pw_main_loop_run(global.loop));
}

// our data processing function is in general:
//
// const b: *pw.c.pw_buffer = pw.c.pw_stream_dequeue_buffer(stream);
// defer pw.c.pw_stream_queue_buffer(stream, b);
//
// .. generate stuff in the buffer ...
fn onProcess(userdata: ?*anyopaque) callconv(.c) void {
    _ = userdata;

    var maybe_buffer: ?*pw.c.pw_buffer = null;
    while (true) {
        const t = pw.c.pw_stream_dequeue_buffer(global.stream) orelse break;
        if (maybe_buffer) |b| check(pw.c.pw_stream_queue_buffer(global.stream, b));
        maybe_buffer = t;
    }
    const b = maybe_buffer orelse {
        log.warn("out of buffers", .{});
        return;
    };
    defer check(pw.c.pw_stream_queue_buffer(global.stream, b));

    const buf: *pw.c.spa_buffer = b.buffer;

    log.debug("new buffer {*}", .{buf});

    const ddata = buf.datas[0].data orelse return;
    var dst: [*]f32 = @ptrCast(@alignCast(ddata));

    const stride = @sizeOf(f32) * global.channel_count;
    var frame_count = buf.datas[0].maxsize / stride;
    if (b.requested != 0) frame_count = @min(b.requested, frame_count);

    for (0..frame_count) |_| {
        global.accumulator += tau * 440 / global.sample_rate;
        if (global.accumulator >= tau) global.accumulator -= tau;
        const sample = @sin(global.accumulator) * global.volume;
        for (0..global.channel_count) |_| {
            dst[0] = sample;
            dst += 1;
        }
    }

    buf.datas[0].chunk.*.offset = 0;
    buf.datas[0].chunk.*.stride = stride;
    buf.datas[0].chunk.*.size = frame_count * stride;
}

fn check(res: c_int) void {
    if (res != 0) {
        std.debug.panic("pipewire call failed: {s}", .{pw.c.spa_strerror(res)});
    }
}

pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    if (@intFromEnum(level) > @intFromEnum(global.runtime_log_level)) return;
    std.log.defaultLog(level, scope, format, args);
}
