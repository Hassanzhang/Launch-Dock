#include "ProcessSupport.h"
#include <spawn.h>
#include <signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

int ld_spawn(const char *directory, const char *command, char *const environment[], pid_t *pid, int *output) {
    int pipes[2];
    if (pipe(pipes) != 0) return errno;
    fcntl(pipes[0], F_SETFD, FD_CLOEXEC);
    fcntl(pipes[1], F_SETFD, FD_CLOEXEC);
    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attr;
    int error = posix_spawn_file_actions_init(&actions);
    if (error) goto close_pipes;
    error = posix_spawnattr_init(&attr);
    if (error) goto destroy_actions;
#define CHECK(call) if ((error = (call))) goto cleanup
    CHECK(posix_spawn_file_actions_addchdir_np(&actions, directory));
    CHECK(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0));
    CHECK(posix_spawn_file_actions_adddup2(&actions, pipes[1], STDOUT_FILENO));
    CHECK(posix_spawn_file_actions_adddup2(&actions, pipes[1], STDERR_FILENO));
    CHECK(posix_spawn_file_actions_addclose(&actions, pipes[0]));
    CHECK(posix_spawn_file_actions_addclose(&actions, pipes[1]));
    sigset_t defaults, mask;
    sigemptyset(&mask);
    sigemptyset(&defaults);
    sigaddset(&defaults, SIGINT); sigaddset(&defaults, SIGTERM);
    sigaddset(&defaults, SIGQUIT); sigaddset(&defaults, SIGPIPE);
    CHECK(posix_spawnattr_setsigdefault(&attr, &defaults));
    CHECK(posix_spawnattr_setsigmask(&attr, &mask));
    CHECK(posix_spawnattr_setpgroup(&attr, 0));
    CHECK(posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT));
    char *argv[] = {"/bin/zsh", "-f", "-c", (char *)command, NULL};
    CHECK(posix_spawn(pid, "/bin/zsh", &actions, &attr, argv, environment));
    close(pipes[1]);
    fcntl(pipes[0], F_SETFL, fcntl(pipes[0], F_GETFL) | O_NONBLOCK);
    *output = pipes[0];
    posix_spawnattr_destroy(&attr);
    posix_spawn_file_actions_destroy(&actions);
    return 0;
cleanup:
    posix_spawnattr_destroy(&attr);
destroy_actions:
    posix_spawn_file_actions_destroy(&actions);
close_pipes:
    close(pipes[0]); close(pipes[1]);
    return error;
}
