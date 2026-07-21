const QscApi = {
  EXEC_TIMEOUT: 8000,

  hasBridge() {
    return typeof ksu !== "undefined" && typeof ksu.exec === "function";
  },

  exec(cmd) {
    return new Promise((resolve) => {
      let settled = false;
      const finish = (result) => {
        if (settled) return;
        settled = true;
        resolve(result);
      };

      const timer = setTimeout(() => {
        finish({ errno: -2, stdout: "", stderr: "timeout" });
      }, this.EXEC_TIMEOUT);

      if (!this.hasBridge()) {
        clearTimeout(timer);
        finish({ errno: -1, stdout: "", stderr: "no_ksu_bridge" });
        return;
      }

      const cb = `cb_${Date.now()}_${Math.random().toString(36).slice(2, 9)}`;
      window[cb] = (errno, stdout, stderr) => {
        clearTimeout(timer);
        delete window[cb];
        finish({
          errno: typeof errno === "number" ? errno : 0,
          stdout: stdout == null ? "" : String(stdout),
          stderr: stderr == null ? "" : String(stderr),
        });
      };

      try {
        // KernelSU / Magisk WebUI 常见签名：exec(cmd, optionsJson, callbackName)
        ksu.exec(cmd, "{}", cb);
      } catch (error) {
        try {
          // 兼容部分管理器：exec(cmd, callbackName)
          ksu.exec(cmd, cb);
        } catch (error2) {
          clearTimeout(timer);
          delete window[cb];
          finish({ errno: -1, stdout: "", stderr: String(error2 || error) });
        }
      }
    });
  },

  async getConf(key) {
    const result = await this.exec(
      `grep '^${key}=' '${QSC.CONF}' 2>/dev/null | tail -1 | cut -d= -f2-`,
    );
    return result.stdout.trim();
  },

  async setConf(key, value) {
    await this.exec(
      `grep -q '^${key}=' '${QSC.CONF}' 2>/dev/null && sed -i 's|^${key}=.*|${key}=${value}|' '${QSC.CONF}' || echo '${key}=${value}' >> '${QSC.CONF}'`,
    );
  },

  openUrl(url) {
    return this.exec(
      `am start -a android.intent.action.VIEW -d '${url}' >/dev/null 2>&1`,
    );
  },

  /** 微信收款页需走微信内置 WebView，系统浏览器会报「不支持该种支付方式」 */
  openWxPay(url) {
    const safe = String(url || "").replace(/'/g, "");
    return this.exec(
      `am start -n com.tencent.mm/.plugin.webview.ui.tools.WebViewUI -d '${safe}' >/dev/null 2>&1`,
    );
  },
};
