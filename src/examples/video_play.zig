// `pipewire/src/examples/video-play.c` translated to Zig.

const std = @import("std");
const log = std.log;
const example_options = @import("example_options");

const p = if (example_options.use_zig_module)
    // Example of linking with the pipewire zig module
    @import("pipewire").c
else
    // Example of linking with the pipewire static library
    @import("pipewire");

const sdl = @cImport({
    @cDefine("WIDTH", std.fmt.comptimePrint("{}", .{width}));
    @cDefine("HEIGHT", std.fmt.comptimePrint("{}", .{height}));
    @cDefine("RATE", std.fmt.comptimePrint("{}", .{rate}));
    @cInclude("SDL3/SDL.h");
});

const width = 1920;
const height = 1080;
const rate = 30;
const max_buffers = 64;

pub const std_options: std.Options = .{
    .log_level = .info,
};

// XXX: expose this from the library so other people don't have to recreate it
const pw_log_scope = .pw;
fn pwLog(
    object: ?*anyopaque,
    level: p.spa_log_level,
    file: [*c]const u8,
    line: c_int,
    func: [*c]const u8,
    fmt: [*c]const u8,
    ...,
) callconv(.c) void {
    pwLogtv(object, level, null, file, line, func, fmt);
}

fn pwLogtv(
    object: ?*anyopaque,
    pw_level: p.spa_log_level,
    topic: ?*const p.spa_log_topic,
    file_abs_c: [*c]const u8,
    line: c_int,
    func: [*c]const u8,
    fmt: [*c]const u8,
    ...,
) callconv(.c) void {
    const level: std.log.Level = switch (pw_level) {
        p.SPA_LOG_LEVEL_NONE => return,
        p.SPA_LOG_LEVEL_ERROR => .err,
        p.SPA_LOG_LEVEL_WARN => .warn,
        p.SPA_LOG_LEVEL_INFO => .info,
        p.SPA_LOG_LEVEL_DEBUG, p.SPA_LOG_LEVEL_TRACE => .debug,
        else => .err,
    };
    const file = b: {
        const file_abs = std.mem.span(file_abs_c);
        const i = std.mem.lastIndexOfAny(u8, file_abs, "\\/") orelse break :b file_abs;
        break :b file_abs[i + 1 ..];
    };
    switch (level) {
        inline else => |l| {
            if (!std.log.logEnabled(l, pw_log_scope)) return;
            // XXX: use c to actually do the formatting into a buf then print here so we can handle
            // the varargs
            std.options.logFn(l, pw_log_scope, "{s}:{}: {s}: {s}", .{ file, line, func, fmt });
        },
    }
    // XXX: display these
    _ = topic;
    _ = object;
}

pub fn main() !void {
    p.pw_init(0, null);
    defer p.pw_deinit();

    p.pw_log_set_level(switch (std.options.log_level) {
        .err => p.SPA_LOG_LEVEL_ERROR,
        .warn => p.SPA_LOG_LEVEL_WARN,
        .info => p.SPA_LOG_LEVEL_INFO,
        .debug => p.SPA_LOG_LEVEL_TRACE,
    });
    const logger = &p.pw_log_get()[0];
    // XXX: make sure this const cast is okay--just verify it was originally mutable
    const funcs: *p.spa_log_methods = @ptrCast(@alignCast(@constCast(logger.iface.cb.funcs.?)));
    // XXX: do the first three really all take the same args? what's the difference between them?
    funcs.log = @ptrCast(&pwLog);
    funcs.logv = @ptrCast(&pwLog);
    funcs.logt = @ptrCast(&pwLog);
    funcs.logtv = @ptrCast(&pwLogtv);
    p.pw_log_set(logger);

    var data: Data = .{};

    // Create a main loop
    data.loop = p.pw_main_loop_new(null).?;
    defer p.pw_main_loop_destroy(data.loop);

    _ = p.pw_loop_add_signal(p.pw_main_loop_get_loop(data.loop), p.SIGINT, &doQuit, &data);
    _ = p.pw_loop_add_signal(p.pw_main_loop_get_loop(data.loop), p.SIGTERM, &doQuit, &data);

    // create a simple stream, the simple stream manages to core and remote objects for you if you
    // don't need to deal with them
    //
    // If you plan to autoconnect your stream, you need to provide at least media, category and role
    // properties
    //
    // Pass your events and a user_data pointer as the last arguments. This will inform you about
    // the stream state. The most important event you need to listen to is the process event where
    // you need to consume the data provided to you.
    const props = p.pw_properties_new(
        p.PW_KEY_MEDIA_TYPE,
        "Video",
        p.PW_KEY_MEDIA_CATEGORY,
        "Capture",
        p.PW_KEY_MEDIA_ROLE,
        "Camera",
        @as(?*anyopaque, null),
    ).?;

    var args: std.process.ArgIterator = .init();
    _ = args.next();
    if (args.next()) |arg| {
        _ = p.pw_properties_set(props, p.PW_KEY_TARGET_OBJECT, arg);
    }

    data.stream = p.pw_stream_new_simple(
        p.pw_main_loop_get_loop(data.loop),
        "video-play",
        props,
        &.{
            .version = p.PW_VERSION_STREAM_EVENTS,
            .state_changed = &onStreamStateChanged,
            .io_changed = &onStreamIoChanged,
            .param_changed = &onStreamParamChanged,
            .process = &onProcess,
        },
        &data,
    ).?;
    defer p.pw_stream_destroy(data.stream);

    if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) {
        log.err("can't initialize SDL: {s}", .{sdl.SDL_GetError()});
        std.process.exit(1);
    }

    if (!sdl.SDL_CreateWindowAndRenderer(
        "Demo",
        width,
        height,
        sdl.SDL_WINDOW_RESIZABLE,
        &data.window,
        &data.renderer,
    )) {
        log.err("can't create window: {s}", .{sdl.SDL_GetError()});
        std.process.exit(1);
    }
    defer {
        if (data.texture) |texture| sdl.SDL_DestroyTexture(texture);
        if (data.cursor) |cursor| sdl.SDL_DestroyTexture(cursor);
        sdl.SDL_DestroyRenderer(data.renderer);
        sdl.SDL_DestroyWindow(data.window);
    }

    var buffer: [1024]u8 align(@alignOf(u32)) = undefined;
    var b = std.mem.zeroInit(p.spa_pod_builder, .{
        .data = &buffer,
        .size = buffer.len,
    });

    // build the extra parameters to connect with. To connect, we can provide a list of supported
    // formats.  We use a builder that writes the param object to the stack.
    var params_buf: [3]?*const p.spa_pod = undefined;
    var params: std.ArrayList(?*const p.spa_pod) = .initBuffer(&params_buf);
    buildFormat(&data, &b, &params);

    {
        var f: p.spa_pod_frame = undefined;
        // send a tag, input tags travel upstream
        p.spa_tag_build_start(&b, &f, p.SPA_PARAM_Tag, p.SPA_DIRECTION_INPUT);
        const items: [1]p.spa_dict_item = .{
            p.SPA_DICT_ITEM_INIT("my-tag-other-key", "my-special-other-tag-value"),
        };
        p.spa_tag_build_add_dict(&b, &p.SPA_DICT_INIT(items, 1));
        params.appendBounded(p.spa_tag_build_end(&b, &f)) catch @panic("OOB");
    }

    // now connect the stream, we need a direction (input/output),
    // an optional target node to connect to, some flags and parameters
    //
    const res = p.pw_stream_connect(
        data.stream,
        p.PW_DIRECTION_INPUT,
        p.PW_ID_ANY,
        p.PW_STREAM_FLAG_AUTOCONNECT | // try to automatically connect this stream
            p.PW_STREAM_FLAG_INACTIVE | // we will activate ourselves
            p.PW_STREAM_FLAG_MAP_BUFFERS, // mmap the buffer data for us
        // extra parameters, see above
        params.items.ptr,
        @intCast(params.items.len),
    );
    if (res < 0) {
        log.err("can't connect: {s}", .{p.spa_strerror(res)});
        std.process.exit(1);
    }

    // /do things until we quit the mainloop
    _ = p.pw_main_loop_run(data.loop);
}

const Pixel = extern struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

const Data = struct {
    renderer: ?*sdl.SDL_Renderer = null,
    window: ?*sdl.SDL_Window = null,
    texture: ?*sdl.SDL_Texture = null,
    cursor: ?*sdl.SDL_Texture = null,

    loop: ?*p.pw_main_loop = null,
    stream: ?*p.pw_stream = null,

    position: ?*p.spa_io_position = null,

    format: p.spa_video_info = .{},
    stride: i32 = 0,
    size: p.spa_rectangle = .{},

    rect: sdl.SDL_FRect = .{},
    cursor_rect: sdl.SDL_FRect = .{},
    is_yuv: bool = false,
};

fn doQuit(userdata: ?*anyopaque, signal_number: c_int) callconv(.c) void {
    _ = signal_number;
    const data: *Data = @ptrCast(@alignCast(userdata));
    _ = p.pw_main_loop_quit(data.loop);
}

// our data processing function is in general:
// ```
// struct pw_buffer *b;
// b = pw_stream_dequeue_buffer(stream);
//
// .. do stuff with buffer ...
//
// pw_stream_queue_buffer(stream, b);
// ```
fn onProcess(userdata: ?*anyopaque) callconv(.c) void {
    const data: *Data = @ptrCast(@alignCast(userdata));
    const stream = data.stream;

    var render_cursor = false;

    var maybe_buffer: ?*p.pw_buffer = null;
    while (true) {
        const t = p.pw_stream_dequeue_buffer(stream) orelse break;
        if (maybe_buffer) |b| _ = p.pw_stream_queue_buffer(stream, b);
        maybe_buffer = t;
    }
    const b = maybe_buffer orelse {
        log.warn("out of buffers", .{});
        return;
    };
    defer _ = p.pw_stream_queue_buffer(stream, b);

    const buf: *p.spa_buffer = b.buffer;

    log.debug("new buffer {*}", .{buf});

    handleEvents(data);

    const sdata = buf.datas[0].data orelse return;

    const maybe_h: ?*p.spa_meta_header = @ptrCast(@alignCast(p.spa_buffer_find_meta_data(buf, p.SPA_META_Header, @sizeOf(p.spa_meta_header))));
    if (maybe_h) |h| {
        const now = p.pw_stream_get_nsec(stream);
        log.debug("now:{} pts:{} diff:{}", .{ now, h.pts, now - @as(u64, @intCast(h.pts)) });
    }

    // get the videocrop metadata if any
    const maybe_mc: ?*p.spa_meta_region = @ptrCast(@alignCast(p.spa_buffer_find_meta_data(buf, p.SPA_META_VideoCrop, @sizeOf(p.spa_meta_region))));
    if (maybe_mc) |mc| {
        if (p.spa_meta_region_is_valid(mc)) {
            data.rect.x = @floatFromInt(mc.region.position.x);
            data.rect.y = @floatFromInt(mc.region.position.y);
            data.rect.w = @floatFromInt(mc.region.size.width);
            data.rect.h = @floatFromInt(mc.region.size.height);
        }
    }
    // get cursor metadata
    const maybe_mcs: ?*p.spa_meta_cursor = @ptrCast(@alignCast(p.spa_buffer_find_meta_data(buf, p.SPA_META_Cursor, @sizeOf(p.spa_meta_cursor))));
    if (maybe_mcs) |mcs| {
        if (p.spa_meta_cursor_is_valid(mcs)) {
            data.cursor_rect.x = @floatFromInt(mcs.position.x);
            data.cursor_rect.y = @floatFromInt(mcs.position.y);

            const mb: *p.spa_meta_bitmap = @ptrFromInt(@intFromPtr(mcs) + mcs.bitmap_offset);
            data.cursor_rect.w = @floatFromInt(mb.size.width);
            data.cursor_rect.h = @floatFromInt(mb.size.height);

            if (data.cursor == null) {
                data.cursor = sdl.SDL_CreateTexture(
                    data.renderer,
                    idToSdlFormat(mb.format),
                    sdl.SDL_TEXTUREACCESS_STREAMING,
                    @intCast(mb.size.width),
                    @intCast(mb.size.height),
                );
                _ = sdl.SDL_SetTextureBlendMode(data.cursor, sdl.SDL_BLENDMODE_BLEND);
            }

            var cdata: [*c]u8 = undefined;
            var cstride: c_int = undefined;
            if (!sdl.SDL_LockTexture(data.cursor, null, &cdata, &cstride)) {
                log.err("Couldn't lock cursor texture: {s}", .{sdl.SDL_GetError()});
                return;
            }
            defer sdl.SDL_UnlockTexture(data.cursor);

            // copy the cursor bitmap into the texture
            var src: [*]u8 = @ptrFromInt(@intFromPtr(mb) + mb.offset);
            var dst = cdata;
            const ostride: usize = @intCast(@min(cstride, mb.stride));

            for (0..mb.size.height) |_| {
                @memcpy(dst[0..ostride], src[0..ostride]);
                dst += @intCast(cstride);
                src += @intCast(mb.stride);
            }

            render_cursor = true;
        }
    }

    // copy video image in texture
    if (data.is_yuv) {
        var datas: [4]?[*]u8 = undefined;
        const sstride = data.stride;
        if (buf.n_datas == 1) {
            _ = sdl.SDL_UpdateTexture(data.texture, null, sdata, sstride);
        } else {
            datas[0] = @ptrCast(sdata);
            datas[1] = @ptrCast(buf.datas[1].data);
            datas[2] = @ptrCast(buf.datas[2].data);
            _ = sdl.SDL_UpdateYUVTexture(
                data.texture,
                null,
                datas[0],
                sstride,
                datas[1],
                @divExact(sstride, 2),
                datas[2],
                @divExact(sstride, 2),
            );
        }
    } else {
        var dstride: c_int = undefined;
        var ddata: ?*anyopaque = undefined;
        if (!sdl.SDL_LockTexture(data.texture, null, &ddata, &dstride)) {
            log.err("Couldn't lock texture: {s}", .{sdl.SDL_GetError()});
        }
        defer sdl.SDL_UnlockTexture(data.texture);

        var sstride: u32 = @intCast(buf.datas[0].chunk.*.stride);
        if (sstride == 0) sstride = buf.datas[0].chunk.*.size / data.size.height;
        const ostride = @min(sstride, dstride);

        var src: [*]u8 = @ptrCast(sdata);
        var dst: [*]u8 = @ptrCast(ddata);

        if (data.format.media_subtype == p.SPA_MEDIA_SUBTYPE_dsp) {
            for (0..data.size.height) |_| {
                const pixel: [*]Pixel = @ptrCast(@alignCast(src));
                for (0..data.size.width) |j| {
                    dst[j * 4 + 0] = @intFromFloat(std.math.clamp(pixel[j].r * 255.0, 0, 255));
                    dst[j * 4 + 1] = @intFromFloat(std.math.clamp(pixel[j].g * 255.0, 0, 255));
                    dst[j * 4 + 2] = @intFromFloat(std.math.clamp(pixel[j].b * 255.0, 0, 255));
                    dst[j * 4 + 3] = @intFromFloat(std.math.clamp(pixel[j].a * 255.0, 0, 255));
                }
                src += sstride;
                dst += @intCast(dstride);
            }
        } else {
            for (0..data.size.height) |_| {
                @memcpy(dst[0..@intCast(ostride)], src[0..@intCast(ostride)]);
                src += sstride;
                dst += @intCast(dstride);
            }
        }
    }

    _ = sdl.SDL_RenderClear(data.renderer);
    // now render the video and then the cursor if any
    _ = sdl.SDL_RenderTexture(data.renderer, data.texture, &data.rect, null);
    if (render_cursor) _ = sdl.SDL_RenderTexture(
        data.renderer,
        data.cursor,
        null,
        &data.cursor_rect,
    );
    _ = sdl.SDL_RenderPresent(data.renderer);
}

fn handleEvents(data: *Data) void {
    var event: sdl.SDL_Event = undefined;
    while (sdl.SDL_PollEvent(&event)) {
        switch (event.type) {
            sdl.SDL_EVENT_QUIT => {
                _ = p.pw_main_loop_quit(data.loop);
            },
            else => {},
        }
    }
}

fn onStreamStateChanged(
    userdata: ?*anyopaque,
    old: p.pw_stream_state,
    state: p.pw_stream_state,
    err: [*c]const u8,
) callconv(.c) void {
    _ = old;
    _ = err;
    const data: *Data = @ptrCast(@alignCast(userdata));
    log.info("stream state: \"{s}\"", .{p.pw_stream_state_as_string(state)});
    switch (state) {
        p.PW_STREAM_STATE_UNCONNECTED => _ = p.pw_main_loop_quit(data.loop),
        // because we started inactive, activate ourselves now
        p.PW_STREAM_STATE_PAUSED => _ = p.pw_stream_set_active(data.stream, true),
        else => {},
    }
}

fn onStreamIoChanged(userdata: ?*anyopaque, id: u32, area: ?*anyopaque, size: u32) callconv(.c) void {
    _ = size;
    const data: *Data = @ptrCast(@alignCast(userdata));
    if (id == p.SPA_IO_Position) {
        data.position = @ptrCast(@alignCast(area));
    }
}

// Be notified when the stream param changes. We're only looking at the
// format changes.
//
// We are now supposed to call pw_stream_finish_format() with success or
// failure, depending on if we can support the format. Because we gave
// a list of supported formats, this should be ok.
//
// As part of pw_stream_finish_format() we can provide parameters that
// will control the buffer memory allocation. This includes the metadata
// that we would like on our buffer, the size, alignment, etp.
fn onStreamParamChanged(userdata: ?*anyopaque, id: u32, param: [*c]const p.spa_pod) callconv(.c) void {
    const data: *Data = @ptrCast(@alignCast(userdata));
    const stream = data.stream;
    var params_buffer: [1024]u8 align(@alignOf(u32)) = undefined;
    var b: p.spa_pod_builder = .{
        .data = &params_buffer,
        .size = params_buffer.len,
        ._padding = 0,
        .state = .{ .offset = 0, .flags = 0, .frame = null },
        .callbacks = .{ .funcs = null, .data = null },
    };

    if (param != null and id == p.SPA_PARAM_Tag) {
        log.err("invalid pod", .{});
        return;
    }
    if (param != null and id == p.SPA_PARAM_Latency) {
        var info: p.spa_latency_info = undefined;
        if (p.spa_latency_parse(param, &info) >= 0) {
            log.info("got latency: {}", .{@divTrunc((info.min_ns + info.max_ns), 2)});
        }
        return;
    }
    // NULL means to clear the format
    if (param == null or id != p.SPA_PARAM_Format) return;

    log.info("got format:", .{});
    _ = p.spa_debug_format(2, null, param);

    if (p.spa_format_parse(param, &data.format.media_type, &data.format.media_subtype) < 0) {
        return;
    }

    if (data.format.media_type != p.SPA_MEDIA_TYPE_video) return;

    const sdl_format, const mult: i32 = switch (data.format.media_subtype) {
        p.SPA_MEDIA_SUBTYPE_raw => b: {
            // call a helper function to parse the format for us.
            _ = p.spa_format_video_raw_parse(param, &data.format.info.raw);
            data.size = p.SPA_RECTANGLE(data.format.info.raw.size.width, data.format.info.raw.size.height);
            break :b .{ idToSdlFormat(data.format.info.raw.format), 1 };
        },
        p.SPA_MEDIA_SUBTYPE_dsp => b: {
            _ = p.spa_format_video_dsp_parse(param, &data.format.info.dsp);
            if (data.format.info.dsp.format != p.SPA_VIDEO_FORMAT_DSP_F32) return;
            data.size = p.SPA_RECTANGLE(data.position.?.video.size.width, data.position.?.video.size.height);
            break :b .{ sdl.SDL_PIXELFORMAT_RGBA32, 4 };
        },
        else => .{ sdl.SDL_PIXELFORMAT_UNKNOWN, 0 },
    };

    if (sdl_format == sdl.SDL_PIXELFORMAT_UNKNOWN) {
        _ = p.pw_stream_set_error(stream, -p.EINVAL, "unknown pixel format");
        return;
    }
    if (data.size.width == 0 or data.size.height == 0) {
        _ = p.pw_stream_set_error(stream, -p.EINVAL, "invalid size");
        return;
    }

    data.texture = sdl.SDL_CreateTexture(
        data.renderer,
        sdl_format,
        sdl.SDL_TEXTUREACCESS_STREAMING,
        @intCast(data.size.width),
        @intCast(data.size.height),
    );
    var d: ?*anyopaque = null;
    const size: i32, const blocks: i32 = switch (sdl_format) {
        sdl.SDL_PIXELFORMAT_YV12, sdl.SDL_PIXELFORMAT_IYUV => b: {
            data.stride = @intCast(data.size.width);
            data.is_yuv = true;
            break :b .{
                @divExact((data.stride * @as(i32, @intCast(data.size.height))) * 3, 2),
                3,
            };
        },
        sdl.SDL_PIXELFORMAT_YUY2 => b: {
            data.is_yuv = true;
            data.stride = @intCast(data.size.width * 2);
            break :b .{
                data.stride * @as(i32, @intCast(data.size.height)),
                1,
            };
        },
        else => b: {
            if (!sdl.SDL_LockTexture(data.texture, null, &d, &data.stride)) {
                log.err("Couldn't lock texture: {s}", .{sdl.SDL_GetError()});
                data.stride = @intCast(data.size.width * 2);
            } else {
                sdl.SDL_UnlockTexture(data.texture);
            }
            break :b .{
                data.stride * @as(i32, @intCast(data.size.height)),
                1,
            };
        },
    };

    data.rect.x = 0;
    data.rect.y = 0;
    data.rect.w = @floatFromInt(data.size.width);
    data.rect.h = @floatFromInt(data.size.height);

    // a SPA_TYPE_OBJECT_ParamBuffers object defines the acceptable size,
    // number, stride etc of the buffers
    var params_buf: [5]?*const p.spa_pod = undefined;
    var params: std.ArrayList(?*const p.spa_pod) = .initBuffer(&params_buf);
    var f: p.spa_pod_frame = undefined;

    _ = p.spa_pod_builder_push_object(
        &b,
        &f,
        p.SPA_TYPE_OBJECT_ParamBuffers,
        p.SPA_PARAM_Buffers,
    );
    _ = p.spa_pod_builder_add(
        &b,

        p.SPA_PARAM_BUFFERS_buffers,
        "?ri",
        @as(c_int, 3),
        @as(c_int, 8),
        @as(c_int, 2),
        @as(c_int, max_buffers),

        p.SPA_PARAM_BUFFERS_blocks,
        "i",
        blocks,

        p.SPA_PARAM_BUFFERS_size,
        "i",
        size * mult,

        p.SPA_PARAM_BUFFERS_stride,
        "i",
        data.stride * mult,

        p.SPA_PARAM_BUFFERS_dataType,
        "?fi",
        @as(c_int, 1),
        @as(c_int, 1 << p.SPA_DATA_MemPtr),

        @as(c_int, 0),
    );
    params.appendBounded(@ptrCast(@alignCast(p.spa_pod_builder_pop(&b, &f)))) catch @panic("OOB");

    // a header metadata with timing information
    _ = p.spa_pod_builder_push_object(
        &b,
        &f,
        p.SPA_TYPE_OBJECT_ParamMeta,
        p.SPA_PARAM_Meta,
    );
    _ = p.spa_pod_builder_add(
        &b,

        p.SPA_PARAM_META_type,
        "I",
        p.SPA_META_Header,

        p.SPA_PARAM_META_size,
        "i",
        @as(usize, @sizeOf(p.spa_meta_header)),

        @as(c_int, 0),
    );
    params.appendBounded(@ptrCast(@alignCast(p.spa_pod_builder_pop(&b, &f)))) catch @panic("OOB");

    // video cropping information
    _ = p.spa_pod_builder_push_object(
        &b,
        &f,
        p.SPA_TYPE_OBJECT_ParamMeta,
        p.SPA_PARAM_Meta,
    );
    _ = p.spa_pod_builder_add(
        &b,

        p.SPA_PARAM_META_type,
        "I",
        p.SPA_META_VideoCrop,

        p.SPA_PARAM_META_size,
        "i",
        @as(usize, @sizeOf(p.spa_meta_region)),

        @as(c_int, 0),
    );
    params.appendBounded(@ptrCast(@alignCast(p.spa_pod_builder_pop(&b, &f)))) catch @panic("OOB");

    // cursor information
    _ = p.spa_pod_builder_push_object(
        &b,
        &f,
        p.SPA_TYPE_OBJECT_ParamMeta,
        p.SPA_PARAM_Meta,
    );
    _ = p.spa_pod_builder_add(
        &b,

        p.SPA_PARAM_META_type,
        "I",
        p.SPA_META_Cursor,

        p.SPA_PARAM_META_size,
        "?ri",
        @as(c_int, 3),
        cursorMetaSize(64, 64),
        cursorMetaSize(1, 1),
        cursorMetaSize(256, 256),

        @as(c_int, 0),
    );
    params.appendBounded(@ptrCast(@alignCast(p.spa_pod_builder_pop(&b, &f)))) catch @panic("OOB");

    // we are done
    _ = p.pw_stream_update_params(stream, params.items.ptr, @intCast(params.items.len));
}

fn cursorMetaSize(w: usize, h: usize) usize {
    return @sizeOf(p.spa_meta_cursor) + @sizeOf(p.spa_meta_bitmap) + w * h * 4;
}

fn buildFormat(data: *Data, b: *p.spa_pod_builder, params: *std.ArrayList(?*const p.spa_pod)) void {
    {
        const format = sdlBuildFormats(data.renderer.?, b);
        log.info("supported SDL formats:", .{});
        _ = p.spa_debug_format(2, null, format);
        params.appendBounded(format) catch @panic("OOB");
    }

    {
        var f: p.spa_pod_frame = undefined;
        _ = p.spa_pod_builder_push_object(b, &f, p.SPA_TYPE_OBJECT_Format, p.SPA_PARAM_EnumFormat);
        _ = p.spa_pod_builder_add(
            b,
            p.SPA_FORMAT_mediaType,
            "I",
            p.SPA_MEDIA_TYPE_video,

            p.SPA_FORMAT_mediaSubtype,
            "I",
            p.SPA_MEDIA_SUBTYPE_dsp,

            p.SPA_FORMAT_VIDEO_format,

            "I",
            p.SPA_VIDEO_FORMAT_DSP_F32,

            @as(c_int, 0),
        );
        const format: *const p.spa_pod = @ptrCast(@alignCast(p.spa_pod_builder_pop(b, &f)));
        _ = p.spa_debug_format(2, null, format);
        params.appendBounded(format) catch @panic("OOB");
    }
}

const FormatPair = struct {
    format: u32,
    id: u32,
};

const sdl_video_formats = [_]FormatPair{
    .{ .format = sdl.SDL_PIXELFORMAT_UNKNOWN, .id = p.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ .format = sdl.SDL_PIXELFORMAT_INDEX1LSB, .id = p.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ .format = sdl.SDL_PIXELFORMAT_UNKNOWN, .id = p.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ .format = sdl.SDL_PIXELFORMAT_INDEX1LSB, .id = p.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ .format = sdl.SDL_PIXELFORMAT_INDEX1MSB, .id = p.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ .format = sdl.SDL_PIXELFORMAT_INDEX4LSB, .id = p.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ .format = sdl.SDL_PIXELFORMAT_INDEX4MSB, .id = p.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ .format = sdl.SDL_PIXELFORMAT_INDEX8, .id = p.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ .format = sdl.SDL_PIXELFORMAT_RGB332, .id = p.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ .format = sdl.SDL_PIXELFORMAT_XRGB4444, .id = p.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ .format = sdl.SDL_PIXELFORMAT_XRGB1555, .id = p.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ .format = sdl.SDL_PIXELFORMAT_XBGR1555, .id = p.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ .format = sdl.SDL_PIXELFORMAT_ARGB4444, .id = p.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ .format = sdl.SDL_PIXELFORMAT_RGBA4444, .id = p.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ .format = sdl.SDL_PIXELFORMAT_ABGR4444, .id = p.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ .format = sdl.SDL_PIXELFORMAT_BGRA4444, .id = p.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ .format = sdl.SDL_PIXELFORMAT_ARGB1555, .id = p.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ .format = sdl.SDL_PIXELFORMAT_RGBA5551, .id = p.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ .format = sdl.SDL_PIXELFORMAT_ABGR1555, .id = p.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ .format = sdl.SDL_PIXELFORMAT_BGRA5551, .id = p.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ .format = sdl.SDL_PIXELFORMAT_RGB565, .id = p.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ .format = sdl.SDL_PIXELFORMAT_BGR565, .id = p.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ .format = sdl.SDL_PIXELFORMAT_RGB24, .id = p.SPA_VIDEO_FORMAT_BGR },
    .{ .format = sdl.SDL_PIXELFORMAT_XRGB8888, .id = p.SPA_VIDEO_FORMAT_BGR },
    .{ .format = sdl.SDL_PIXELFORMAT_RGBX8888, .id = p.SPA_VIDEO_FORMAT_xBGR },
    .{ .format = sdl.SDL_PIXELFORMAT_BGR24, .id = p.SPA_VIDEO_FORMAT_RGB },
    .{ .format = sdl.SDL_PIXELFORMAT_XBGR8888, .id = p.SPA_VIDEO_FORMAT_RGB },
    .{ .format = sdl.SDL_PIXELFORMAT_BGRX8888, .id = p.SPA_VIDEO_FORMAT_xRGB },
    .{ .format = sdl.SDL_PIXELFORMAT_ARGB2101010, .id = p.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ .format = sdl.SDL_PIXELFORMAT_RGBA8888, .id = p.SPA_VIDEO_FORMAT_ABGR },
    .{ .format = sdl.SDL_PIXELFORMAT_ARGB8888, .id = p.SPA_VIDEO_FORMAT_BGRA },
    .{ .format = sdl.SDL_PIXELFORMAT_BGRA8888, .id = p.SPA_VIDEO_FORMAT_ARGB },
    .{ .format = sdl.SDL_PIXELFORMAT_ABGR8888, .id = p.SPA_VIDEO_FORMAT_RGBA },
    .{ .format = sdl.SDL_PIXELFORMAT_YV12, .id = p.SPA_VIDEO_FORMAT_YV12 },
    .{ .format = sdl.SDL_PIXELFORMAT_IYUV, .id = p.SPA_VIDEO_FORMAT_I420 },
    .{ .format = sdl.SDL_PIXELFORMAT_YUY2, .id = p.SPA_VIDEO_FORMAT_YUY2 },
    .{ .format = sdl.SDL_PIXELFORMAT_UYVY, .id = p.SPA_VIDEO_FORMAT_UYVY },
    .{ .format = sdl.SDL_PIXELFORMAT_YVYU, .id = p.SPA_VIDEO_FORMAT_YVYU },
    .{ .format = sdl.SDL_PIXELFORMAT_NV12, .id = p.SPA_VIDEO_FORMAT_NV12 },
    .{ .format = sdl.SDL_PIXELFORMAT_NV21, .id = p.SPA_VIDEO_FORMAT_NV21 },
};

fn sdlFormatToId(format: u32) u32 {
    for (sdl_video_formats) |f| {
        if (f.format == format) {
            return f.id;
        }
    }
    return p.SPA_VIDEO_FORMAT_UNKNOWN;
}

fn idToSdlFormat(id: u32) u32 {
    for (sdl_video_formats) |f| {
        if (f.id == id) {
            return f.format;
        }
    }
    return sdl.SDL_PIXELFORMAT_UNKNOWN;
}

fn sdlBuildFormats(renderer: *sdl.SDL_Renderer, b: *p.spa_pod_builder) *p.spa_pod {
    var f: [2]p.spa_pod_frame = undefined;

    // make an object of type SPA_TYPE_OBJECT_Format and id SPA_PARAM_EnumFormat. The object type is
    // important because it defines the properties that are acceptable. The id gives more context
    // about what the object is meant to contain. In this case we enumerate supported formats.
    _ = p.spa_pod_builder_push_object(b, &f[0], p.SPA_TYPE_OBJECT_Format, p.SPA_PARAM_EnumFormat);
    // add media type and media subtype properties
    _ = p.spa_pod_builder_prop(b, p.SPA_FORMAT_mediaType, 0);
    _ = p.spa_pod_builder_id(b, p.SPA_MEDIA_TYPE_video);
    _ = p.spa_pod_builder_prop(b, p.SPA_FORMAT_mediaSubtype, 0);
    _ = p.spa_pod_builder_id(b, p.SPA_MEDIA_SUBTYPE_raw);

    // build an enumeration of formats
    _ = p.spa_pod_builder_prop(b, p.SPA_FORMAT_VIDEO_format, 0);
    _ = p.spa_pod_builder_push_choice(b, &f[1], p.SPA_CHOICE_Enum, 0);

    const props: sdl.SDL_PropertiesID = sdl.SDL_GetRendererProperties(renderer);

    const texture_formats: [*]sdl.SDL_PixelFormat = @ptrCast(@alignCast(sdl.SDL_GetPointerProperty(
        props,
        sdl.SDL_PROP_RENDERER_TEXTURE_FORMATS_POINTER,
        null,
    )));

    // first the formats supported by the textures
    var i: u32 = 0;
    var ci: u32 = 0;
    while (texture_formats[i] != sdl.SDL_PIXELFORMAT_UNKNOWN) : (i += 1) {
        const id: u32 = sdlFormatToId(texture_formats[i]);
        if (id == 0) continue;
        if (ci == 0) _ = p.spa_pod_builder_id(b, p.SPA_VIDEO_FORMAT_UNKNOWN);
        ci += 1;
        _ = p.spa_pod_builder_id(b, id);
    }
    // then all the other ones SDL can convert from/to
    for (sdl_video_formats) |format| {
        const id: u32 = format.id;
        if (id != p.SPA_VIDEO_FORMAT_UNKNOWN) {
            _ = p.spa_pod_builder_id(b, id);
        }
    }
    _ = p.spa_pod_builder_id(b, p.SPA_VIDEO_FORMAT_RGBA_F32);
    _ = p.spa_pod_builder_pop(b, &f[1]);
    // add size and framerate ranges
    const max_texture_size: u32 = @intCast(sdl.SDL_GetNumberProperty(
        props,
        sdl.SDL_PROP_RENDERER_MAX_TEXTURE_SIZE_NUMBER,
        0,
    ));
    _ = p.spa_pod_builder_add(
        b,
        p.SPA_FORMAT_VIDEO_size,
        p.SPA_POD_CHOICE_RANGE_Rectangle(
            &p.SPA_RECTANGLE(width, height),
            &p.SPA_RECTANGLE(1, 1),
            &p.SPA_RECTANGLE(max_texture_size, max_texture_size),
        ),
        p.SPA_FORMAT_VIDEO_framerate,
        p.SPA_POD_CHOICE_RANGE_Fraction(
            &p.SPA_FRACTION(rate, 1),
            &p.SPA_FRACTION(0, 1),
            &p.SPA_FRACTION(30, 1),
        ),
        @as(c_int, 0),
    );
    return @ptrCast(@alignCast(p.spa_pod_builder_pop(b, &f[0])));
}
