/* Minimal PTY proxy packaged as a native library for the Android editor.
 *
 * Android's Java API has no openpty(), but a native process may allocate one.
 * This helper creates the terminal on the Android side, runs the supplied
 * command (PRoot + OpenCode) on the controlling end, and relays:
 *   - stdin  (pipe)  -> terminal input
 *   - stdout (pipe)  <- terminal output
 *   - a control FIFO <- "R <cols> <rows>" resize and "Q" graceful quit lines
 *
 * It is intentionally dependency-free, so the editor can ship it as
 * libai_pty.so and execute it from nativeLibraryDir on Android 10+.
 *
 * Usage: ai_pty <cols> <rows> <control-fifo> -- <program> [args...]
 */
#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

#define INPUT_CAPACITY 16384
#define CONTROL_CAPACITY 2048

static volatile sig_atomic_t stop_requested = 0;
static pid_t child_pid = -1;
static int master_fd = -1;

static void on_stop_signal(int signal_number) {
    (void)signal_number;
    stop_requested = 1;
}

static void on_child_signal(int signal_number) {
    (void)signal_number;
}

static void ignore_signal(int signal_number) {
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_handler = SIG_IGN;
    sigemptyset(&action.sa_mask);
    sigaction(signal_number, &action, NULL);
}

static void install_handler(int signal_number, void (*handler)(int)) {
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_handler = handler;
    sigemptyset(&action.sa_mask);
    action.sa_flags = 0; /* no SA_RESTART: poll() must wake up */
    sigaction(signal_number, &action, NULL);
}

static int write_all(int fd, const unsigned char *data, size_t size) {
    size_t offset = 0;
    while (offset < size) {
        ssize_t written = write(fd, data + offset, size - offset);
        if (written < 0) {
            if (errno == EINTR) {
                continue;
            }
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                struct pollfd wait = {fd, POLLOUT, 0};
                if (poll(&wait, 1, 1000) > 0) {
                    continue;
                }
            }
            return -1;
        }
        offset += (size_t)written;
    }
    return 0;
}

/* Write as much pending terminal input as the nonblocking master accepts. */
static size_t flush_input(int fd, const unsigned char *data, size_t offset, size_t length) {
    while (offset < length) {
        ssize_t written = write(fd, data + offset, length - offset);
        if (written > 0) {
            offset += (size_t)written;
            continue;
        }
        if (written < 0 && errno == EINTR) {
            continue;
        }
        break;
    }
    return offset;
}

static int set_window_size(int fd, int columns, int rows) {
    struct winsize size;
    memset(&size, 0, sizeof(size));
    size.ws_col = (unsigned short)(columns > 0 ? columns : 80);
    size.ws_row = (unsigned short)(rows > 0 ? rows : 24);
    if (ioctl(fd, TIOCSWINSZ, &size) != 0) {
        return -1;
    }
    if (child_pid > 0) {
        kill(-child_pid, SIGWINCH);
        kill(child_pid, SIGWINCH);
    }
    return 0;
}

static void terminate_child(int signal_number, int grace_ms) {
    if (child_pid <= 0) {
        return;
    }
    kill(-child_pid, signal_number);
    kill(child_pid, signal_number);
    for (int waited = 0; waited < grace_ms; waited += 50) {
        int status = 0;
        if (waitpid(child_pid, &status, WNOHANG) == child_pid) {
            child_pid = -1;
            return;
        }
        struct timespec pause = {0, 50 * 1000 * 1000};
        nanosleep(&pause, NULL);
    }
    kill(-child_pid, SIGKILL);
    kill(child_pid, SIGKILL);
}

/* Returns nonzero when the child was reaped (status stored in *out_status). */
static int poll_child(int *out_status) {
    if (child_pid <= 0) {
        return 0;
    }
    int status = 0;
    pid_t result = waitpid(child_pid, &status, WNOHANG);
    if (result == child_pid) {
        *out_status = status;
        child_pid = -1;
        return 1;
    }
    return 0;
}

/* Keep reading the terminal after the child exits so the final screen is not lost. */
static void drain_master(void) {
    unsigned char buffer[4096];
    for (int attempt = 0; attempt < 20; attempt++) {
        ssize_t count = read(master_fd, buffer, sizeof(buffer));
        if (count > 0) {
            if (write_all(STDOUT_FILENO, buffer, (size_t)count) != 0) {
                return;
            }
            continue;
        }
        if (count < 0 && errno == EINTR) {
            continue;
        }
        if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            struct pollfd wait = {master_fd, POLLIN, 0};
            if (poll(&wait, 1, 50) > 0) {
                continue;
            }
        }
        break;
    }
}

int main(int argc, char **argv) {
    if (argc < 6 || strcmp(argv[4], "--") != 0) {
        fprintf(stderr, "usage: ai_pty <cols> <rows> <control-fifo> -- <program> [args...]\n");
        return 2;
    }
    int columns = atoi(argv[1]);
    int rows = atoi(argv[2]);
    const char *control_path = argv[3];
    char **command = &argv[5];

    if (columns <= 0 || columns > 1000 || rows <= 0 || rows > 1000) {
        fprintf(stderr, "ai_pty: invalid terminal size\n");
        return 2;
    }

    ignore_signal(SIGPIPE);
    install_handler(SIGTERM, on_stop_signal);
    install_handler(SIGINT, on_stop_signal);
    install_handler(SIGHUP, on_stop_signal);
    install_handler(SIGCHLD, on_child_signal);

    master_fd = posix_openpt(O_RDWR | O_NOCTTY);
    if (master_fd < 0 || grantpt(master_fd) != 0 || unlockpt(master_fd) != 0) {
        fprintf(stderr, "ai_pty: cannot allocate pty: %s\n", strerror(errno));
        return 3;
    }
    const char *slave_name = ptsname(master_fd);
    if (slave_name == NULL) {
        fprintf(stderr, "ai_pty: ptsname failed: %s\n", strerror(errno));
        return 3;
    }
    set_window_size(master_fd, columns, rows);

    child_pid = fork();
    if (child_pid < 0) {
        fprintf(stderr, "ai_pty: fork failed: %s\n", strerror(errno));
        return 4;
    }
    if (child_pid == 0) {
        setsid();
        int slave = open(slave_name, O_RDWR);
        if (slave < 0) {
            _exit(126);
        }
        ioctl(slave, TIOCSCTTY, 0);
        dup2(slave, STDIN_FILENO);
        dup2(slave, STDOUT_FILENO);
        dup2(slave, STDERR_FILENO);
        if (slave > STDERR_FILENO) {
            close(slave);
        }
        close(master_fd);
        setenv("TERM", "xterm-256color", 1);
        setenv("COLORTERM", "truecolor", 1);
        execvp(command[0], command);
        _exit(127);
    }

    /* The helper's own stdin is the input pipe; move it aside so fd 0 can be
     * replaced with /dev/null for anything spawned through this terminal. */
    int input_fd = dup(STDIN_FILENO);
    int null_fd = open("/dev/null", O_RDONLY);
    if (null_fd >= 0) {
        dup2(null_fd, STDIN_FILENO);
        if (null_fd > STDERR_FILENO) {
            close(null_fd);
        }
    }

    int control_fd = open(control_path, O_RDWR | O_NONBLOCK);
    if (control_fd < 0) {
        fprintf(stderr, "ai_pty: cannot open control fifo: %s\n", strerror(errno));
        terminate_child(SIGKILL, 0);
        return 5;
    }

    int flags = fcntl(master_fd, F_GETFL, 0);
    fcntl(master_fd, F_SETFL, flags | O_NONBLOCK);

    unsigned char input[INPUT_CAPACITY];
    size_t input_offset = 0;
    size_t input_length = 0;
    char control[CONTROL_CAPACITY];
    size_t control_length = 0;
    int exit_status = 0;
    int child_finished = 0;

    while (!child_finished) {
        struct pollfd descriptors[4];
        int count = 0;
        descriptors[count].fd = master_fd;
        descriptors[count].events = POLLIN;
        descriptors[count].revents = 0;
        count++;
        descriptors[count].fd = input_fd;
        descriptors[count].events = POLLIN;
        descriptors[count].revents = 0;
        count++;
        descriptors[count].fd = control_fd;
        descriptors[count].events = POLLIN;
        descriptors[count].revents = 0;
        count++;
        if (input_length > input_offset) {
            descriptors[count].fd = master_fd;
            descriptors[count].events = POLLOUT;
            descriptors[count].revents = 0;
            count++;
        }

        if (stop_requested) {
            break;
        }
        int ready = poll(descriptors, (nfds_t)count, 250);
        if (ready < 0 && errno != EINTR) {
            break;
        }

        if (poll_child(&exit_status)) {
            child_finished = 1;
            break;
        }

        if (ready > 0) {
            if (descriptors[0].revents & (POLLIN | POLLHUP | POLLERR)) {
                unsigned char output[8192];
                ssize_t size = read(master_fd, output, sizeof(output));
                if (size > 0) {
                    if (write_all(STDOUT_FILENO, output, (size_t)size) != 0) {
                        break;
                    }
                } else if (size == 0 || (size < 0 && errno != EAGAIN && errno != EINTR)) {
                    child_finished = 1;
                    break;
                }
            }
            if (input_fd >= 0 && (descriptors[1].revents & (POLLIN | POLLHUP | POLLERR))) {
                if (input_length == input_offset) {
                    input_offset = 0;
                    input_length = 0;
                }
                if (input_length == input_offset) {
                    ssize_t size = read(input_fd, input, sizeof(input));
                    if (size > 0) {
                        input_offset = 0;
                        input_length = (size_t)size;
                    } else if (size == 0 || (size < 0 && errno != EAGAIN && errno != EINTR)) {
                        input_fd = -1;
                    }
                }
                /* Keystrokes must reach the terminal immediately, not on the
                 * next poll timeout. */
                if (input_length > input_offset) {
                    input_offset = flush_input(master_fd, input, input_offset, input_length);
                }
            }
            if (descriptors[2].revents & POLLIN) {
                if (control_length < sizeof(control) - 1) {
                    ssize_t size = read(control_fd, control + control_length, sizeof(control) - 1 - control_length);
                    if (size > 0) {
                        control_length += (size_t)size;
                        control[control_length] = '\0';
                        char *line_start = control;
                        char *newline = strchr(control, '\n');
                        while (newline != NULL) {
                            *newline = '\0';
                            int width = 0;
                            int height = 0;
                            if (sscanf(line_start, "R %d %d", &width, &height) == 2 &&
                                    width > 0 && width <= 1000 && height > 0 && height <= 1000) {
                                set_window_size(master_fd, width, height);
                            } else if (line_start[0] == 'Q') {
                                stop_requested = 1;
                            }
                            line_start = newline + 1;
                            newline = strchr(line_start, '\n');
                        }
                        control_length = strlen(line_start);
                        memmove(control, line_start, control_length);
                    }
                } else {
                    /* Discard malformed control data instead of growing forever. */
                    control_length = 0;
                    char discard[256];
                    while (read(control_fd, discard, sizeof(discard)) > 0) {
                    }
                }
            }
            if (count > 3 && (descriptors[3].revents & POLLOUT) && input_length > input_offset) {
                input_offset = flush_input(master_fd, input, input_offset, input_length);
            }
        }
    }

    if (child_pid > 0) {
        /* The master can report EOF a few milliseconds before SIGCHLD is
         * delivered; give the real child status a short chance. */
        for (int attempt = 0; attempt < 40; attempt++) {
            if (poll_child(&exit_status)) {
                break;
            }
            struct timespec pause = {0, 50 * 1000 * 1000};
            nanosleep(&pause, NULL);
        }
    }
    if (child_pid > 0) {
        terminate_child(SIGTERM, 2000);
    }
    drain_master();
    if (input_fd >= 0) {
        close(input_fd);
    }
    close(control_fd);
    close(master_fd);
    if (WIFEXITED(exit_status)) {
        return WEXITSTATUS(exit_status);
    }
    if (WIFSIGNALED(exit_status)) {
        return 128 + WTERMSIG(exit_status);
    }
    return 0;
}
