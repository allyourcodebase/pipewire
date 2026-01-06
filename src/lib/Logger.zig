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

extern const __logger_methods: ?*anyopaque;

pub fn init() c.spa_log {
    return .{
        .iface = .{
            .type = c.SPA_TYPE_INTERFACE_Log,
            .version = c.SPA_VERSION_LOG,
            .cb = .{
                .funcs = __logger_methods,
                // Appears to be unused, likely intended as userdata
                .data = null,
            },
        },
        .level = default_level,
    };
}

const DebugContextData = struct {
    spa: c.spa_debug_context,
    level: std.log.Level,
    zigLog: *const fn (msg: []const u8) void,
};

// See `va.c`
extern fn __dbg_ctx__spaCallbackReal(?*c.spa_debug_context, [*c]const u8, ...) callconv(.c) void;
extern fn __dbg_ctx__spaCallbackNoop(_: ?*c.spa_debug_context, _: [*c]const u8, ...) callconv(.c) void;
export fn __nova___dbg_ctx__spaCallbackReal(
    ctx: ?*c.spa_debug_context,
    msg: [*:0]const u8,
    len: c_int,
) callconv(.c) void {
    const data: *const DebugContextData = @fieldParentPtr("spa", ctx.?);
    data.zigLog(msg[0..@intCast(len)]);
}

pub fn dbgCtx(
    comptime ctx_level: std.log.Level,
    comptime ctx_scope: @TypeOf(.enum_literal),
) *c.spa_debug_context {
    const Intern = struct {
        fn zigLog(msg: []const u8) void {
            std.options.logFn(ctx_level, ctx_scope, "{s}", .{msg});
        }

        var instance: DebugContextData = .{
            .spa = .{
                .log = if (std.log.logEnabled(ctx_level, ctx_scope))
                    &__dbg_ctx__spaCallbackReal
                else
                    &__dbg_ctx__spaCallbackNoop,
            },
            .level = ctx_level,
            .zigLog = &zigLog,
        };
    };
    return &Intern.instance.spa;
}

fn pwLevelToZig(pw_level: c.spa_log_level) ?std.log.Level {
    return switch (pw_level) {
        c.SPA_LOG_LEVEL_NONE => return null,
        c.SPA_LOG_LEVEL_ERROR => .err,
        c.SPA_LOG_LEVEL_WARN => .warn,
        c.SPA_LOG_LEVEL_INFO => .info,
        c.SPA_LOG_LEVEL_DEBUG, c.SPA_LOG_LEVEL_TRACE => .debug,
        else => .err,
    };
}

export fn __logger__enabled(pw_level: c.spa_log_level) bool {
    const level = pwLevelToZig(pw_level) orelse return false;
    switch (level) {
        inline else => |l| return std.log.logEnabled(l, scope),
    }
}

export fn __nova__logger__logtv(
    object: ?*anyopaque,
    pw_level: c.spa_log_level,
    topic: ?*const c.spa_log_topic,
    file_abs_c: [*c]const u8,
    line: c_int,
    func: [*c]const u8,
    msg: [*c]const u8,
    len: c_int,
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
    const level = pwLevelToZig(pw_level) orelse return;

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
            std.options.logFn(l, scope, "{s}:{}: {s}", .{
                file,
                line,
                msg[0..@intCast(len)],
            });
        },
    }
}

// Don't optimize out exports
comptime {
    _ = &__nova___dbg_ctx__spaCallbackReal;
    _ = &__nova__logger__logtv;
    _ = &__logger__enabled;
}
