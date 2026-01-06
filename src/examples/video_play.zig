//! `pipewire/src/examples/video-play.c` translated to Zig and ported from SDL to Zin to demonstrate
//! video without a dynamic linker. This is not an efficient way to render, each pixel is rendered
//! as a rectangle, in a real application you'll want a better strategy for this.

const builtin = @import("builtin");
const std = @import("std");
const zin = @import("zin");
const win32 = zin.platform.win32;
const log = std.log;
const example_options = @import("example_options");
const assert = std.debug.assert;

const Allocator = std.mem.Allocator;

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

// Configure zin
pub const zin_config: zin.Config = .{
    .StaticWindowId = enum {
        main,
        pub fn getConfig(self: @This()) zin.WindowConfigData {
            return switch (self) {
                .main => .{
                    .window_size_events = true,
                    .key_events = true,
                    .mouse_events = true,
                    .timers = .one,
                    .background = .{ .r = 49, .g = 49, .b = 49 },
                    .dynamic_background = false,
                    .win32 = .{ .render = .{ .gdi = .{} } },
                    .x11 = .{ .render_kind = .double_buffered },
                },
            };
        }
    },
};

// Video settings
const texel_width = 10;
const max_buffers = 64;
const default_video_width = 160;
const default_video_height = 90;
const default_frame_rate = 60;
const max_frame_rate = 120;

// Global state used by Zin and Pipewire
const global = struct {
    const default_timer_period_ns = 16 * std.time.ns_per_ms;

    var runtime_log_level: std.log.Level = .info;

    var last_render: ?std.time.Instant = null;
    var timer_period_ns: u64 = 0;

    var loop: ?*pw.c.pw_main_loop = null;
    var stream: ?*pw.c.pw_stream = null;

    var position: ?*pw.c.spa_io_position = null;

    var format: pw.c.spa_video_info = .{};
    var stride: i32 = 0;
    var size: pw.c.spa_rectangle = .{};

    var rect: Rect = .{};
    var is_yuv: bool = false;

    var current_buffer: ?*pw.c.pw_buffer = null;
};

pub fn main() !void {
    // If we're linking with the Zig module, set up logging.
    var logger = if (example_options.use_zig_module) pw.Logger.init() else {};
    if (example_options.use_zig_module) {
        pw.c.pw_log_set(&logger);
        pw.c.pw_log_set_level(pw.Logger.default_level);
    }

    // Configure our runtime log level
    const log_level_env_var = "VIDEO_PLAY_LOG_LEVEL";
    if (std.posix.getenv("VIDEO_PLAY_LOG_LEVEL")) |level_str| {
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

    // Initialize pipewire
    pw.c.pw_init(0, null);
    defer pw.c.pw_deinit();

    // Create the pipewire loop
    global.loop = pw.c.pw_main_loop_new(null).?;
    defer pw.c.pw_main_loop_destroy(global.loop);

    // Create the pipewire stream
    {
        const props = pw.c.pw_properties_new(
            pw.c.PW_KEY_MEDIA_TYPE,
            "Video",
            pw.c.PW_KEY_MEDIA_CATEGORY,
            "Capture",
            pw.c.PW_KEY_MEDIA_ROLE,
            "Camera",
            @as(?*anyopaque, null),
        ).?;

        var args: std.process.ArgIterator = .init();
        _ = args.next();
        if (args.next()) |arg| {
            check(pw.c.pw_properties_set(props, pw.c.PW_KEY_TARGET_OBJECT, arg));
        }

        global.stream = pw.c.pw_stream_new_simple(
            pw.c.pw_main_loop_get_loop(global.loop),
            "video-play",
            props,
            &.{
                .version = pw.c.PW_VERSION_STREAM_EVENTS,
                .state_changed = &onStreamStateChanged,
                .io_changed = &onStreamIoChanged,
                .param_changed = &onStreamParamChanged,
                .process = &onProcess,
            },
            null,
        ).?;
    }
    defer pw.c.pw_stream_destroy(global.stream);

    // Connect to the stream
    {
        var builder_buf: [1024]u8 align(@alignOf(u32)) = undefined;
        var b = std.mem.zeroInit(pw.c.spa_pod_builder, .{
            .data = &builder_buf,
            .size = builder_buf.len,
        });

        var params_buf: [2]?*const pw.c.spa_pod = undefined;
        var params: std.ArrayList(?*const pw.c.spa_pod) = .initBuffer(&params_buf);

        // Tell pipewire which formats we support
        {
            var format_frame: pw.c.spa_pod_frame = undefined;
            check(pw.c.spa_pod_builder_push_object(
                &b,
                &format_frame,
                pw.c.SPA_TYPE_OBJECT_Format,
                pw.c.SPA_PARAM_EnumFormat,
            ));
            check(pw.c.spa_pod_builder_prop(&b, pw.c.SPA_FORMAT_mediaType, 0));
            check(pw.c.spa_pod_builder_id(&b, pw.c.SPA_MEDIA_TYPE_video));
            check(pw.c.spa_pod_builder_prop(&b, pw.c.SPA_FORMAT_mediaSubtype, 0));
            check(pw.c.spa_pod_builder_id(&b, pw.c.SPA_MEDIA_SUBTYPE_raw));

            // Tell pipewire we prefer yuy2 since it's the only one we currently support, but tell
            // it that we support all other formats as fallbacks so we have a chance to respond if
            // that's what webcam gives us.
            {
                var choice_frame: pw.c.spa_pod_frame = undefined;
                check(pw.c.spa_pod_builder_prop(&b, pw.c.SPA_FORMAT_VIDEO_format, 0));
                check(pw.c.spa_pod_builder_push_choice(&b, &choice_frame, pw.c.SPA_CHOICE_Enum, 0));
                check(pw.c.spa_pod_builder_id(&b, pw.c.SPA_VIDEO_FORMAT_YUY2));
                for (all_formats) |format| {
                    check(pw.c.spa_pod_builder_id(&b, format));
                }
                assert(pw.c.spa_pod_builder_pop(&b, &choice_frame) != null);
            }

            // Set the resolutions we support. We default pretty low since we're rendering a
            // rectangle per pixel.
            {
                var choice_frame: pw.c.spa_pod_frame = undefined;
                check(pw.c.spa_pod_builder_prop(&b, pw.c.SPA_FORMAT_VIDEO_size, 0));
                check(pw.c.spa_pod_builder_push_choice(&b, &choice_frame, pw.c.SPA_CHOICE_Range, 0));
                check(pw.c.spa_pod_builder_rectangle(&b, default_video_width, default_video_height));
                check(pw.c.spa_pod_builder_rectangle(&b, 1, 1));
                check(pw.c.spa_pod_builder_rectangle(&b, default_video_width, default_video_height));
                assert(pw.c.spa_pod_builder_pop(&b, &choice_frame) != null);
            }

            // Tell pipewire what framerates we support.
            {
                var choice_frame: pw.c.spa_pod_frame = undefined;
                check(pw.c.spa_pod_builder_prop(&b, pw.c.SPA_FORMAT_VIDEO_framerate, 0));
                check(pw.c.spa_pod_builder_push_choice(&b, &choice_frame, pw.c.SPA_CHOICE_Range, 0));
                check(pw.c.spa_pod_builder_fraction(&b, default_frame_rate, 1));
                check(pw.c.spa_pod_builder_fraction(&b, 0, 1));
                check(pw.c.spa_pod_builder_fraction(&b, max_frame_rate, 1));
                assert(pw.c.spa_pod_builder_pop(&b, &choice_frame) != null);
            }

            // Log the supported formats
            const format: *pw.c.spa_pod = @ptrCast(@alignCast(pw.c.spa_pod_builder_pop(&b, &format_frame).?));
            if (example_options.use_zig_module) {
                log.info("supported formats:", .{});
                check(pw.c.spa_debugc_format(dbg_ctx, 2, null, format));
            }

            // Add the supported formats to our params
            params.appendBounded(format) catch @panic("OOB");
        }

        // Request the webcam feed
        {
            var format_frame: pw.c.spa_pod_frame = undefined;
            check(pw.c.spa_pod_builder_push_object(&b, &format_frame, pw.c.SPA_TYPE_OBJECT_Format, pw.c.SPA_PARAM_EnumFormat));

            check(pw.c.spa_pod_builder_prop(&b, pw.c.SPA_FORMAT_mediaType, 0));
            check(pw.c.spa_pod_builder_id(&b, pw.c.SPA_MEDIA_TYPE_video));

            check(pw.c.spa_pod_builder_prop(&b, pw.c.SPA_FORMAT_mediaSubtype, 0));
            check(pw.c.spa_pod_builder_id(&b, pw.c.SPA_MEDIA_SUBTYPE_dsp));

            check(pw.c.spa_pod_builder_prop(&b, pw.c.SPA_FORMAT_VIDEO_format, 0));
            check(pw.c.spa_pod_builder_id(&b, pw.c.SPA_VIDEO_FORMAT_DSP_F32));

            const format: *const pw.c.spa_pod = @ptrCast(@alignCast(pw.c.spa_pod_builder_pop(&b, &format_frame)));
            if (example_options.use_zig_module) {
                check(pw.c.spa_debugc_format(dbg_ctx, 2, null, format));
            }
            params.appendBounded(format) catch @panic("OOB");
        }

        // Connect to the stream, start inactive we'll active it later
        const res = pw.c.pw_stream_connect(
            global.stream,
            pw.c.PW_DIRECTION_INPUT,
            pw.c.PW_ID_ANY,
            pw.c.PW_STREAM_FLAG_AUTOCONNECT |
                pw.c.PW_STREAM_FLAG_INACTIVE |
                pw.c.PW_STREAM_FLAG_MAP_BUFFERS,
            params.items.ptr,
            @intCast(params.items.len),
        );
        if (res < 0) {
            log.err("can't connect: {s}", .{pw.c.spa_strerror(res)});
            std.process.exit(1);
        }
    }

    // Setup Zin
    try zin.processInit(.{});
    {
        var err: zin.X11ConnectError = undefined;
        zin.x11Connect(&err) catch std.debug.panic("X11 connect failed: {f}", .{err});
    }
    defer zin.x11Disconnect();

    zin.staticWindow(.main).registerClass(.{
        .callback = windowEvent,
        .win32_name = zin.L("VideoPlay"),
        .macos_view = "VideoPlay",
    }, .{
        .win32_icon_large = .none,
        .win32_icon_small = .none,
    });
    defer zin.staticWindow(.main).unregisterClass();

    try zin.staticWindow(.main).create(.{
        .title = "Video Play",
        .size = .{ .client_points = .{
            .x = default_video_width * texel_width,
            .y = default_video_height * texel_width,
        } },
        .pos = null,
    });
    defer zin.staticWindow(.main).destroy();
    zin.staticWindow(.main).show();

    // Start a timer with the default timer period since we don't have a video feed yet, and call
    // our callback once on startup so we don't have to wait for one timer period to elapse.
    startTimerNanos(global.default_timer_period_ns);
    windowEvent(.{ .timer = {} });

    // Start the main loop.
    try zin.mainLoop();
}

/// Process a window event.
fn windowEvent(cb: zin.Callback(.{ .static = .main })) void {
    switch (cb) {
        .close => zin.quitMainLoop(),
        .window_size => {},
        .draw => |d| render(d),
        .timer => {
            pipewireFlush();
            zin.staticWindow(.main).invalidate();
        },
        else => {},
    }
}

/// Flush all pending pipewire events.
fn pipewireFlush() void {
    while (true) {
        const result = pw.c.pw_loop_iterate(pw.c.pw_main_loop_get_loop(global.loop), 0);
        if (result == 0) break;
        if (result < 0) {
            std.log.err("pipewire error {}", .{result});
            zin.quitMainLoop();
            break;
        }
    }
}

/// Handle the stream options changing.
fn onStreamStateChanged(
    userdata: ?*anyopaque,
    old: pw.c.pw_stream_state,
    state: pw.c.pw_stream_state,
    err: [*c]const u8,
) callconv(.c) void {
    _ = old;
    _ = userdata;

    global.current_buffer = null;

    if (err != null) {
        log.err("stream state: \"{s}\" (error={s})", .{ pw.c.pw_stream_state_as_string(state), err });
    } else {
        log.info("stream state: \"{s}\"", .{pw.c.pw_stream_state_as_string(state)});
    }

    if (state == pw.c.PW_STREAM_STATE_PAUSED) {
        check(pw.c.pw_stream_set_active(global.stream, true));
    }

    if (state != pw.c.PW_STREAM_STATE_STREAMING) {
        startTimerNanos(global.default_timer_period_ns);
    }
}

/// Handle the stream IO state changing.
fn onStreamIoChanged(userdata: ?*anyopaque, id: u32, area: ?*anyopaque, size: u32) callconv(.c) void {
    _ = size;
    _ = userdata;
    if (id == pw.c.SPA_IO_Position) {
        global.position = @ptrCast(@alignCast(area));
    }
}

/// Handle the stream parameters changing.
fn onStreamParamChanged(userdata: ?*anyopaque, id: u32, param: [*c]const pw.c.spa_pod) callconv(.c) void {
    _ = userdata;

    const stream = global.stream;
    var params_buffer: [1024]u8 align(@alignOf(u32)) = undefined;
    var b: pw.c.spa_pod_builder = .{
        .data = &params_buffer,
        .size = params_buffer.len,
        ._padding = 0,
        .state = .{ .offset = 0, .flags = 0, .frame = null },
        .callbacks = .{ .funcs = null, .data = null },
    };

    // Fail if the pod is invalid
    if (param != null and id == pw.c.SPA_PARAM_Tag) {
        log.err("invalid pod", .{});
        return;
    }

    // Handle latency changing
    if (param != null and id == pw.c.SPA_PARAM_Latency) {
        var info: pw.c.spa_latency_info = undefined;
        if (pw.c.spa_latency_parse(param, &info) >= 0) {
            log.info("got latency: {}ns", .{@divTrunc((info.min_ns + info.max_ns), 2)});
        }
        return;
    }

    // Clear the format if requested
    if (param == null or id != pw.c.SPA_PARAM_Format) return;

    // Log the new format
    if (example_options.use_zig_module) {
        log.info("got format:", .{});
        check(pw.c.spa_debugc_format(dbg_ctx, 2, null, param));
    }

    // Parse the new format and reset our timer to the new interval
    var parsed: pw.c.spa_video_info_raw = undefined;
    if (pw.c.spa_format_video_raw_parse(param, &parsed) < 0) {
        std.debug.panic("failed to parse format", .{});
    }
    if (pw.c.spa_format_parse(param, &global.format.media_type, &global.format.media_subtype) < 0) {
        return;
    }
    if (global.format.media_type != pw.c.SPA_MEDIA_TYPE_video) return;
    const num: f32 = @floatFromInt(parsed.framerate.num);
    const denom: f32 = @floatFromInt(parsed.framerate.denom);
    const hz = denom / num;
    startTimerNanos(@intFromFloat(hz * std.time.ns_per_s));

    // Check what format we got
    const format, const mult: i32 = switch (global.format.media_subtype) {
        pw.c.SPA_MEDIA_SUBTYPE_raw => b: {
            // call a helper function to parse the format for us.
            _ = pw.c.spa_format_video_raw_parse(param, &global.format.info.raw);
            global.size = pw.c.SPA_RECTANGLE(global.format.info.raw.size.width, global.format.info.raw.size.height);
            break :b .{ global.format.info.raw.format, 1 };
        },
        pw.c.SPA_MEDIA_SUBTYPE_dsp => b: {
            check(pw.c.spa_format_video_dsp_parse(param, &global.format.info.dsp));
            if (global.format.info.dsp.format != pw.c.SPA_VIDEO_FORMAT_DSP_F32) return;
            global.size = pw.c.SPA_RECTANGLE(global.position.?.video.size.width, global.position.?.video.size.height);
            break :b .{ pw.c.SPA_VIDEO_FORMAT_DSP_F32, 4 };
        },
        else => .{ pw.c.SPA_VIDEO_FORMAT_UNKNOWN, 0 },
    };
    if (format == pw.c.SPA_VIDEO_FORMAT_UNKNOWN) {
        _ = pw.c.pw_stream_set_error(stream, -pw.c.EINVAL, "unknown pixel format");
        return;
    }
    if (global.size.width == 0 or global.size.height == 0) {
        _ = pw.c.pw_stream_set_error(stream, -pw.c.EINVAL, "invalid size");
        return;
    }

    // Check what size we got
    const size: i32, const blocks: i32 = switch (format) {
        pw.c.SPA_VIDEO_FORMAT_YV12, pw.c.SPA_VIDEO_FORMAT_I420 => b: {
            global.stride = @intCast(global.size.width);
            global.is_yuv = true;
            break :b .{
                @divExact((global.stride * @as(i32, @intCast(global.size.height))) * 3, 2),
                3,
            };
        },
        pw.c.SPA_VIDEO_FORMAT_YUY2 => b: {
            global.is_yuv = true;
            global.stride = @intCast(global.size.width * 2);
            break :b .{
                global.stride * @as(i32, @intCast(global.size.height)),
                1,
            };
        },
        else => b: {
            global.stride = @intCast(global.size.width * 2);
            break :b .{
                global.stride * @as(i32, @intCast(global.size.height)),
                1,
            };
        },
    };

    // Update the global rect
    global.rect.x = 0;
    global.rect.y = 0;
    global.rect.w = @floatFromInt(global.size.width);
    global.rect.h = @floatFromInt(global.size.height);

    // Specify our buffer options
    var params_buf: [3]?*const pw.c.spa_pod = undefined;
    var params: std.ArrayList(?*const pw.c.spa_pod) = .initBuffer(&params_buf);
    {
        var param_buffers_frame: pw.c.spa_pod_frame = undefined;
        check(pw.c.spa_pod_builder_push_object(
            &b,
            &param_buffers_frame,
            pw.c.SPA_TYPE_OBJECT_ParamBuffers,
            pw.c.SPA_PARAM_Buffers,
        ));

        {
            var choice_frame: pw.c.spa_pod_frame = undefined;
            check(pw.c.spa_pod_builder_prop(&b, pw.c.SPA_PARAM_BUFFERS_buffers, 0));
            check(pw.c.spa_pod_builder_push_choice(&b, &choice_frame, pw.c.SPA_CHOICE_Range, 0));
            check(pw.c.spa_pod_builder_int(&b, 8));
            check(pw.c.spa_pod_builder_int(&b, 2));
            check(pw.c.spa_pod_builder_int(&b, max_buffers));
            assert(pw.c.spa_pod_builder_pop(&b, &choice_frame) != null);
        }

        check(pw.c.spa_pod_builder_prop(&b, pw.c.SPA_PARAM_BUFFERS_blocks, 0));
        check(pw.c.spa_pod_builder_int(&b, blocks));

        check(pw.c.spa_pod_builder_prop(&b, pw.c.SPA_PARAM_BUFFERS_size, 0));
        check(pw.c.spa_pod_builder_int(&b, size * mult));

        check(pw.c.spa_pod_builder_prop(&b, pw.c.SPA_PARAM_BUFFERS_stride, 0));
        check(pw.c.spa_pod_builder_int(&b, global.stride * mult));

        check(pw.c.spa_pod_builder_prop(&b, pw.c.SPA_PARAM_BUFFERS_stride, 0));
        check(pw.c.spa_pod_builder_int(&b, global.stride * mult));

        {
            var choice_frame: pw.c.spa_pod_frame = undefined;
            check(pw.c.spa_pod_builder_prop(&b, pw.c.SPA_PARAM_BUFFERS_dataType, 0));
            check(pw.c.spa_pod_builder_push_choice(&b, &choice_frame, pw.c.SPA_CHOICE_Range, 0));
            check(pw.c.spa_pod_builder_int(&b, 8));
            check(pw.c.spa_pod_builder_int(&b, 2));
            check(pw.c.spa_pod_builder_int(&b, max_buffers));
            assert(pw.c.spa_pod_builder_pop(&b, &choice_frame) != null);
        }

        {
            var choice_frame: pw.c.spa_pod_frame = undefined;
            check(pw.c.spa_pod_builder_prop(&b, pw.c.SPA_PARAM_BUFFERS_dataType, 0));
            check(pw.c.spa_pod_builder_push_choice(&b, &choice_frame, pw.c.SPA_CHOICE_Flags, 0));
            check(pw.c.spa_pod_builder_int(&b, 1 << pw.c.SPA_DATA_MemPtr));
            assert(pw.c.spa_pod_builder_pop(&b, &choice_frame) != null);
        }

        params.appendBounded(@ptrCast(@alignCast(pw.c.spa_pod_builder_pop(&b, &param_buffers_frame)))) catch @panic("OOB");
    }

    // Specify the timing options
    {
        var timing_frame: pw.c.spa_pod_frame = undefined;
        check(pw.c.spa_pod_builder_push_object(
            &b,
            &timing_frame,
            pw.c.SPA_TYPE_OBJECT_ParamMeta,
            pw.c.SPA_PARAM_Meta,
        ));
        check(pw.c.spa_pod_builder_prop(&b, pw.c.SPA_PARAM_META_type, 0));
        check(pw.c.spa_pod_builder_id(&b, pw.c.SPA_META_Header));

        check(pw.c.spa_pod_builder_prop(&b, pw.c.SPA_PARAM_META_size, 0));
        check(pw.c.spa_pod_builder_int(&b, @sizeOf(pw.c.spa_meta_header)));

        params.appendBounded(@ptrCast(@alignCast(pw.c.spa_pod_builder_pop(&b, &timing_frame)))) catch @panic("OOB");
    }

    // Specify the cropping options
    {
        var crop_frame: pw.c.spa_pod_frame = undefined;
        check(pw.c.spa_pod_builder_push_object(
            &b,
            &crop_frame,
            pw.c.SPA_TYPE_OBJECT_ParamMeta,
            pw.c.SPA_PARAM_Meta,
        ));

        check(pw.c.spa_pod_builder_prop(&b, pw.c.SPA_PARAM_META_type, 0));
        check(pw.c.spa_pod_builder_id(&b, pw.c.SPA_META_VideoCrop));

        check(pw.c.spa_pod_builder_prop(&b, pw.c.SPA_PARAM_META_size, 0));
        check(pw.c.spa_pod_builder_id(&b, @sizeOf(pw.c.spa_meta_region)));

        params.appendBounded(@ptrCast(@alignCast(pw.c.spa_pod_builder_pop(&b, &crop_frame)))) catch @panic("OOB");
    }

    // Success
    check(pw.c.pw_stream_update_params(stream, params.items.ptr, @intCast(params.items.len)));
}

/// Process a new buffer.
fn onProcess(userdata: ?*anyopaque) callconv(.c) void {
    _ = userdata;
    const stream = global.stream;

    var maybe_buffer: ?*pw.c.pw_buffer = null;
    while (true) {
        const t = pw.c.pw_stream_dequeue_buffer(stream) orelse break;
        if (maybe_buffer) |b| check(pw.c.pw_stream_queue_buffer(stream, b));
        maybe_buffer = t;
    }
    if (maybe_buffer) |b| {
        if (global.current_buffer) |current| {
            check(pw.c.pw_stream_queue_buffer(stream, current));
        }
        global.current_buffer = b;
    }
}

/// Render the current buffer.
fn render(draw: zin.Draw(.{ .static = .main })) void {
    // Early out if we're redrawing too fast (e.g. during a resize)
    {
        const now = std.time.Instant.now() catch |err| @panic(@errorName(err));
        if (global.last_render) |last_render| {
            const elapsed_ns = now.since(last_render);
            if (elapsed_ns < global.timer_period_ns / 2) return;
        }
        global.last_render = now;
    }

    // Clear the screen
    draw.clear();

    // Render the current frame
    const client_size = zin.staticWindow(.main).getClientSize();

    const buf: *pw.c.spa_buffer = (global.current_buffer orelse {
        draw.text("waiting for webcam...", @divTrunc(client_size.x, 2) - 50, @divTrunc(client_size.y, 2), .white);
        return;
    }).buffer;

    const sdata = buf.datas[0].data orelse return;

    const maybe_mc: ?*pw.c.spa_meta_region = @ptrCast(@alignCast(pw.c.spa_buffer_find_meta_data(buf, pw.c.SPA_META_VideoCrop, @sizeOf(pw.c.spa_meta_region))));
    if (maybe_mc) |mc| {
        if (pw.c.spa_meta_region_is_valid(mc)) {
            global.rect.x = @floatFromInt(mc.region.position.x);
            global.rect.y = @floatFromInt(mc.region.position.y);
            global.rect.w = @floatFromInt(mc.region.size.width);
            global.rect.h = @floatFromInt(mc.region.size.height);
        }
    }

    if (global.is_yuv and buf.n_datas == 1) {
        const sstride = global.stride;
        const udata: [*]u8 = @ptrCast(sdata);
        const size = zin.staticWindow(.main).getClientSize();
        const rect_size = zin.scale(i32, texel_width, draw.getDpiScale().x);
        for (0..@intCast(@min(size.y, global.size.height))) |y| {
            var x: usize = 0;
            while (x < @min(size.x, global.size.width)) : (x += 2) {
                const i: usize = @intCast(y * @as(usize, @intCast(sstride)) + x * 2);
                const colors = yuyvToRgb(udata[i..][0..4].*);
                draw.rect(
                    .ltwh(
                        @as(i32, @intCast(x)) * rect_size,
                        @as(i32, @intCast(y)) * rect_size,
                        rect_size,
                        rect_size,
                    ),
                    colors[0],
                );
                draw.rect(
                    .ltwh(
                        (@as(i32, @intCast(x)) + 1) * rect_size,
                        @as(i32, @intCast(y)) * rect_size,
                        rect_size,
                        rect_size,
                    ),
                    colors[1],
                );
            }
        }
    } else {
        draw.text(
            "unsupported format...",
            @divTrunc(client_size.x, 2) - 50,
            @divTrunc(client_size.y, 2),
            .white,
        );
        return;
    }
}

pub fn clampUnorm(val: anytype) u8 {
    return @intCast(std.math.clamp(val, 0, 255));
}

fn yuyvToRgb(yuyv: [4]u8) [2]zin.Rgb8 {
    const d = @as(i32, yuyv[1]) - 128;
    const e = @as(i32, yuyv[3]) - 128;
    const c0 = @as(i32, yuyv[0]) - 16;
    const c1 = @as(i32, yuyv[2]) - 16;
    return .{
        .{
            .r = clampUnorm(((298 * c0) + (409 * e) + 128) >> 8),
            .g = clampUnorm(((298 * c0) - (100 * d) - (208 * e) + 128) >> 8),
            .b = clampUnorm(((298 * c0) + (516 * d) + 128) >> 8),
        },
        .{
            .r = clampUnorm(((298 * c1) + (409 * e) + 128) >> 8),
            .g = clampUnorm(((298 * c1) - (100 * d) - (208 * e) + 128) >> 8),
            .b = clampUnorm(((298 * c1) + (516 * d) + 128) >> 8),
        },
    };
}

fn check(res: c_int) void {
    if (res != 0) {
        std.debug.panic("pipewire call failed: {s}", .{pw.c.spa_strerror(res)});
    }
}

fn startTimerNanos(ns: u64) void {
    global.timer_period_ns = ns;
    zin.staticWindow(.main).startTimerNanos({}, ns);
}

const Rect = struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,
};

const all_formats: []const pw.c.spa_video_format = &.{
    pw.c.SPA_VIDEO_FORMAT_ENCODED,
    pw.c.SPA_VIDEO_FORMAT_I420,
    pw.c.SPA_VIDEO_FORMAT_YV12,
    pw.c.SPA_VIDEO_FORMAT_YUY2,
    pw.c.SPA_VIDEO_FORMAT_UYVY,
    pw.c.SPA_VIDEO_FORMAT_AYUV,
    pw.c.SPA_VIDEO_FORMAT_RGBx,
    pw.c.SPA_VIDEO_FORMAT_BGRx,
    pw.c.SPA_VIDEO_FORMAT_xRGB,
    pw.c.SPA_VIDEO_FORMAT_xBGR,
    pw.c.SPA_VIDEO_FORMAT_RGBA,
    pw.c.SPA_VIDEO_FORMAT_BGRA,
    pw.c.SPA_VIDEO_FORMAT_ARGB,
    pw.c.SPA_VIDEO_FORMAT_ABGR,
    pw.c.SPA_VIDEO_FORMAT_RGB,
    pw.c.SPA_VIDEO_FORMAT_BGR,
    pw.c.SPA_VIDEO_FORMAT_Y41B,
    pw.c.SPA_VIDEO_FORMAT_Y42B,
    pw.c.SPA_VIDEO_FORMAT_YVYU,
    pw.c.SPA_VIDEO_FORMAT_Y444,
    pw.c.SPA_VIDEO_FORMAT_v210,
    pw.c.SPA_VIDEO_FORMAT_v216,
    pw.c.SPA_VIDEO_FORMAT_NV12,
    pw.c.SPA_VIDEO_FORMAT_NV21,
    pw.c.SPA_VIDEO_FORMAT_GRAY8,
    pw.c.SPA_VIDEO_FORMAT_GRAY16_BE,
    pw.c.SPA_VIDEO_FORMAT_GRAY16_LE,
    pw.c.SPA_VIDEO_FORMAT_v308,
    pw.c.SPA_VIDEO_FORMAT_RGB16,
    pw.c.SPA_VIDEO_FORMAT_BGR16,
    pw.c.SPA_VIDEO_FORMAT_RGB15,
    pw.c.SPA_VIDEO_FORMAT_BGR15,
    pw.c.SPA_VIDEO_FORMAT_UYVP,
    pw.c.SPA_VIDEO_FORMAT_A420,
    pw.c.SPA_VIDEO_FORMAT_RGB8P,
    pw.c.SPA_VIDEO_FORMAT_YUV9,
    pw.c.SPA_VIDEO_FORMAT_YVU9,
    pw.c.SPA_VIDEO_FORMAT_IYU1,
    pw.c.SPA_VIDEO_FORMAT_ARGB64,
    pw.c.SPA_VIDEO_FORMAT_AYUV64,
    pw.c.SPA_VIDEO_FORMAT_r210,
    pw.c.SPA_VIDEO_FORMAT_I420_10BE,
    pw.c.SPA_VIDEO_FORMAT_I420_10LE,
    pw.c.SPA_VIDEO_FORMAT_I422_10BE,
    pw.c.SPA_VIDEO_FORMAT_I422_10LE,
    pw.c.SPA_VIDEO_FORMAT_Y444_10BE,
    pw.c.SPA_VIDEO_FORMAT_Y444_10LE,
    pw.c.SPA_VIDEO_FORMAT_GBR,
    pw.c.SPA_VIDEO_FORMAT_GBR_10BE,
    pw.c.SPA_VIDEO_FORMAT_GBR_10LE,
    pw.c.SPA_VIDEO_FORMAT_NV16,
    pw.c.SPA_VIDEO_FORMAT_NV24,
    pw.c.SPA_VIDEO_FORMAT_NV12_64Z32,
    pw.c.SPA_VIDEO_FORMAT_A420_10BE,
    pw.c.SPA_VIDEO_FORMAT_A420_10LE,
    pw.c.SPA_VIDEO_FORMAT_A422_10BE,
    pw.c.SPA_VIDEO_FORMAT_A422_10LE,
    pw.c.SPA_VIDEO_FORMAT_A444_10BE,
    pw.c.SPA_VIDEO_FORMAT_A444_10LE,
    pw.c.SPA_VIDEO_FORMAT_NV61,
    pw.c.SPA_VIDEO_FORMAT_P010_10BE,
    pw.c.SPA_VIDEO_FORMAT_P010_10LE,
    pw.c.SPA_VIDEO_FORMAT_IYU2,
    pw.c.SPA_VIDEO_FORMAT_VYUY,
    pw.c.SPA_VIDEO_FORMAT_GBRA,
    pw.c.SPA_VIDEO_FORMAT_GBRA_10BE,
    pw.c.SPA_VIDEO_FORMAT_GBRA_10LE,
    pw.c.SPA_VIDEO_FORMAT_GBR_12BE,
    pw.c.SPA_VIDEO_FORMAT_GBR_12LE,
    pw.c.SPA_VIDEO_FORMAT_GBRA_12BE,
    pw.c.SPA_VIDEO_FORMAT_GBRA_12LE,
    pw.c.SPA_VIDEO_FORMAT_I420_12BE,
    pw.c.SPA_VIDEO_FORMAT_I420_12LE,
    pw.c.SPA_VIDEO_FORMAT_I422_12BE,
    pw.c.SPA_VIDEO_FORMAT_I422_12LE,
    pw.c.SPA_VIDEO_FORMAT_Y444_12BE,
    pw.c.SPA_VIDEO_FORMAT_Y444_12LE,
    pw.c.SPA_VIDEO_FORMAT_RGBA_F16,
    pw.c.SPA_VIDEO_FORMAT_RGBA_F32,
    pw.c.SPA_VIDEO_FORMAT_xRGB_210LE,
    pw.c.SPA_VIDEO_FORMAT_xBGR_210LE,
    pw.c.SPA_VIDEO_FORMAT_RGBx_102LE,
    pw.c.SPA_VIDEO_FORMAT_BGRx_102LE,
    pw.c.SPA_VIDEO_FORMAT_ARGB_210LE,
    pw.c.SPA_VIDEO_FORMAT_ABGR_210LE,
    pw.c.SPA_VIDEO_FORMAT_RGBA_102LE,
    pw.c.SPA_VIDEO_FORMAT_BGRA_102LE,
    pw.c.SPA_VIDEO_FORMAT_DSP_F32,
};

pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    if (@intFromEnum(level) > @intFromEnum(global.runtime_log_level)) return;
    std.log.defaultLog(level, scope, format, args);
}
