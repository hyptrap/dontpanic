#if !defined(COMPILING) && !defined(__clang__)
set -xeu
aarch64-suse-linux-gcc -O2 -Werror -Wall -g -shared -fPIC -DCOMPILING $0 -o libwv.so
sha256sum libwv.so
exit $?
#endif

#define _GNU_SOURCE

#include <linux/limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <unistd.h>
#include <fcntl.h>
#include <assert.h>
#include <string.h>
#include <stdarg.h>
#include <stdbool.h>

static typeof(fopen) *fopen64_p = NULL;
static typeof(fwrite) *fwrite_p = NULL;

// TODO: Lists of file to be verified
static FILE *write_handle = NULL;
static const char *write_path = NULL;

// compatibility
__asm__(".symver dlsym,dlsym@GLIBC_2.17");
static void __attribute__((constructor)) __init() {
    // hook libc's function instead of underlaying POSIX, the openssl only uses these
    // TODO: hook the open/write instead?
    fopen64_p = dlsym(RTLD_NEXT, "fopen64");
    assert(fopen64_p);

    fwrite_p = dlsym(RTLD_NEXT, "fwrite");
    assert(fwrite_p);

    // TODO: use abspath
    write_path = getenv("WRV_READ_PATH");
    fprintf(stderr, "write_verify: fopen64_p=%p, fwrite_p=%p, write_path=%s\n",
            fopen64_p, fwrite_p, write_path);
}

FILE *fopen64(const char *filename, const char *mode) {
    FILE *ret;
    bool matched = false;

    if (!write_handle && write_path && strncmp(filename, write_path, PATH_MAX) == 0) {
        // make read-only for the target, we won't write actually, just verify
        mode = "r";
        matched = true;
    }
    
    ret = fopen64_p(filename, mode);
    if (ret >= 0 && matched)
        write_handle = ret;

    return ret;
}

// copyright: https://gist.github.com/ccbrown/9722406
static void DumpHex(const void* data, size_t size) {
	char ascii[17];
	size_t i, j;
	ascii[16] = '\0';
	for (i = 0; i < size; ++i) {
		printf("%02X ", ((unsigned char*)data)[i]);
		if (((unsigned char*)data)[i] >= ' ' && ((unsigned char*)data)[i] <= '~') {
			ascii[i % 16] = ((unsigned char*)data)[i];
		} else {
			ascii[i % 16] = '.';
		}
		if ((i+1) % 8 == 0 || i+1 == size) {
			printf(" ");
			if ((i+1) % 16 == 0) {
				printf("|  %s \n", ascii);
			} else if (i+1 == size) {
				ascii[(i+1) % 16] = '\0';
				if ((i+1) % 16 <= 8) {
					printf(" ");
				}
				for (j = (i+1) % 16; j < 16; ++j) {
					printf("   ");
				}
				printf("|  %s \n", ascii);
			}
		}
	}
}

size_t fwrite(const void *buffer, size_t size, size_t count, FILE *stream) {
    void *expected;
    size_t readed;
    size_t len;

    if (stream != write_handle)
        return fwrite_p(buffer, size, count, stream);

    // TODO: avoid malloc, and skip when malloc failed?
    len = size * count;
    expected = malloc(len);
    assert(expected);

    // Try to verify, and panic earlier!
    readed = fread(expected, size, count, stream);
    if (readed != count || memcmp(buffer, expected, len) != 0) {
        fprintf(stderr, "inconsistent: size=%ld, count=%ld, read=%ld, tell=%ld\n",
                size, count, readed, ftell(stream));
        fprintf(stderr, "  ----- buffer -----\n");
        DumpHex(buffer, len);
        fprintf(stderr, "  ----- expect -----\n");
        DumpHex(expected, len);
        abort();
    }

    free(expected);
    return count;
}
