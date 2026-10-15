#ifndef PROCESS_SUPPORT_H
#define PROCESS_SUPPORT_H
#include <sys/types.h>
// Returns a POSIX error code, with a nonblocking merged output pipe on success.
int ld_spawn(const char *directory, const char *command, char *const environment[], pid_t *pid, int *output);
#endif
