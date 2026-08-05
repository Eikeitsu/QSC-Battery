const QscApi = {
  EXEC_TIMEOUT: 8000,

  hasBridge() {
    return typeof ksu !== "undefined" && typeof ksu.exec === "function";
  },

  exec(cmd, timeoutMs) {
    const timeout = timeoutMs || this.EXEC_TIMEOUT;
    return new Promise((resolve) => {
      let settled = false;
      const finish = (result) => {
        if (settled) return;
        settled = true;
        resolve(result);
      };

      const timer = setTimeout(() => {
        finish({ errno: -2, stdout: "", stderr: "timeout" });
      }, timeout);

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
    const safeKey = String(key).replace(/[^a-zA-Z0-9_]/g, "");
    const safeVal = String(value).replace(/'/g, "");
    await this.exec(
      `sed -i '/^${safeKey}=/d' '${QSC.CONF}' 2>/dev/null; echo '${safeKey}=${safeVal}' >> '${QSC.CONF}'`,
    );
  },

  parseJsonc(text) {
    const cleaned = String(text || "")
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/^\s*\/\/.*$/gm, "")
      .replace(/,\s*([\]}])/g, "$1");
    return JSON.parse(cleaned);
  },

  async hasCurrentFeature() {
    const result = await this.exec(
      `[ -f '${QSC.CURRENT_CONF}' ] && [ -f '${QSC.CURRENT_LIB}' ] && echo 1 || echo 0`,
    );
    return result.stdout.trim() === "1";
  },

  // textarea / 表单：一行一个包名；落盘必须是 JSON 字符串数组
  normalizeAppList(value) {
    if (Array.isArray(value)) {
      return value.map((s) => String(s).trim()).filter(Boolean);
    }
    return String(value || "")
      .split(/\n+/)
      .map((s) => s.trim())
      .filter(Boolean);
  },

  async loadCurrentJsonc() {
    const result = await this.exec(`cat '${QSC.CURRENT_CONF}' 2>/dev/null`);
    if (!result.stdout.trim()) return { ...QSC.CURRENT_DEFAULTS };
    try {
      const parsed = this.parseJsonc(result.stdout);
      const merged = { ...QSC.CURRENT_DEFAULTS, ...parsed };
      merged.app_list = Array.isArray(merged.app_list)
        ? this.normalizeAppList(merged.app_list)
        : [...QSC.CURRENT_DEFAULTS.app_list];
      merged.battery_current = Array.isArray(merged.battery_current)
        ? merged.battery_current
        : [];
      return merged;
    } catch (_) {
      return { ...QSC.CURRENT_DEFAULTS };
    }
  },

  async saveCurrentJsonc(obj) {
    const payload = {
      current_control: Number(obj.current_control) ? 1 : 0,
      battery_stop: Number(obj.battery_stop) || 110,
      slow_charge: Number(obj.slow_charge) || 110,
      default_current_max: Number(obj.default_current_max) || 5000000,
      temperature_current: Number(obj.temperature_current) ? 1 : 0,
      default_current_limit: Number(obj.default_current_limit) || 40,
      default_current_max_limit: Number(obj.default_current_max_limit) || 1500000,
      temperature_current_limit: Number(obj.temperature_current_limit) || 45,
      constant_current_max: Math.max(
        50000,
        Number(obj.constant_current_max) || 100000,
      ),
      app_limit: Number(obj.app_limit) ? 1 : 0,
      app_current_max: Math.max(50000, Number(obj.app_current_max) || 200000),
      app_list: this.normalizeAppList(obj.app_list),
      bypass_mode: obj.bypass_mode === "auto" ? "auto" : "sim",
      safety_temp_max: Math.min(
        55,
        Math.max(40, Number(obj.safety_temp_max) || 48),
      ),
      battery_current: Array.isArray(obj.battery_current)
        ? obj.battery_current
        : [],
    };
    const json = JSON.stringify(payload, null, 2);
    const b64 = btoa(unescape(encodeURIComponent(json)));
    const result = await this.exec(
      `echo '${b64}' | base64 -d > '${QSC.CURRENT_CONF}' 2>/dev/null || echo '${b64}' | base64 --decode > '${QSC.CURRENT_CONF}' 2>/dev/null`,
    );
    return result.errno === 0 || result.errno === undefined;
  },

  /**
   * 已安装用户应用列表。优先 KernelSU WebUI 的 listUserPackages / getPackagesInfo
   * （与 Tricky Addon 同类桥接）；否则 pm list packages -3，名称回退为包名。
   */
  async listInstalledApps() {
    const fromBridge = () => {
      try {
        if (typeof ksu === "undefined") return null;
        let pkgs = null;
        if (typeof ksu.listUserPackages === "function") {
          pkgs = JSON.parse(ksu.listUserPackages() || "[]");
        } else if (typeof ksu.listAllPackages === "function") {
          pkgs = JSON.parse(ksu.listAllPackages() || "[]");
        }
        if (!Array.isArray(pkgs) || !pkgs.length) return null;
        let infos = null;
        if (typeof ksu.getPackagesInfo === "function") {
          try {
            infos = JSON.parse(
              ksu.getPackagesInfo(JSON.stringify(pkgs)) || "[]",
            );
          } catch (_) {
            infos = null;
          }
        }
        return pkgs.map((pkg, i) => ({
          package: pkg,
          name: infos?.[i]?.appLabel || infos?.[i]?.name || pkg,
        }));
      } catch (_) {
        return null;
      }
    };

    const bridged = fromBridge();
    if (bridged?.length) {
      return bridged.sort((a, b) =>
        (a.name || a.package).localeCompare(b.name || b.package, "zh"),
      );
    }

    const result = await this.exec(
      `pm list packages -3 2>/dev/null | sed 's/^package://' | sort`,
      20000,
    );
    const pkgs = result.stdout
      .split(/\r?\n/)
      .map((s) => s.trim())
      .filter(Boolean);
    return pkgs.map((pkg) => ({ package: pkg, name: pkg }));
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
