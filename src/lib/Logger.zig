//! A logger that forwards pipewire logs to `std.log.`
//!
//! May be initialized with `pw_log_set` before initializing pipewire. Don't forget to call
//! `pw_log_set_level`.

const std = @import("std");
const c = @import("root.zig").c;

pub const default_level = switch (std.options.log_level) {
    .err => c.SPA_LOG_LEVEL_ERROR,
    .warn => c.SPA_LOG_LEVEL_WARN,
    .info => c.SPA_LOG_LEVEL_INFO,
    .debug => c.SPA_LOG_LEVEL_TRACE,
};
pub const scope = .pw;

pub fn init() c.spa_log {
    return .{
        .iface = .{
            .type = c.SPA_TYPE_INTERFACE_Log,
            .version = c.SPA_VERSION_LOG,
            .cb = .{
                .funcs = &c.spa_log_methods{
                    .version = c.SPA_VERSION_LOG_METHODS,
                    .log = &Methods.log,
                    .logt = &Methods.logt,
                    // We have to pointer cast these due to the way the variadic argument list
                    // is translated.
                    .logv = @ptrCast(&Methods.logv),
                    .logtv = @ptrCast(&Methods.logtv),
                    .topic_init = &Methods.topicInit,
                },
                // Appears to be unused, likely intended as userdata
                .data = null,
            },
        },
        .level = default_level,
    };
}

pub fn dbgCtx(
    comptime ctx_level: std.log.Level,
    comptime ctx_scope: @TypeOf(.enum_literal),
) *c.spa_debug_context {
    const DebugContext = struct {
        fn callback(_: ?*c.spa_debug_context, fmt: [*c]const u8, ...) callconv(.c) void {
            var args = @cVaStart();
            defer @cVaEnd(&args);

            if (!std.log.logEnabled(ctx_level, ctx_scope)) return;
            var buf: [1024]u8 = undefined;
            const formatted = b: {
                const max_len = c.spa_vscnprintf(&buf, buf.len, fmt, @ptrCast(&args));
                if (max_len < 0) break :b "(formatting failed)";
                break :b buf[0..@min(buf.len - 1, @as(usize, @intCast(max_len)))];
            };
            std.options.logFn(ctx_level, ctx_scope, "{s}", .{formatted});
        }

        var instance: c.spa_debug_context = .{ .log = &callback };
    };
    return &DebugContext.instance;
}

const Methods = struct {
    fn log(
        object: ?*anyopaque,
        pw_level: c.spa_log_level,
        file_abs_c: [*c]const u8,
        line: c_int,
        func: [*c]const u8,
        fmt: [*c]const u8,
        ...,
    ) callconv(.c) void {
        var args = @cVaStart();
        defer @cVaEnd(&args);
        logtv(object, pw_level, null, file_abs_c, line, func, fmt, &args);
    }

    fn logv(
        object: ?*anyopaque,
        pw_level: c.spa_log_level,
        file_abs_c: [*c]const u8,
        line: c_int,
        func: [*c]const u8,
        fmt: [*c]const u8,
        args: ?*std.builtin.VaList,
    ) callconv(.c) void {
        logtv(object, pw_level, null, file_abs_c, line, func, fmt, args);
    }

    fn logt(
        object: ?*anyopaque,
        pw_level: c.spa_log_level,
        topic: ?*const c.spa_log_topic,
        file_abs_c: [*c]const u8,
        line: c_int,
        func: [*c]const u8,
        fmt: [*c]const u8,
        ...,
    ) callconv(.c) void {
        var args = @cVaStart();
        defer @cVaEnd(&args);
        logtv(object, pw_level, topic, file_abs_c, line, func, fmt, &args);
    }

    fn logtv(
        object: ?*anyopaque,
        pw_level: c.spa_log_level,
        topic: ?*const c.spa_log_topic,
        file_abs_c: [*c]const u8,
        line: c_int,
        func: [*c]const u8,
        fmt: [*c]const u8,
        args: ?*std.builtin.VaList,
    ) callconv(.c) void {
        // Object seems to be ignored by default logger. I believe the messages include it in
        // the formatted string when relevant.
        _ = object;
        // Topics are not useful in practice, they're often redundant with filename and message
        // content, and we've already uniquely identified the log by file and line number. They
        // are likely present for topic based filtering which we don't support anyway.
        _ = topic;
        // Function names add a lot of noise to the log, and this information can be deduced
        // from the file name and line number, so we skip it.
        _ = func;

        // Convert to Zig log levels.
        const level: std.log.Level = switch (pw_level) {
            c.SPA_LOG_LEVEL_NONE => return,
            c.SPA_LOG_LEVEL_ERROR => .err,
            c.SPA_LOG_LEVEL_WARN => .warn,
            c.SPA_LOG_LEVEL_INFO => .info,
            c.SPA_LOG_LEVEL_DEBUG, c.SPA_LOG_LEVEL_TRACE => .debug,
            else => .err,
        };

        // We don't want to log absolute file paths. That's overly verbose, and exposes more
        // information to logs than is likely intended.
        const file = b: {
            const file_abs = std.mem.span(file_abs_c);
            const i = std.mem.lastIndexOfAny(u8, file_abs, "\\/") orelse break :b file_abs;
            break :b file_abs[i + 1 ..];
        };

        // Perform the log. We use an inline else to make the level comptime known.
        switch (level) {
            inline else => |l| {
                if (!std.log.logEnabled(l, scope)) return;
                var buf: [1024]u8 = undefined;
                const formatted = b: {
                    const max_len = c.spa_vscnprintf(&buf, buf.len, fmt, @ptrCast(args));
                    if (max_len < 0) break :b "(formatting failed)";
                    break :b buf[0..@min(buf.len - 1, @as(usize, @intCast(max_len)))];
                };
                std.options.logFn(l, scope, "{s}:{}: {s}", .{
                    file,
                    line,
                    formatted,
                });
            },
        }
    }

    fn topicInit(object: ?*anyopaque, topic: ?*c.spa_log_topic) callconv(.c) void {
        // Noop in default implementation as well
        _ = object;
        _ = topic;
    }
};
