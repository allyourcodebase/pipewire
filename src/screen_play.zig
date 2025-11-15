const std = @import("std");
const log = std.log;

// const builtin = @import("builtin");
// const std = @import("std");
// const zin = @import("zin");
// const win32 = zin.platform.win32;

// pub const zin_config: zin.Config = .{
//     .StaticWindowId = StaticWindowId,
// };

// const StaticWindowId = enum {
//     main,

//     pub fn getConfig(self: StaticWindowId) zin.WindowConfigData {
//         return switch (self) {
//             .main => .{
//                 .window_size_events = true,
//                 .key_events = false,
//                 .mouse_events = false,
//                 .timers = .one,
//                 .background = .{ .r = 49, .g = 49, .b = 49 },
//                 .dynamic_background = false,
//                 .win32 = .{ .render = .{ .gdi = .{} } },
//                 .x11 = .{ .render_kind = .double_buffered },
//             },
//         };
//     }
// };

// const global = struct {
//     // var class_extra: ?zin.WindowClass = null;
//     var last_animation: ?std.time.Instant = null;
//     var text_position: f32 = 0;
//     var mouse_position: ?zin.XY = null;
// };

// pub fn main() !void {
//     try zin.processInit(.{});
//     {
//         var err: zin.X11ConnectError = undefined;
//         zin.x11Connect(&err) catch std.debug.panic("X11 connect failed: {f}", .{err});
//     }
//     defer zin.x11Disconnect();

//     zin.staticWindow(.main).registerClass(.{
//         .callback = callback,
//         .win32_name = zin.L("Screen Play"),
//         .macos_view = "Screen Play",
//     }, .{
//         .win32_icon_large = .none,
//         .win32_icon_small = .none,
//     });
//     defer zin.staticWindow(.main).unregisterClass();

//     try zin.staticWindow(.main).create(.{
//         .title = "Screen Play",
//         .size = .{ .client_points = .{ .x = 300, .y = 200 } },
//         .pos = null,
//     });
//     defer zin.staticWindow(.main).destroy();
//     zin.staticWindow(.main).show();
//     zin.staticWindow(.main).startTimer({}, 14);

//     try zin.mainLoop();
// }

// fn callback(cb: zin.Callback(.{ .static = .main })) void {
//     switch (cb) {
//         .close => zin.quitMainLoop(),
//         .draw => |d| {
//             zin.staticWindow(.main).invalidate();
//             {
//                 const now = std.time.Instant.now() catch @panic("?");
//                 const elapsed_ns = if (global.last_animation) |l| now.since(l) else 0;
//                 global.last_animation = now;

//                 const speed: f32 = 0.0000000001;
//                 global.text_position = @mod(global.text_position + speed * @as(f32, @floatFromInt(elapsed_ns)), 1.0);
//             }

//             const size = zin.staticWindow(.main).getClientSize();
//             d.clear();
//             const animate: zin.XY = .{
//                 .x = @intFromFloat(@round(@as(f32, @floatFromInt(size.x)) * global.text_position)),
//                 .y = @intFromFloat(@round(@as(f32, @floatFromInt(size.y)) * global.text_position)),
//             };
//             const dpi_scale = d.getDpiScale();

//             // currenly only supported on windows
//             if (zin.platform_kind == .win32 or zin.platform_kind == .x11) {
//                 var pentagon = [5]zin.PolygonPoint{
//                     .xy(zin.scale(i32, 200, dpi_scale.x), zin.scale(i32, 127, dpi_scale.y)), // top
//                     .xy(zin.scale(i32, 232, dpi_scale.x), zin.scale(i32, 150, dpi_scale.y)), // top right
//                     .xy(zin.scale(i32, 220, dpi_scale.x), zin.scale(i32, 187, dpi_scale.y)), // bottom right
//                     .xy(zin.scale(i32, 180, dpi_scale.x), zin.scale(i32, 187, dpi_scale.y)), // bottom left
//                     .xy(zin.scale(i32, 168, dpi_scale.x), zin.scale(i32, 150, dpi_scale.y)), // top left
//                 };
//                 d.polygon(&pentagon, .blue);
//             }

//             const rect_size = zin.scale(i32, 10, dpi_scale.x);
//             d.rect(.ltwh(animate.x, size.y - animate.y, rect_size, rect_size), .red);
//             const margin_left = zin.scale(i32, 10, dpi_scale.x);
//             const top = zin.scale(i32, 50, dpi_scale.y);
//             d.text("Press 'n' to create a new window.", margin_left, top, .white);
//             d.text("Weeee!!!", animate.x, animate.y, .white);
//             if (global.mouse_position) |p| {
//                 d.text("Mouse", p.x, p.y, .white);
//             }
//         },
//         .timer => zin.staticWindow(.main).invalidate(),
//         else => {},
//     }
// }

const c = @import("c.zig");
// const c = @cImport({
//     @cInclude("spa/utils/defs.h");
//     @cInclude("pipewire/pipewire.h");
//     @cInclude("spa/param/video/format-utils.h");
//     @cInclude("spa/debug/format.h");
// });

// XXX: ...
// #include <stdio.h>
// #include <unistd.h>
// #include <signal.h>

// #include <spa/utils/result.h>
// #include <spa/param/video/format-utils.h>
// #include <spa/param/tag-utils.h>
// #include <spa/param/props.h>
// #include <spa/param/latency-utils.h>
// #include <spa/debug/pod.h>

// #include <pipewire/pipewire.h>

// XXX: use rate
const width = 1920;
const height = 1080;
const rate = 30;

// #define MAX_BUFFERS 64

// #include "sdl.h"

// struct pixel {
//     float r, g, b, a;
// };

const Data = struct {
    // path: []const u8,

    // SDL_Renderer *renderer;
    // SDL_Window *window;
    // SDL_Texture *texture;
    // SDL_Texture *cursor;

    loop: *c.pw_main_loop,

    // stream: *c.pw_stream,
    // stream_listener: *c.spa_hook,

    // position: *c.spa_io_position,

    // format: c.spa_video_info,
    // stride: i32,
    // size: c.spa_rectangle,

    // counter: c_int, // XXX: type?
    // rect: c.SDL_FRect,
    // cursor_rect: c.SDL_FRect,
    // is_yuv: bool,
};

// static void handle_events(struct data *data)
// {
//     // SDL_Event event;
//     // while (SDL_PollEvent(&event)) {
//     //  switch (event.type) {
//     //  case SDL_EVENT_QUIT:
//     //      pw_main_loop_quit(data->loop);
//     //      break;
//     //  }
//     // }
// }

// /* our data processing function is in general:
//  *
//  *  struct pw_buffer *b;
//  *  b = pw_stream_dequeue_buffer(stream);
//  *
//  *  .. do stuff with buffer ...
//  *
//  *  pw_stream_queue_buffer(stream, b);
//  */
fn onProcess(data: ?*anyopaque) callconv(.c) void {
    _ = data;
    // struct data *data = _data;
    // struct pw_stream *stream = data->stream;
    // struct pw_buffer *b;
    // struct spa_buffer *buf;
    // void *sdata, *ddata;
    // int sstride, dstride, ostride;
    // struct spa_meta_region *mc;
    // struct spa_meta_cursor *mcs;
    // struct spa_meta_header *h;
    // uint32_t i, j;
    // uint8_t *src, *dst;
    // bool render_cursor = false;

    // b = NULL;
    // while (true) {
    //     struct pw_buffer *t;
    //     if ((t = pw_stream_dequeue_buffer(stream)) == NULL)
    //         break;
    //     if (b)
    //         pw_stream_queue_buffer(stream, b);
    //     b = t;
    // }
    // if (b == NULL) {
    //     pw_log_warn("out of buffers: %m");
    //     return;
    // }

    // buf = b->buffer;

    // pw_log_trace("new buffer %p", buf);

    // handle_events(data);

    // if ((sdata = buf->datas[0].data) == NULL)
    //     goto done;

    // if ((h = spa_buffer_find_meta_data(buf, SPA_META_Header, sizeof(*h)))) {
    //     uint64_t now = pw_stream_get_nsec(stream);
    //     pw_log_debug("now:%"PRIu64" pts:%"PRIu64" diff:%"PRIi64,
    //             now, h->pts, now - h->pts);
    // }

    // /* get the videocrop metadata if any */
    // if ((mc = spa_buffer_find_meta_data(buf, SPA_META_VideoCrop, sizeof(*mc))) &&
    //     spa_meta_region_is_valid(mc)) {
    //     data->rect.x = mc->region.position.x;
    //     data->rect.y = mc->region.position.y;
    //     data->rect.w = mc->region.size.width;
    //     data->rect.h = mc->region.size.height;
    // }
    // /* get cursor metadata */
    // if ((mcs = spa_buffer_find_meta_data(buf, SPA_META_Cursor, sizeof(*mcs))) &&
    //     spa_meta_cursor_is_valid(mcs)) {
    //     struct spa_meta_bitmap *mb;
    //     void *cdata;
    //     int cstride;

    //     data->cursor_rect.x = mcs->position.x;
    //     data->cursor_rect.y = mcs->position.y;

    //     mb = SPA_PTROFF(mcs, mcs->bitmap_offset, struct spa_meta_bitmap);
    //     data->cursor_rect.w = mb->size.width;
    //     data->cursor_rect.h = mb->size.height;

    //     // if (data->cursor == NULL) {
    //     //  data->cursor = SDL_CreateTexture(data->renderer,
    //     //               id_to_sdl_format(mb->format),
    //     //               SDL_TEXTUREACCESS_STREAMING,
    //     //               mb->size.width, mb->size.height);
    //     //  SDL_SetTextureBlendMode(data->cursor, SDL_BLENDMODE_BLEND);
    //     // }

    //     // if (!SDL_LockTexture(data->cursor, NULL, &cdata, &cstride)) {
    //     //  fprintf(stderr, "Couldn't lock cursor texture: %s\n", SDL_GetError());
    //     //  goto done;
    //     // }

    //     /* copy the cursor bitmap into the texture */
    //     src = SPA_PTROFF(mb, mb->offset, uint8_t);
    //     dst = cdata;
    //     ostride = SPA_MIN(cstride, mb->stride);

    //     for (i = 0; i < mb->size.height; i++) {
    //         memcpy(dst, src, ostride);
    //         dst += cstride;
    //         src += mb->stride;
    //     }
    //     // SDL_UnlockTexture(data->cursor);

    //     render_cursor = true;
    // }

    // /* copy video image in texture */
    // if (data->is_yuv) {
    //     void *datas[4];
    //     sstride = data->stride;
    //     if (buf->n_datas == 1) {
    //         // SDL_UpdateTexture(data->texture, NULL,
    //         //      sdata, sstride);
    //     } else {
    //         datas[0] = sdata;
    //         datas[1] = buf->datas[1].data;
    //         datas[2] = buf->datas[2].data;
    //         // SDL_UpdateYUVTexture(data->texture, NULL,
    //         //      datas[0], sstride,
    //         //      datas[1], sstride / 2,
    //         //      datas[2], sstride / 2);
    //     }
    // }
    // else {
    //     // if (!SDL_LockTexture(data->texture, NULL, &ddata, &dstride)) {
    //     //  fprintf(stderr, "Couldn't lock texture: %s\n", SDL_GetError());
    //     // }

    //     sstride = buf->datas[0].chunk->stride;
    //     if (sstride == 0)
    //         sstride = buf->datas[0].chunk->size / data->size.height;
    //     ostride = SPA_MIN(sstride, dstride);

    //     src = sdata;
    //     dst = ddata;

    //     if (data->format.media_subtype == SPA_MEDIA_SUBTYPE_dsp) {
    //         for (i = 0; i < data->size.height; i++) {
    //             struct pixel *p = (struct pixel *) src;
    //             for (j = 0; j < data->size.width; j++) {
    //                 dst[j * 4 + 0] = SPA_CLAMP((uint8_t)(p[j].r * 255.0f), 0u, 255u);
    //                 dst[j * 4 + 1] = SPA_CLAMP((uint8_t)(p[j].g * 255.0f), 0u, 255u);
    //                 dst[j * 4 + 2] = SPA_CLAMP((uint8_t)(p[j].b * 255.0f), 0u, 255u);
    //                 dst[j * 4 + 3] = SPA_CLAMP((uint8_t)(p[j].a * 255.0f), 0u, 255u);
    //             }
    //             src += sstride;
    //             dst += dstride;
    //         }
    //     } else {
    //         for (i = 0; i < data->size.height; i++) {
    //             memcpy(dst, src, ostride);
    //             src += sstride;
    //             dst += dstride;
    //         }
    //     }
    //     // SDL_UnlockTexture(data->texture);
    // }

    // // SDL_RenderClear(data->renderer);
    // // /* now render the video and then the cursor if any */
    // // SDL_RenderTexture(data->renderer, data->texture, &data->rect, NULL);
    // // if (render_cursor) {
    // //  SDL_RenderTexture(data->renderer, data->cursor, NULL, &data->cursor_rect);
    // // }
    // // SDL_RenderPresent(data->renderer);

    //   done:
    // pw_stream_queue_buffer(stream, b);
}

fn onStreamStateChanged(
    data: ?*anyopaque,
    old: c.pw_stream_state,
    state: c.pw_stream_state,
    err: [*c]const u8,
) callconv(.c) void {
    _ = data;
    _ = old;
    _ = state;
    _ = err;
    // XXX: ...
    // struct data *data = _data;
    // fprintf(stderr, "stream state: \"%s\"\n", pw_stream_state_as_string(state));
    // switch (state) {
    // case PW_STREAM_STATE_UNCONNECTED:
    //     pw_main_loop_quit(data->loop);
    //     break;
    // case PW_STREAM_STATE_PAUSED:
    //     /* because we started inactive, activate ourselves now */
    //     pw_stream_set_active(data->stream, true);
    //     break;
    // default:
    //     break;
    // }
}

fn onStreamIoChanged(data: ?*anyopaque, id: u32, area: ?*anyopaque, size: u32) callconv(.c) void {
    _ = data;
    _ = id;
    _ = area;
    _ = size;
    // XXX: ...
    // struct data *data = _data;

    // switch (id) {
    // case SPA_IO_Position:
    //     data->position = area;
    //     break;
    // }
}

// /* Be notified when the stream param changes. We're only looking at the
//  * format changes.
//  *
//  * We are now supposed to call pw_stream_finish_format() with success or
//  * failure, depending on if we can support the format. Because we gave
//  * a list of supported formats, this should be ok.
//  *
//  * As part of pw_stream_finish_format() we can provide parameters that
//  * will control the buffer memory allocation. This includes the metadata
//  * that we would like on our buffer, the size, alignment, etc.
//  */
fn onStreamParamChanged(data: ?*anyopaque, id: u32, param: [*c]const c.spa_pod) callconv(.c) void {
    _ = data;
    _ = id;
    _ = param;
    //     struct data *data = _data;
    //     struct pw_stream *stream = data->stream;
    //     uint8_t params_buffer[1024];
    //     struct spa_pod_builder b = SPA_POD_BUILDER_INIT(params_buffer, sizeof(params_buffer));
    //     const struct spa_pod *params[5];
    //     uint32_t n_params = 0;
    //     Uint32 sdl_format;
    //     void *d;
    //     int32_t mult, size, blocks;

    //     if (param != NULL && id == SPA_PARAM_Tag) {
    //         spa_debug_pod(0, NULL, param);
    //         return;
    //     }
    //     if (param != NULL && id == SPA_PARAM_Latency) {
    //         struct spa_latency_info info;
    //         if (spa_latency_parse(param, &info) >= 0)
    //             fprintf(stderr, "got latency: %"PRIu64"\n", (info.min_ns + info.max_ns) / 2);
    //         return;
    //     }
    //     /* NULL means to clear the format */
    //     if (param == NULL || id != SPA_PARAM_Format)
    //         return;

    //     fprintf(stderr, "got format:\n");
    //     spa_debug_format(2, NULL, param);

    //     if (spa_format_parse(param, &data->format.media_type, &data->format.media_subtype) < 0)
    //         return;

    //     if (data->format.media_type != SPA_MEDIA_TYPE_video)
    //         return;

    //     switch (data->format.media_subtype) {
    //     case SPA_MEDIA_SUBTYPE_raw:
    //         /* call a helper function to parse the format for us. */
    //         spa_format_video_raw_parse(param, &data->format.info.raw);
    //         sdl_format = id_to_sdl_format(data->format.info.raw.format);
    //         data->size = SPA_RECTANGLE(data->format.info.raw.size.width,
    //                 data->format.info.raw.size.height);
    //         mult = 1;
    //         break;
    //     case SPA_MEDIA_SUBTYPE_dsp:
    //         spa_format_video_dsp_parse(param, &data->format.info.dsp);
    //         if (data->format.info.dsp.format != SPA_VIDEO_FORMAT_DSP_F32)
    //             return;
    //         sdl_format = SDL_PIXELFORMAT_RGBA32;
    //         data->size = SPA_RECTANGLE(data->position->video.size.width,
    //                 data->position->video.size.height);
    //         mult = 4;
    //         break;
    //     default:
    //         sdl_format = SDL_PIXELFORMAT_UNKNOWN;
    //         break;
    //     }

    //     if (sdl_format == SDL_PIXELFORMAT_UNKNOWN) {
    //         pw_stream_set_error(stream, -EINVAL, "unknown pixel format");
    //         return;
    //     }
    //     if (data->size.width == 0 || data->size.height == 0) {
    //         pw_stream_set_error(stream, -EINVAL, "invalid size");
    //         return;
    //     }

    //     data->texture = SDL_CreateTexture(data->renderer,
    //                       sdl_format,
    //                       SDL_TEXTUREACCESS_STREAMING,
    //                       data->size.width,
    //                       data->size.height);
    //     switch(sdl_format) {
    //     case SDL_PIXELFORMAT_YV12:
    //     case SDL_PIXELFORMAT_IYUV:
    //         data->stride = data->size.width;
    //         size = (data->stride * data->size.height) * 3 / 2;
    //         data->is_yuv = true;
    //         blocks = 3;
    //         break;
    //     case SDL_PIXELFORMAT_YUY2:
    //         data->is_yuv = true;
    //         data->stride = data->size.width * 2;
    //         size = (data->stride * data->size.height);
    //         blocks = 1;
    //         break;
    //     default:
    //         if (!SDL_LockTexture(data->texture, NULL, &d, &data->stride)) {
    //             fprintf(stderr, "Couldn't lock texture: %s\n", SDL_GetError());
    //             data->stride = data->size.width * 2;
    //         } else
    //             SDL_UnlockTexture(data->texture);
    //         size = data->stride * data->size.height;
    //         blocks = 1;
    //         break;
    //     }

    //     data->rect.x = 0;
    //     data->rect.y = 0;
    //     data->rect.w = data->size.width;
    //     data->rect.h = data->size.height;

    //     /* a SPA_TYPE_OBJECT_ParamBuffers object defines the acceptable size,
    //      * number, stride etc of the buffers */
    //     params[n_params++] = spa_pod_builder_add_object(&b,
    //         SPA_TYPE_OBJECT_ParamBuffers, SPA_PARAM_Buffers,
    //         SPA_PARAM_BUFFERS_buffers, SPA_POD_CHOICE_RANGE_Int(8, 2, MAX_BUFFERS),
    //         SPA_PARAM_BUFFERS_blocks,  SPA_POD_Int(blocks),
    //         SPA_PARAM_BUFFERS_size,    SPA_POD_Int(size * mult),
    //         SPA_PARAM_BUFFERS_stride,  SPA_POD_Int(data->stride * mult),
    //         SPA_PARAM_BUFFERS_dataType, SPA_POD_CHOICE_FLAGS_Int((1<<SPA_DATA_MemPtr)));

    //     /* a header metadata with timing information */
    //     params[n_params++] = spa_pod_builder_add_object(&b,
    //         SPA_TYPE_OBJECT_ParamMeta, SPA_PARAM_Meta,
    //         SPA_PARAM_META_type, SPA_POD_Id(SPA_META_Header),
    //         SPA_PARAM_META_size, SPA_POD_Int(sizeof(struct spa_meta_header)));
    //     /* video cropping information */
    //     params[n_params++] = spa_pod_builder_add_object(&b,
    //         SPA_TYPE_OBJECT_ParamMeta, SPA_PARAM_Meta,
    //         SPA_PARAM_META_type, SPA_POD_Id(SPA_META_VideoCrop),
    //         SPA_PARAM_META_size, SPA_POD_Int(sizeof(struct spa_meta_region)));
    // #define CURSOR_META_SIZE(w,h)   (sizeof(struct spa_meta_cursor) + \
    //                  sizeof(struct spa_meta_bitmap) + w * h * 4)
    //     /* cursor information */
    //     params[n_params++] = spa_pod_builder_add_object(&b,
    //         SPA_TYPE_OBJECT_ParamMeta, SPA_PARAM_Meta,
    //         SPA_PARAM_META_type, SPA_POD_Id(SPA_META_Cursor),
    //         SPA_PARAM_META_size, SPA_POD_CHOICE_RANGE_Int(
    //                 CURSOR_META_SIZE(64,64),
    //                 CURSOR_META_SIZE(1,1),
    //                 CURSOR_META_SIZE(256,256)));

    //     /* we are done */
    //     pw_stream_update_params(stream, params, n_params);
}

// XXX: hand translated, could maybe just not even use this helper tbh
fn spa_pod_builder_add_object(b: *c.spa_pod_builder, ty: u32, id: u32, args: anytype) ?*anyopaque {
    var f: c.spa_pod_frame = undefined;
    // XXX: res ignored
    _ = c.spa_pod_builder_push_object(b, &f, ty, id);
    _ = @call(.auto, c.spa_pod_builder_add, .{b} ++ args ++ .{@as(c_int, 0)});
    return c.spa_pod_builder_pop(b, &f);
}

fn buildFormat(data: *Data, b: *c.spa_pod_builder, params: *[3]?*c.spa_pod) u32 {
    _ = data; // XXX: ...
    var n_params: u32 = 0;

    params[n_params] = sdlBuildFormats(
        // data.renderer,
        b,
    );
    n_params += 1;

    log.info("supported SDL formats:", .{});
    _ = c.spa_debug_format(2, null, params[0]); // XXX: ignored result?

    // XXX: CURRENT: this one fails to translate, translated it manually but getting crash, not sure
    // if here or elsewhere
    // params[n_params] = @ptrCast(@alignCast(spa_pod_builder_add_object(
    //     b,
    //     c.SPA_TYPE_OBJECT_Format,
    //     c.SPA_PARAM_EnumFormat,
    //     .{
    //         c.SPA_FORMAT_mediaType,
    //         c.SPA_POD_Id(c.SPA_MEDIA_TYPE_video),
    //         c.SPA_FORMAT_mediaSubtype,
    //         c.SPA_POD_Id(c.SPA_MEDIA_SUBTYPE_dsp),
    //         c.SPA_FORMAT_VIDEO_format,
    //         c.SPA_POD_Id(c.SPA_VIDEO_FORMAT_DSP_F32),
    //     },
    // )));
    // n_params += 1;

    // log.info("supported DSP formats:", .{});
    // c.spa_debug_format(2, null, params[1]);

    return n_params;
}

// static void do_quit(void *userdata, int signal_number)
// {
//     struct data *data = userdata;
//     pw_main_loop_quit(data->loop);
// }

// XXX: document where this is adapted from if we keep the comments and such, probalby jsut don't keep them?
pub fn main() void {
    // struct data data = { 0, };
    var buffer: [1024]u8 = undefined;
    var b: c.spa_pod_builder = .{
        .data = &buffer,
        .size = buffer.len,
        ._padding = 0,
        .state = .{ .offset = 0, .flags = 0, .frame = null },
        .callbacks = .{ .funcs = null, .data = null },
    };
    // struct pw_properties *props;
    // int res, n_params;

    c.pw_init(0, null);
    defer c.pw_deinit();

    // /* create a main loop */
    // Create a main loop
    // XXX: ...add to data
    const loop = c.pw_main_loop_new(null).?;

    // create a simple stream, the simple stream manages to core and remote
    // objects for you if you don't need to deal with them
    //
    // If you plan to autoconnect your stream, you need to provide at least
    // media, category and role properties
    //
    // Pass your events and a user_data pointer as the last arguments. This
    // will inform you about the stream state. The most important event
    // you need to listen to is the process event where you need to consume
    // the data provided to you.
    //
    const props = c.pw_properties_new(
        c.PW_KEY_MEDIA_TYPE,
        "Video",
        c.PW_KEY_MEDIA_CATEGORY,
        "Capture",
        c.PW_KEY_MEDIA_ROLE,
        "Camera",
        @as(?*anyopaque, null),
    );
    // XXX: need this?
    // data.path = argc > 1 ? argv[1] : NULL;
    // if (data.path)
    //     pw_properties_set(props, PW_KEY_TARGET_OBJECT, data.path);

    // XXX: add to data?
    // XXX: make var if modified?
    var data: Data = .{
        .loop = loop,
    };
    const stream = c.pw_stream_new_simple(
        c.pw_main_loop_get_loop(data.loop),
        "video-play",
        props,
        &.{
            .version = c.PW_VERSION_STREAM_EVENTS,
            .state_changed = &onStreamStateChanged,
            .io_changed = &onStreamIoChanged,
            .param_changed = &onStreamParamChanged,
            .process = &onProcess,
        },
        &data,
    );
    _ = stream;

    // // if (!SDL_Init(SDL_INIT_VIDEO)) {
    // //  fprintf(stderr, "can't initialize SDL: %s\n", SDL_GetError());
    // //  return -1;
    // // }

    // // if (!SDL_CreateWindowAndRenderer("Demo", WIDTH, HEIGHT, SDL_WINDOW_RESIZABLE, &data.window, &data.renderer)) {
    // //  fprintf(stderr, "can't create window: %s\n", SDL_GetError());
    // //  return -1;
    // // }

    // /* build the extra parameters to connect with. To connect, we can provide
    //  * a list of supported formats.  We use a builder that writes the param
    //  * object to the stack. */
    var params: [3]?*c.spa_pod = undefined; // XXX: nullable or not?
    const n_params = buildFormat(&data, &b, &params);
    _ = n_params;

    // {
    //     struct spa_pod_frame f;
    //     struct spa_dict_item items[1];
    //     /* send a tag, input tags travel upstream */
    //     spa_tag_build_start(&b, &f, SPA_PARAM_Tag, SPA_DIRECTION_INPUT);
    //     items[0] = SPA_DICT_ITEM_INIT("my-tag-other-key", "my-special-other-tag-value");
    //     spa_tag_build_add_dict(&b, &SPA_DICT_INIT(items, 1));
    //     params[n_params++] = spa_tag_build_end(&b, &f);
    // }

    // /* now connect the stream, we need a direction (input/output),
    //  * an optional target node to connect to, some flags and parameters
    //  */
    // if ((res = pw_stream_connect(data.stream,
    //           PW_DIRECTION_INPUT,
    //           PW_ID_ANY,
    //           PW_STREAM_FLAG_AUTOCONNECT |  /* try to automatically connect this stream */
    //           PW_STREAM_FLAG_INACTIVE | /* we will activate ourselves */
    //           PW_STREAM_FLAG_MAP_BUFFERS,   /* mmap the buffer data for us */
    //           params, n_params))        /* extra parameters, see above */ < 0) {
    //     fprintf(stderr, "can't connect: %s\n", spa_strerror(res));
    //     return -1;
    // }

    // /* do things until we quit the mainloop */
    // pw_main_loop_run(data.loop);

    // pw_stream_destroy(data.stream);
    // pw_main_loop_destroy(data.loop);

    // // SDL_DestroyTexture(data.texture);
    // // if (data.cursor)
    // //  SDL_DestroyTexture(data.cursor);
    // // SDL_DestroyRenderer(data.renderer);
    // // SDL_DestroyWindow(data.window);
}

// XXX: sdl...
// XXX: ...

// /* PipeWire */
// /* SPDX-FileCopyrightText: Copyright © 2018 Wim Taymans */
// /* SPDX-License-Identifier: MIT */

// /*
//  [title]
//  SDL2 video format conversions
//  [title]
//  */

// #include <SDL3/SDL.h>

// #include <spa/utils/type.h>
// #include <spa/pod/builder.h>
// #include <spa/param/video/raw.h>
// #include <spa/param/video/format.h>

const VideoFormat = struct {
    format: u32,
    id: u32,
};
const sdl_video_formats = [_]VideoFormat{
    .{ c.SDL_PIXELFORMAT_UNKNOWN, c.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ c.SDL_PIXELFORMAT_INDEX1LSB, c.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ c.SDL_PIXELFORMAT_UNKNOWN, c.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ c.SDL_PIXELFORMAT_INDEX1LSB, c.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ c.SDL_PIXELFORMAT_INDEX1MSB, c.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ c.SDL_PIXELFORMAT_INDEX4LSB, c.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ c.SDL_PIXELFORMAT_INDEX4MSB, c.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ c.SDL_PIXELFORMAT_INDEX8, c.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ c.SDL_PIXELFORMAT_RGB332, c.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ c.SDL_PIXELFORMAT_XRGB4444, c.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ c.SDL_PIXELFORMAT_XRGB1555, c.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ c.SDL_PIXELFORMAT_XBGR1555, c.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ c.SDL_PIXELFORMAT_ARGB4444, c.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ c.SDL_PIXELFORMAT_RGBA4444, c.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ c.SDL_PIXELFORMAT_ABGR4444, c.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ c.SDL_PIXELFORMAT_BGRA4444, c.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ c.SDL_PIXELFORMAT_ARGB1555, c.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ c.SDL_PIXELFORMAT_RGBA5551, c.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ c.SDL_PIXELFORMAT_ABGR1555, c.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ c.SDL_PIXELFORMAT_BGRA5551, c.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ c.SDL_PIXELFORMAT_RGB565, c.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ c.SDL_PIXELFORMAT_BGR565, c.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ c.SDL_PIXELFORMAT_RGB24, c.SPA_VIDEO_FORMAT_BGR },
    .{ c.SDL_PIXELFORMAT_XRGB8888, c.SPA_VIDEO_FORMAT_BGR },
    .{ c.SDL_PIXELFORMAT_RGBX8888, c.SPA_VIDEO_FORMAT_xBGR },
    .{ c.SDL_PIXELFORMAT_BGR24, c.SPA_VIDEO_FORMAT_RGB },
    .{ c.SDL_PIXELFORMAT_XBGR8888, c.SPA_VIDEO_FORMAT_RGB },
    .{ c.SDL_PIXELFORMAT_BGRX8888, c.SPA_VIDEO_FORMAT_xRGB },
    .{ c.SDL_PIXELFORMAT_ARGB2101010, c.SPA_VIDEO_FORMAT_UNKNOWN },
    .{ c.SDL_PIXELFORMAT_RGBA8888, c.SPA_VIDEO_FORMAT_ABGR },
    .{ c.SDL_PIXELFORMAT_ARGB8888, c.SPA_VIDEO_FORMAT_BGRA },
    .{ c.SDL_PIXELFORMAT_BGRA8888, c.SPA_VIDEO_FORMAT_ARGB },
    .{ c.SDL_PIXELFORMAT_ABGR8888, c.SPA_VIDEO_FORMAT_RGBA },
    .{ c.SDL_PIXELFORMAT_YV12, c.SPA_VIDEO_FORMAT_YV12 },
    .{ c.SDL_PIXELFORMAT_IYUV, c.SPA_VIDEO_FORMAT_I420 },
    .{ c.SDL_PIXELFORMAT_YUY2, c.SPA_VIDEO_FORMAT_YUY2 },
    .{ c.SDL_PIXELFORMAT_UYVY, c.SPA_VIDEO_FORMAT_UYVY },
    .{ c.SDL_PIXELFORMAT_YVYU, c.SPA_VIDEO_FORMAT_YVYU },
    .{ c.SDL_PIXELFORMAT_NV12, c.SPA_VIDEO_FORMAT_NV12 },
    .{ c.SDL_PIXELFORMAT_NV21, c.SPA_VIDEO_FORMAT_NV21 },
};

fn sdlBuildFormats(
    // renderer: *c.SDL_Renderer,
    b: *c.spa_pod_builder,
) ?*c.spa_pod {
    // // uint32_t i, c;
    var f: [2]c.spa_pod_frame = undefined;
    // XXX: results ignored?
    _ = c.spa_pod_builder_push_object(b, &f[0], c.SPA_TYPE_OBJECT_Format, c.SPA_PARAM_EnumFormat);
    _ = c.spa_pod_builder_prop(b, c.SPA_FORMAT_mediaType, 0);
    _ = c.spa_pod_builder_id(b, c.SPA_MEDIA_TYPE_video);
    _ = c.spa_pod_builder_prop(b, c.SPA_FORMAT_mediaSubtype, 0);
    _ = c.spa_pod_builder_id(b, c.SPA_MEDIA_SUBTYPE_raw);

    _ = c.spa_pod_builder_prop(b, c.SPA_FORMAT_VIDEO_format, 0);
    _ = c.spa_pod_builder_push_choice(b, &f[1], c.SPA_CHOICE_Enum, 0);

    // // const props: c.SDL_PropertiesID = c.SDL_GetRendererProperties(renderer);

    // // const SDL_PixelFormat *texture_formats = nullptr;
    // // SDL_GetPointerProperty(
    // //  props,
    // //  SDL_PROP_RENDERER_TEXTURE_FORMATS_POINTER,
    // //  NULL
    // // );

    // c.SPA_FOR_EACH_ELEMENT_VAR(sdl_video_formats, f) {
    //     var id: u32 = f.id;
    //     if (id != c.SPA_VIDEO_FORMAT_UNKNOWN)
    //         c.spa_pod_builder_id(b, id);
    // }

    // XXX: hack: just picked a format for now
    _ = c.spa_pod_builder_id(b, c.SPA_VIDEO_FORMAT_BGR);

    _ = c.spa_pod_builder_id(b, c.SPA_VIDEO_FORMAT_RGBA_F32);
    _ = c.spa_pod_builder_pop(b, &f[1]);
    // add size and framerate ranges
    const max_texture_size: u64 = 4096;
    _ = c.spa_pod_builder_add(
        b,
        c.SPA_FORMAT_VIDEO_size,
        c.SPA_POD_CHOICE_RANGE_Rectangle(
            &c.SPA_RECTANGLE(width, height),
            &c.SPA_RECTANGLE(1, 1),
            &c.SPA_RECTANGLE(max_texture_size, max_texture_size),
        ),
        c.SPA_FORMAT_VIDEO_framerate,
        c.SPA_POD_CHOICE_RANGE_Fraction(
            &c.SPA_FRACTION(rate, 1),
            &c.SPA_FRACTION(0, 1),
            &c.SPA_FRACTION(30, 1),
        ),
        @as(c_int, 0),
    );
    return @ptrCast(@alignCast(c.spa_pod_builder_pop(b, &f[0])));
}
