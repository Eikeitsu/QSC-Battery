const QscUi = {
  toast(message) {
    const snackbar = document.getElementById("snackbar");
    const text = document.getElementById("snackbarText");
    if (!snackbar || !text) return;
    text.textContent = message;
    snackbar.classList.add("show");
    clearTimeout(snackbar._timer);
    snackbar._timer = setTimeout(() => snackbar.classList.remove("show"), 2200);
  },

  toggleExpand(id) {
    document.getElementById(`expand-${id}`)?.classList.toggle("open");
    document.getElementById(`arrow-${id}`)?.classList.toggle("open");
  },

  renderChips(containerId, items, current, handler) {
    const container = document.getElementById(containerId);
    if (!container) return;
    container.innerHTML = items
      .map((item) => {
        const active = String(current) === item.id ? " active" : "";
        return `<div class="chip${active}" data-value="${item.id}">${item.l}</div>`;
      })
      .join("");
    container.querySelectorAll(".chip").forEach((chip) => {
      chip.addEventListener("click", (event) => {
        event.stopPropagation();
        handler(chip.dataset.value);
      });
    });
  },

  applyFontScale(scale) {
    const value = Number.isFinite(scale) ? scale : 1;
    document.documentElement.style.setProperty("--font-scale", value);
    const slider = document.getElementById("fontSlider");
    const desc = document.getElementById("fontSizeDesc");
    if (slider) slider.value = value;
    if (desc) desc.textContent = `${value.toFixed(2)}x`;
    try {
      localStorage.setItem(QSC.FONT_KEY, value);
    } catch (_) {}
    this.syncTopbarSpacer();
  },

  onFontSliderChange() {
    this.applyFontScale(
      parseFloat(document.getElementById("fontSlider").value),
    );
  },

  updateSubs() {
    const stop = parseInt(document.getElementById("power_stop").value, 10) || 0;
    const start =
      parseInt(document.getElementById("power_start").value, 10) || 0;
    const tempOn = document.getElementById("temperature_switch").checked;
    const powerSub = document.getElementById("powerSub");
    const tempSub = document.getElementById("tempSub");

    let powerText = "阈值无效";
    if (stop === 110) powerText = "电量停充已关闭";
    else if (stop > start) powerText = `停止 ${stop}% · 恢复 ${start}%`;

    if (powerSub) powerSub.textContent = powerText;

    let tempText = "已关闭";
    if (tempOn) {
      const stopTemp = document.getElementById("temperature_switch_stop").value;
      const startTemp = document.getElementById(
        "temperature_switch_start",
      ).value;
      tempText = `停充 ≥${stopTemp}°C · 恢复 ≤${startTemp}°C`;
    }
    if (tempSub) tempSub.textContent = tempText;

    const homePower = document.getElementById("homePowerPlan");
    const homeTemp = document.getElementById("homeTempPlan");
    const homeFull = document.getElementById("homeFullPlan");
    const homeReset = document.getElementById("homeResetPlan");
    if (homePower) homePower.textContent = powerText;
    if (homeTemp) homeTemp.textContent = tempText;
    if (homeFull)
      homeFull.textContent = document.getElementById("charge_full")?.checked
        ? "已开启"
        : "已关闭";
    if (homeReset)
      homeReset.textContent = document.getElementById("power_reset")?.checked
        ? "已开启"
        : "已关闭";
  },

  syncTopbarSpacer() {
    const bar = document.getElementById("topbar");
    const spacer = document.getElementById("topbarSpacer");
    if (!bar || !spacer) return;
    spacer.style.height = `${Math.ceil(bar.getBoundingClientRect().height)}px`;
  },
};
