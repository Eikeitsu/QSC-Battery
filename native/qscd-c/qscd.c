/*
 * 事件等待器（C 实现）：阻塞在内核 power_supply uevent 上，
 * 让 shell 主循环不再需要定时唤醒。
 *
 * 与 native/qscd（Rust 实现）行为逐字对齐：同样的子命令、同样的退出码、
 * 同样的钳位范围。两者可互换安装，模块只认 bin/qscd 这一个名字。
 *
 * 用法
 *   qscd wait-event <最长秒数> [最短秒数]
 *       先睡「最短秒数」压掉事件风暴，再等 power_supply 事件直到「最长秒数」。
 *       退出 0 = 有事件或已到时（调用方跑完整一轮）
 *       退出 2 = 本机不可用（调用方应永久退回 sleep）
 *   qscd probe
 *       安装时自检：能建起 netlink 套接字则退出 0。
 *   qscd selftest
 *       纯函数自检，供 CI 在宿主机上跑（不碰 netlink）。
 *
 * 设计约束：本程序不写任何充电节点，也不做阈值判定，只负责「等」。
 * 因此它异常退出时最坏结果是退化成定时轮询，而不是停充失效。
 */

#include <errno.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

/* sys/socket.h 要在 linux/netlink.h 之前：后者用到前者的 sa_family_t */
#include <sys/socket.h>
#include <sys/time.h>

#include <linux/netlink.h>

#ifndef NETLINK_KOBJECT_UEVENT
#define NETLINK_KOBJECT_UEVENT 15
#endif

/* 内核 uevent 载荷里的匹配串；命中即认为电池状态可能变了 */
static const char MATCH[] = "SUBSYSTEM=power_supply";
#define MATCH_LEN (sizeof(MATCH) - 1)

#define RECV_BUF 8192
/* 单次 recv 超时，用于周期性回到循环检查总截止时间 */
#define RECV_SLICE_SEC 2

#define EXIT_OK 0
#define EXIT_UNUSABLE 2

#define WAIT_MAX_CAP 3600u
#define WAIT_MAX_DEFAULT 30u
#define WAIT_FLOOR_DEFAULT 3u

/* uevent 载荷内含 '\0' 分隔，不能用 strstr，只能按字节扫 */
static int payload_matches(const char *buf, size_t len) {
  if (len < MATCH_LEN) {
    return 0;
  }
  for (size_t i = 0; i + MATCH_LEN <= len; i++) {
    if (memcmp(buf + i, MATCH, MATCH_LEN) == 0) {
      return 1;
    }
  }
  return 0;
}

/* 解析秒数：非法或缺省取 fallback，最终钳到 [0, cap] */
static unsigned long parse_secs(const char *arg, unsigned long fallback,
                                unsigned long cap) {
  unsigned long value = 0;
  int digits = 0;
  const char *p = arg;

  if (p == NULL) {
    return fallback > cap ? cap : fallback;
  }
  while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') {
    p++;
  }
  while (*p >= '0' && *p <= '9') {
    /* 早停即可，反正后面还要按 cap 钳位 */
    if (value > WAIT_MAX_CAP) {
      value = WAIT_MAX_CAP + 1;
      p++;
      digits = 1;
      continue;
    }
    value = value * 10 + (unsigned long)(*p - '0');
    digits = 1;
    p++;
  }
  while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') {
    p++;
  }
  if (digits == 0 || *p != '\0') {
    value = fallback;
  }
  return value > cap ? cap : value;
}

/* 成功返回 fd，失败返回 -1 */
static int uevent_socket_open(void) {
  struct sockaddr_nl addr;
  struct timeval tv;
  int fd;

  fd = socket(AF_NETLINK, SOCK_DGRAM | SOCK_CLOEXEC, NETLINK_KOBJECT_UEVENT);
  if (fd < 0) {
    return -1;
  }

  memset(&addr, 0, sizeof(addr));
  addr.nl_family = AF_NETLINK;
  addr.nl_pid = 0;    /* 交给内核分配，避免与其它监听者冲突 */
  addr.nl_groups = 1; /* 组 1 = kobject uevent 广播 */
  if (bind(fd, (const struct sockaddr *)&addr, sizeof(addr)) < 0) {
    close(fd);
    return -1;
  }

  tv.tv_sec = RECV_SLICE_SEC;
  tv.tv_usec = 0;
  if (setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv)) < 0) {
    close(fd);
    return -1;
  }
  return fd;
}

/* 1=命中 power_supply 事件；0=本次超时或事件无关；-1=套接字不可用 */
static int uevent_poll_once(int fd, char *buf, size_t cap) {
  ssize_t n = recv(fd, buf, cap, 0);

  if (n > 0) {
    return payload_matches(buf, (size_t)n);
  }
  if (n == 0) {
    return 0;
  }
  /* EAGAIN=收满超时；EINTR=被信号打断。两者都只是本次没拿到事件 */
  if (errno == EAGAIN || errno == EINTR) {
    return 0;
  }
  return -1;
}

/* 成功写入 *out 并返回 1；时钟不可用返回 0（调用方必须视为不可用，
 * 否则截止时间失效会让本进程一直挂在 recv 上） */
static int monotonic_sec(long *out) {
  struct timespec ts;

  if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
    return 0;
  }
  *out = (long)ts.tv_sec;
  return 1;
}

static void sleep_secs(unsigned long secs) {
  /* sleep 被信号打断时返回剩余秒数，补睡完，避免主循环提前一轮 */
  unsigned int left = (unsigned int)secs;

  while (left > 0) {
    left = sleep(left);
  }
}

static int wait_event(unsigned long max_secs, unsigned long floor_secs) {
  unsigned long floor = floor_secs > max_secs ? max_secs : floor_secs;
  unsigned long remaining;
  long now;
  long deadline;
  char buf[RECV_BUF];
  int fd;

  if (floor > 0) {
    sleep_secs(floor);
  }
  remaining = max_secs - floor;
  if (remaining == 0) {
    return EXIT_OK;
  }

  if (!monotonic_sec(&now)) {
    return EXIT_UNUSABLE;
  }
  fd = uevent_socket_open();
  if (fd < 0) {
    return EXIT_UNUSABLE;
  }

  deadline = now + (long)remaining;
  while (monotonic_sec(&now) && now < deadline) {
    int rc = uevent_poll_once(fd, buf, sizeof(buf));

    if (rc > 0) {
      close(fd);
      return EXIT_OK;
    }
    if (rc < 0) {
      close(fd);
      return EXIT_UNUSABLE;
    }
  }
  close(fd);
  return EXIT_OK;
}

/* 与 Rust 版的 #[cfg(test)] 用例一一对应，CI 在宿主机上跑 */
static int selftest(void) {
  static const char hit[] =
      "change@/devices/battery\0ACTION=change\0SUBSYSTEM=power_supply\0";
  static const char miss[] = "change@/devices/net\0ACTION=change\0SUBSYSTEM=net\0";
  int fails = 0;

#define CHECK(cond)                                                            \
  do {                                                                         \
    if (!(cond)) {                                                             \
      fprintf(stderr, "selftest failed: %s (line %d)\n", #cond, __LINE__);      \
      fails++;                                                                 \
    }                                                                          \
  } while (0)

  CHECK(payload_matches(hit, sizeof(hit) - 1));
  CHECK(!payload_matches(miss, sizeof(miss) - 1));
  CHECK(!payload_matches("", 0));
  CHECK(!payload_matches("short", 5));

  CHECK(parse_secs(NULL, 30, 3600) == 30);
  CHECK(parse_secs("5", 30, 3600) == 5);
  CHECK(parse_secs(" 7 ", 30, 3600) == 7);
  CHECK(parse_secs("99999", 30, 3600) == 3600);
  CHECK(parse_secs("abc", 30, 3600) == 30);
  CHECK(parse_secs("12x", 30, 3600) == 30);
  CHECK(parse_secs("", 30, 3600) == 30);

  /* floor 不得超过 max：max=2 时 floor 参数写 10 也应被压到 2 */
  {
    unsigned long max = parse_secs("2", 30, 3600);
    unsigned long floor = parse_secs("10", 3, max > 0 ? max : 1);

    CHECK(max == 2);
    CHECK(floor == 2);
  }

  /* floor >= max：只睡不建套接字，必须成功返回（不依赖 netlink 可用性） */
  CHECK(wait_event(0, 0) == EXIT_OK);

#undef CHECK

  if (fails == 0) {
    printf("ok\n");
    return EXIT_OK;
  }
  return 1;
}

int main(int argc, char **argv) {
  const char *cmd = argc > 1 ? argv[1] : NULL;

  if (cmd != NULL && strcmp(cmd, "wait-event") == 0) {
    unsigned long max = parse_secs(argc > 2 ? argv[2] : NULL, WAIT_MAX_DEFAULT,
                                   WAIT_MAX_CAP);
    unsigned long floor = parse_secs(argc > 3 ? argv[3] : NULL,
                                     WAIT_FLOOR_DEFAULT, max > 0 ? max : 1);

    return wait_event(max, floor);
  }
  if (cmd != NULL && strcmp(cmd, "probe") == 0) {
    int fd = uevent_socket_open();

    if (fd >= 0) {
      close(fd);
      printf("ok\n");
      return EXIT_OK;
    }
    fprintf(stderr, "qscd: netlink uevent socket unavailable\n");
    return EXIT_UNUSABLE;
  }
  if (cmd != NULL && strcmp(cmd, "selftest") == 0) {
    return selftest();
  }
  fprintf(stderr, "usage: qscd wait-event <max_secs> [floor_secs] | qscd probe\n");
  return EXIT_UNUSABLE;
}
