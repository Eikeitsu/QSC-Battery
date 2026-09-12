/*
 * qsc — QSC-Battery CLI 入口（薄包装）
 *
 * 实际逻辑仍在模块内 bin/qsc.sh；本二进制只负责：
 *   1. 找到模块目录
 *   2. exec sh …/bin/qsc.sh "$@"
 *
 * 安装位置：/data/adb/qsc/bin/qsc（不挂 system）
 */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define MOD_ID "QSC_Battery"
#define QSC_SH "bin/qsc.sh"

static int try_exec(const char *moddir, int argc, char **argv) {
	char script[512];
	char *args[64];
	int i;

	if (argc + 2 >= (int)(sizeof(args) / sizeof(args[0]))) {
		fprintf(stderr, "qsc: too many arguments\n");
		return 2;
	}

	if (snprintf(script, sizeof(script), "%s/%s", moddir, QSC_SH) >= (int)sizeof(script)) {
		fprintf(stderr, "qsc: path too long\n");
		return 2;
	}

	if (access(script, R_OK) != 0) {
		return -1;
	}

	args[0] = "sh";
	args[1] = script;
	for (i = 1; i < argc; i++) {
		args[i + 1] = argv[i];
	}
	args[argc + 1] = NULL;

	execv("/system/bin/sh", args);
	execv("/vendor/bin/sh", args);
	execv("/bin/sh", args);
	fprintf(stderr, "qsc: exec sh failed: %s\n", strerror(errno));
	return 127;
}

int main(int argc, char **argv) {
	const char *candidates[] = {
		"/data/adb/modules/" MOD_ID,
		"/data/adb/modules_update/" MOD_ID,
		NULL,
	};
	const char *env = getenv("QSC_MODDIR");
	int i, rc;

	if (env && env[0]) {
		rc = try_exec(env, argc, argv);
		if (rc >= 0) {
			return rc;
		}
	}

	for (i = 0; candidates[i]; i++) {
		rc = try_exec(candidates[i], argc, argv);
		if (rc >= 0) {
			return rc;
		}
	}

	fprintf(stderr,
		"qsc: module not found (expected /data/adb/modules/%s)\n"
		"     Install QSC-Battery Magisk module first.\n",
		MOD_ID);
	return 1;
}
