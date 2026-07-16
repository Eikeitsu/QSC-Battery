const QscApi = {
  exec(cmd) {
    return new Promise((resolve) => {
      const cb = `cb_${Date.now()}_${Math.random().toString(36).slice(2)}`;
      window[cb] = (errno, stdout, stderr) => {
        delete window[cb];
        resolve({ errno, stdout: stdout || '', stderr: stderr || '' });
      };
      try {
        ksu.exec(cmd, '{}', cb);
      } catch (error) {
        delete window[cb];
        resolve({ errno: -1, stdout: '', stderr: String(error) });
      }
    });
  },

  async getConf(key) {
    const result = await this.exec(`grep '^${key}=' '${QSC.CONF}' 2>/dev/null | tail -1 | cut -d= -f2`);
    return result.stdout.trim();
  },

  async setConf(key, value) {
    await this.exec(
      `grep -q '^${key}=' '${QSC.CONF}' 2>/dev/null && sed -i 's/^${key}=.*/${key}=${value}/' '${QSC.CONF}' || echo '${key}=${value}' >> '${QSC.CONF}'`
    );
  },

  openUrl(url) {
    return this.exec(`am start -a android.intent.action.VIEW -d '${url}'`);
  }
};
