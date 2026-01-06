// Zig doesn't currently implement varargs on aargch64-linux, so we've moved all vararg code into
// C. Once this is resolved, we can move this code back into Zig:
//
// * https://github.com/ziglang/zig/issues/15389

#include <stdarg.h>
#include <fcntl.h>

// Shims for filesystem access.
extern int __nova_wrap_open(const char * path, int flags, mode_t mode);

int __wrap_open(const char * path, int flags, ...) {
	mode_t mode = 0;

	if ((flags & O_CREAT) || (flags & O_TMPFILE)) {
		va_list args;
		va_start(args, flags);
		mode = va_arg(args, mode_t);
		va_end(args);
	}

	return __nova_wrap_open(path, flags, mode);
}
