#include <stdint.h>
#include <string.h>
#include <dlfcn.h>
#include <sys/stat.h>
#include <spa/support/log.h>

// Do this from C to workaround `stat` translating to an opaque type for musl, likely due to the
// bitpacking syntax used on timespec.
void __wrap_fstat_found(struct stat * stat, uint64_t len) {
	memset(stat, 0, sizeof(struct stat));
	(*stat).st_mode = S_IFREG;
	(*stat).st_uid = 0xFFFFFFFF;
	(*stat).st_gid = 0xFFFFFFFF;
	(*stat).st_size = len;
}

// See `__wrap_fstat_found`.
void __wrap_stat_found(struct stat * stat) {
	memset(stat, 0, sizeof(struct stat));
	(*stat).st_mode = S_IFREG;
}
