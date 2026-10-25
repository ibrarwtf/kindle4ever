// k4keys - read the Kindle 4 NT buttons straight from evdev.
//
// Prints one line per key event: "<name> <down|up|repeat> <dev>:<code> <ms>"
// Usage: k4keys [-1] [-g] [-t SECONDS]
//   -1   exit after the first key press (prints just that key's name), for scripts
//   -g   grab the devices (EVIOCGRAB) so the framework doesn't see the keys while we run
//   -t   give up after SECONDS (exit 1)
// The power button is not an input device on the K4 (it goes through the PMIC/powerd).

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

#ifndef K4_VERSION
#define K4_VERSION "dev"  // set by tools/build.sh from git describe
#endif

// The kernel (2.6.31, 32-bit) writes 16-byte events with a 32-bit timeval. musl's time64
// struct timeval is 16 bytes on its own, so linux/input.h's struct input_event would not
// match - use our own layout.
struct kevent {
    uint32_t sec, usec;
    uint16_t type, code;
    int32_t value;
};

#define EV_KEY 1
#define EVIOCGRAB _IOW('E', 0x90, int)

static const struct { int dev, code; const char *name; } keys[] = {
    {0, 102, "home"}, {0, 139, "menu"}, {0, 158, "back"}, {0, 29, "kbd"},
    {0, 104, "lnext"}, {0, 193, "lprev"}, {0, 191, "rnext"}, {0, 109, "rprev"},  // page keys by side
    {1, 103, "up"}, {1, 108, "down"}, {1, 105, "left"}, {1, 106, "right"}, {1, 194, "select"},
};

static const char USAGE[] =
"usage: k4keys [-1] [-g] [-t SECONDS]\n"
"       k4keys --help | --version\n"
"\n"
"Read the Kindle 4 NT buttons from evdev (/dev/input/event0-2).\n"
"\n"
"Output, one line per key event:  NAME down|up|repeat DEV:CODE MS\n"
"  e.g. 'rnext down 0:191 1234'  (MS = milliseconds since start; NAME 'unknown' for other codes)\n"
"Names: home menu back kbd lprev lnext rprev rnext up down left right select\n"
"\n"
"Options:\n"
"  -1          wait for one key press, print just its name, exit 0\n"
"  -g          grab the devices so Amazon's UI doesn't see the keys while k4keys runs\n"
"  -t SECONDS  give up after SECONDS (exit 1)\n"
"\n"
"The power button is not an input device on the K4 (it goes to powerd).\n"
"Exit codes: 0 ok, 1 timeout or error, 2 usage.\n";

static const char *key_name(int dev, int code) {
    for (unsigned i = 0; i < sizeof keys / sizeof keys[0]; i++)
        if (keys[i].dev == dev && keys[i].code == code) return keys[i].name;
    return "unknown";
}

static double now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

int main(int argc, char **argv) {
    if (argc > 1 && !strcmp(argv[1], "--version")) { printf("%s %s\n", "k4keys", K4_VERSION); return 0; }
    if (argc > 1 && (!strcmp(argv[1], "--help") || !strcmp(argv[1], "-h"))) { fputs(USAGE, stdout); return 0; }
    int once = 0, grab = 0, timeout_s = -1;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-1")) once = 1;
        else if (!strcmp(argv[i], "-g")) grab = 1;
        else if (!strcmp(argv[i], "-t") && i + 1 < argc) timeout_s = atoi(argv[++i]);
        else { fputs(USAGE, stderr); return 2; }
    }

    struct pollfd pfd[3];
    int ndev = 0;
    for (int d = 0; d < 3; d++) {
        char path[32];
        snprintf(path, sizeof path, "/dev/input/event%d", d);
        int fd = open(path, O_RDONLY);
        if (fd < 0) { fprintf(stderr, "k4keys: %s: %s\n", path, strerror(errno)); continue; }
        if (grab && ioctl(fd, EVIOCGRAB, 1)) fprintf(stderr, "k4keys: grab %s: %s\n", path, strerror(errno));
        pfd[ndev].fd = fd;
        pfd[ndev].events = POLLIN;
        ndev++;
    }
    if (!ndev) return 1;
    setvbuf(stdout, NULL, _IOLBF, 0);

    double start = now_ms();
    for (;;) {
        int wait = -1;
        if (timeout_s >= 0) {
            wait = (int)(timeout_s * 1000 - (now_ms() - start));
            if (wait <= 0) return 1;
        }
        int r = poll(pfd, ndev, wait);
        if (r < 0) { if (errno == EINTR) continue; perror("k4keys: poll"); return 1; }
        if (r == 0) return 1;
        for (int i = 0; i < ndev; i++) {
            if (!(pfd[i].revents & POLLIN)) continue;
            struct kevent ev[16];
            ssize_t n = read(pfd[i].fd, ev, sizeof ev);
            for (int j = 0; j < (int)(n / (ssize_t)sizeof ev[0]); j++) {
                if (ev[j].type != EV_KEY) continue;  // skip EV_SYN and EV_MSC scancodes
                // dev index = event number (devices opened in order)
                char path[32];
                snprintf(path, sizeof path, "/proc/self/fd/%d", pfd[i].fd);
                char link[64] = "";
                ssize_t l = readlink(path, link, sizeof link - 1);
                int dev = l > 0 ? link[l - 1] - '0' : i;
                const char *name = key_name(dev, ev[j].code);
                if (once) {
                    if (ev[j].value == 1) { printf("%s\n", name); return 0; }
                    continue;
                }
                printf("%s %s %d:%d %.0f\n", name, ev[j].value == 1 ? "down" : ev[j].value == 0 ? "up" : "repeat",
                       dev, ev[j].code, now_ms() - start);
            }
        }
    }
}
