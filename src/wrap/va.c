// Zig doesn't currently implement varargs on aargch64-linux, so we've moved all vararg code into
// this file. Once this is resolved, we can move this code back into Zig:
//
// * https://github.com/ziglang/zig/issues/15389

#include <fcntl.h>
#include <stdarg.h>
#include <spa/utils/string.h>
#include <spa/debug/context.h>
#include <spa/support/log.h>

int __nova__wrap_open(const char * path, int flags, mode_t mode);

int __wrap_open(const char * path, int flags, ...) {
	mode_t mode = 0;

	if ((flags & O_CREAT) || (flags & O_TMPFILE)) {
		va_list args;
		va_start(args, flags);
		mode = va_arg(args, mode_t);
		va_end(args);
	}

	return __nova__wrap_open(path, flags, mode);
}


void __nova___dbg_ctx__spaCallbackReal(
    struct spa_debug_context * ctx,
    const char * msg,
    int len
);

void __dbg_ctx__spaCallbackReal(struct spa_debug_context * ctx, const char * fmt, ...) {

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

    __nova___dbg_ctx__spaCallbackReal(ctx, msg, msg_len);

}

void __dbg_ctx__spaCallbackNoop(struct spa_debug_context * ctx, const char * fmt, ...) {}

void __nova__logger__logtv(
	void * object,
	enum spa_log_level level,
	const struct spa_log_topic * topic,
	const char * file_abs,
	int line,
	const char * func,
	const char * msg,
	int len
);

bool __logger__enabled(enum spa_log_level level);

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
	if (!__logger__enabled(level)) return;

	const char * msg = "(formatted failed)";
	int msg_len = strlen(msg);

    const int buf_len = 1024;
    char buf[buf_len];
    int print_len = spa_vscnprintf(&buf[0], buf_len, fmt, args);
    if (print_len >= 0 && print_len < buf_len) {
	    msg = &buf[0];
	    msg_len = print_len;
	}

    __nova__logger__logtv(object, level, topic, file_abs, line, func, msg, msg_len);
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

static void topicInit(void * object, struct spa_log_topic *topic) {
    // Noop in default implementation as well
}

static struct spa_log_methods __logger_methods_v = {
    .version = SPA_VERSION_LOG_METHODS,
    .log = &log,
    .logt = &logt,
    .logv = &logv,
    .logtv = &logtv,
    .topic_init = &topicInit,
};

void * __logger_methods = &__logger_methods_v;
