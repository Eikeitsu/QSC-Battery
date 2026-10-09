/*
 * 音量键（安装 customize + Action）：EVIOCGRAB 独占后再读，避免弹出音量条。
 * getevent 只旁路观察，事件仍进 AudioService；SukiSU 管理器常自吞键，BakaSU 等不会。
 * 产物进 module/bin/，运行期保留供 Action 使用。
 *
 * 用法: volkey [超时秒数]   默认 20
 * 退出: 0=音量上  1=音量下  2=超时/不可用
 */

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#ifndef EVIOCGRAB
#define EVIOCGRAB _IOW('E', 0x90, int)
#endif

#define MAX_DEVS 16
#define EXIT_UP 0
#define EXIT_DOWN 1
#define EXIT_TIMEOUT 2

static int test_bit(int bit, const unsigned char *mask) {
  return (mask[bit / 8] >> (bit % 8)) & 1;
}

static int open_volume_devs(int *fds, int max) {
  DIR *dir = opendir("/dev/input");
  int n = 0;
  struct dirent *ent;

  if (!dir) {
    return 0;
  }
  while ((ent = readdir(dir)) != NULL && n < max) {
    char path[64];
    unsigned char keybits[(KEY_MAX + 7) / 8];
    int fd;

    if (strncmp(ent->d_name, "event", 5) != 0) {
      continue;
    }
    if (snprintf(path, sizeof(path), "/dev/input/%s", ent->d_name) >= (int)sizeof(path)) {
      continue;
    }
    fd = open(path, O_RDONLY | O_CLOEXEC | O_NONBLOCK);
    if (fd < 0) {
      continue;
    }
    memset(keybits, 0, sizeof(keybits));
    if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(keybits)), keybits) < 0) {
      close(fd);
      continue;
    }
    if (!test_bit(KEY_VOLUMEUP, keybits) && !test_bit(KEY_VOLUMEDOWN, keybits)) {
      close(fd);
      continue;
    }
    if (ioctl(fd, EVIOCGRAB, 1) != 0) {
      /* 抢不到就仍监视：比完全失败好；HUD 可能仍会出现 */
    }
    fds[n++] = fd;
  }
  closedir(dir);
  return n;
}

static void release_all(int *fds, int n) {
  for (int i = 0; i < n; i++) {
    if (fds[i] >= 0) {
      ioctl(fds[i], EVIOCGRAB, 0);
      close(fds[i]);
      fds[i] = -1;
    }
  }
}

static int drain_pending(int *fds, int n) {
  struct input_event ev;
  for (int i = 0; i < n; i++) {
    for (;;) {
      ssize_t r = read(fds[i], &ev, sizeof(ev));
      if (r < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
          break;
        }
        break;
      }
      if (r != (ssize_t)sizeof(ev)) {
        break;
      }
    }
  }
  return 0;
}

static unsigned parse_timeout(const char *arg) {
  unsigned long v = 0;
  if (arg == NULL || *arg == '\0') {
    return 20u;
  }
  for (const char *p = arg; *p; p++) {
    if (*p < '0' || *p > '9') {
      return 20u;
    }
    v = v * 10u + (unsigned)(*p - '0');
    if (v > 300u) {
      return 300u;
    }
  }
  if (v < 1u) {
    return 1u;
  }
  return (unsigned)v;
}

int main(int argc, char **argv) {
  int fds[MAX_DEVS];
  struct pollfd pfds[MAX_DEVS];
  int n;
  unsigned timeout_sec;
  int remaining_ms;

  timeout_sec = parse_timeout(argc > 1 ? argv[1] : NULL);
  n = open_volume_devs(fds, MAX_DEVS);
  if (n <= 0) {
    return EXIT_TIMEOUT;
  }

  /* 吞掉残留 DOWN，避免提示未出就选中 */
  drain_pending(fds, n);

  for (int i = 0; i < n; i++) {
    pfds[i].fd = fds[i];
    pfds[i].events = POLLIN;
    pfds[i].revents = 0;
  }

  remaining_ms = (int)timeout_sec * 1000;
  while (remaining_ms > 0) {
    int slice = remaining_ms > 1000 ? 1000 : remaining_ms;
    int pr = poll(pfds, (nfds_t)n, slice);
    if (pr < 0) {
      if (errno == EINTR) {
        continue;
      }
      release_all(fds, n);
      return EXIT_TIMEOUT;
    }
    if (pr == 0) {
      remaining_ms -= slice;
      continue;
    }
    for (int i = 0; i < n; i++) {
      struct input_event ev;
      if (!(pfds[i].revents & POLLIN)) {
        continue;
      }
      for (;;) {
        ssize_t r = read(fds[i], &ev, sizeof(ev));
        if (r < 0) {
          if (errno == EAGAIN || errno == EWOULDBLOCK) {
            break;
          }
          break;
        }
        if (r != (ssize_t)sizeof(ev)) {
          break;
        }
        if (ev.type != EV_KEY || ev.value != 1) {
          continue;
        }
        if (ev.code == KEY_VOLUMEUP) {
          release_all(fds, n);
          return EXIT_UP;
        }
        if (ev.code == KEY_VOLUMEDOWN) {
          release_all(fds, n);
          return EXIT_DOWN;
        }
      }
    }
    remaining_ms -= slice;
  }

  release_all(fds, n);
  return EXIT_TIMEOUT;
}
