package com.qsc.battery.core

import com.topjohnwu.superuser.Shell
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.nio.charset.StandardCharsets
import java.util.Base64

data class ExecResult(
    val code: Int,
    val out: String,
    val err: String,
) {
    val ok: Boolean get() = code == 0
}

class RootBridge {
    suspend fun isRootAvailable(): Boolean = withContext(Dispatchers.IO) {
        Shell.getShell().isRoot
    }

    suspend fun exec(cmd: String): ExecResult = withContext(Dispatchers.IO) {
        val result = Shell.cmd(cmd).exec()
        ExecResult(
            code = result.code,
            out = result.out.joinToString("\n"),
            err = result.err.joinToString("\n"),
        )
    }

    suspend fun exists(path: String): Boolean {
        val r = exec("[ -e '$path' ]")
        return r.ok
    }

    suspend fun readFile(path: String): String? {
        val r = exec("cat '$path' 2>/dev/null")
        return if (r.ok) r.out else null
    }

    suspend fun writeFile(path: String, content: String): Boolean {
        val b64 = Base64.getEncoder().encodeToString(content.toByteArray(StandardCharsets.UTF_8))
        val dir = path.substringBeforeLast('/', missingDelimiterValue = "")
        val r = exec(
            "mkdir -p '$dir' 2>/dev/null; " +
                "echo '$b64' | base64 -d > '$path.tmp' && mv '$path.tmp' '$path'",
        )
        return r.ok
    }

    suspend fun touch(path: String): Boolean = exec("mkdir -p \"\$(dirname '$path')\"; touch '$path'").ok

    suspend fun rm(path: String): Boolean = exec("rm -f '$path'").ok
}
