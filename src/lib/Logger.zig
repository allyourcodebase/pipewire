//! A logger that forwards pipewire logs to `std.log.`

const std = @import("std");
const c = @import("root.zig").c;

pub const default_level = switch (std.options.log_level) {
    .err => c.SPA_LOG_LEVEL_ERROR,
    .warn => c.SPA_LOG_LEVEL_WARN,
    .info => c.SPA_LOG_LEVEL_INFO,
    .debug => c.SPA_LOG_LEVEL_TRACE,
};
pub const scope = .pw;

/// We store this as a singleton to simplify initialization. There's no reason to have more
/// than one, but we can't quite just store it as a global since it's currently referencing
/// externs in `va.c` that can't be resolved at comptime when using LLVM.
var instance: c.spa_log = .{
    .iface = .{
        .type = c.SPA_TYPE_INTERFACE_Log,
        .version = c.SPA_VERSION_LOG,
        .cb = .{
            // Initialized by `get` since this value is an extern pointer, which means it's
            // not copmtime known (unless we're on the x64 backend.)
            .funcs = null,
            // Appears to be unused. Likely intended as userdata.
            .data = null,
        },
    },
    .level = default_level,
};

/// Initializes the logger.
pub fn init() void {
    c.pw_log_set(get());
    c.pw_log_set_level(default_level);
}

/// Gets the logger instance.
pub fn get() *c.spa_log {
    if (instance.iface.cb.funcs == null) instance.iface.cb.funcs = va.__log_funcs;
    return &instance;
}

const DbgCtx = struct {
    spa: c.spa_debug_context,
    level: std.log.Level,
    log: *const fn (msg: []const u8) void,

    /// Converts a PipeWire log level to a Zig log level, or returns `null` if there's no
    /// equivalent.
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

    /// Called by `va.c`.
    export fn __nova_debugc_format(
        ctx: ?*c.spa_debug_context,
        msg: [*:0]const u8,
        len: c_int,
    ) callconv(.c) void {
        const data: *const DbgCtx = @fieldParentPtr("spa", ctx.?);
        data.log(msg[0..@intCast(len)]);
    }

    /// Returns true if the given log level is enabled.
    export fn __log_enabled(pw_level: c.spa_log_level) bool {
        const level = pwLevelToZig(pw_level) orelse return false;
        switch (level) {
            inline else => |l| return std.log.logEnabled(l, scope),
        }
    }

    export fn __nova_logtv(
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
};

pub fn dbgCtx(
    comptime ctx_level: std.log.Level,
    comptime ctx_scope: @TypeOf(.enum_literal),
) *c.spa_debug_context {
    const Intern = struct {
        /// Log the message to Zig's logger.
        fn log(msg: []const u8) void {
            std.options.logFn(ctx_level, ctx_scope, "{s}", .{msg});
        }

        /// Ignore the message.
        fn ignore(
            _: ?*c.spa_debug_context,
            _: [*c]const u8,
            ...,
        ) callconv(.c) void {}

        /// An instance of the logger with the comptime set config.
        var instance: DbgCtx = .{
            .spa = .{
                .log = if (std.log.logEnabled(ctx_level, ctx_scope))
                    &va.__debugc_format
                else
                    &ignore,
            },
            .level = ctx_level,
            .log = &log,
        };
    };
    return &Intern.instance.spa;
}

/// From `va.c`.
const va = struct {
    extern const __log_funcs: ?*anyopaque;
    extern fn __debugc_format(?*c.spa_debug_context, [*c]const u8, ...) callconv(.c) void;
};

// Don't optimize out exports
comptime {
    _ = &DbgCtx.__nova_debugc_format;
    _ = &DbgCtx.__nova_logtv;
    _ = &DbgCtx.__log_enabled;
}
