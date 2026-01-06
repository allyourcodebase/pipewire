// Zig doesn't currently implement varargs on aargch64-linux, so we've moved all vararg code into
// C. Once this is resolved, we can move this code back into Zig:
//
// * https://github.com/ziglang/zig/issues/15389

#include <stdarg.h>
#include <spa/support/log.h>

// Shims for debug contexts.
extern void __nova_debugc_format(
    struct spa_debug_context * ctx,
    const char * msg,
    int len
);

void __debugc_format(struct spa_debug_context * ctx, const char * fmt, ...) {

    const char * msg = "(formatted failed)";
    int msg_len = strlen(msg);

	va_list args;
	va_start(args, fmt);

    const int buf_len = 1024;
    char buf[buf_len];
    int print_len = spa_vscnprintf(&buf[0], buf_len, fmt, args);
    if (print_len >= 0 && print_len < buf_len) {
	    msg = &buf[0];
	    msg_len = print_len;
	}

    va_end(args);

    __nova_debugc_format(ctx, msg, msg_len);

}

// Shims for logging.
extern bool __log_enabled(enum spa_log_level level);

extern void __nova_logtv(
	void * object,
	enum spa_log_level level,
	const struct spa_log_topic * topic,
	const char * file_abs,
	int line,
	const char * func,
	const char * msg,
	int len
);

static void logtv(
    void * object,
    enum spa_log_level level,
    const struct spa_log_topic * topic,
    const char * file_abs,
    int line,
    const char * func,
    const char * fmt,
    va_list args
) {
	if (!__log_enabled(level)) return;

	const char * msg = "(formatted failed)";
	int msg_len = strlen(msg);

    const int buf_len = 1024;
    char buf[buf_len];
    int print_len = spa_vscnprintf(&buf[0], buf_len, fmt, args);
    if (print_len >= 0 && print_len < buf_len) {
	    msg = &buf[0];
	    msg_len = print_len;
	}

    __nova_logtv(object, level, topic, file_abs, line, func, msg, msg_len);
}

static void log(
    void * object,
    enum spa_log_level level,
    const char * file_abs,
    int line,
    const char *func,
    const char * fmt,
    ...
) {
	va_list args;
	va_start(args, fmt);
    logtv(object, level, NULL, file_abs, line, func, fmt, args);
    va_end(args);
}

static void logv(
    void * object,
    enum spa_log_level level,
    const char * file_abs,
    int line,
    const char * func,
    const char * fmt,
    va_list args
) {
    logtv(object, level, NULL, file_abs, line, func, fmt, args);
}

static void logt(
    void * object,
    enum spa_log_level level,
    const struct spa_log_topic * topic,
    const char * file_abs,
    int line,
    const char * func,
    const char * fmt,
    ...
) {
    va_list args;
	va_start(args, fmt);
    logtv(object, level, topic, file_abs, line, func, fmt, args);
    va_end(args);
}

static void topic_init(void * object, struct spa_log_topic *topic) {
    // Noop in default implementation as well
}

static struct spa_log_methods __log_funcs_real = {
    .version = SPA_VERSION_LOG_METHODS,
    .log = &log,
    .logt = &logt,
    .logv = &logv,
    .logtv = &logtv,
    .topic_init = &topic_init,
};

void * __log_funcs = &__log_funcs_real;
