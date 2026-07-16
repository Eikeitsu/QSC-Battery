const QscUi = {
  toast(message) {
    const snackbar = document.getElementById('snackbar');
    document.getElementById('snackbarText').textContent = message;
    snackbar.classList.add('show');
    clearTimeout(snackbar._timer);
    snackbar._timer = setTimeout(() => snackbar.classList.remove('show'), 2200);
  },

  toggleExpand(id) {
    document.getElementById(`expand-${id}`)?.classList.toggle('open');
    document.getElementById(`arrow-${id}`)?.classList.toggle('open');
  },

  renderChips(containerId, items, current, handler) {
    const container = document.getElementById(containerId);
    if (!container) return;
    container.innerHTML = items.map((item) => {
      const active = String(current) === item.id ? ' active' : '';
      return `<div class="chip${active}" data-value="${item.id}">${item.l}</div>`;
    }).join('');
    container.querySelectorAll('.chip').forEach((chip) => {
      chip.addEventListener('click', () => handler(chip.dataset.value));
    });
  },

  applyFontScale(scale) {
    document.documentElement.style.setProperty('--font-scale', scale);
    document.getElementById('fontSlider').value = scale;
    document.getElementById('fontSizeDesc').textContent = `${scale.toFixed(2)}x`;
    try { localStorage.setItem(QSC.FONT_KEY, scale); } catch (_) {}
  },

  onFontSliderChange() {
    this.applyFontScale(parseFloat(document.getElementById('fontSlider').value));
  },

  updateSubs() {
    const stop = parseInt(document.getElementById('power_stop').value, 10) || 0;
    const start = parseInt(document.getElementById('power_start').value, 10) || 0;
    const tempOn = document.getElementById('temperature_switch').checked;
    const powerSub = document.getElementById('powerSub');
    const tempSub = document.getElementById('tempSub');

    if (stop === 110) {
      powerSub.textContent = '电量停充已关闭';
    } else if (stop > start) {
      powerSub.textContent = `停止 ${stop}% · 恢复 ${start}%`;
    } else {
      powerSub.textContent = '阈值无效，停止值需大于恢复值';
    }

    if (tempOn) {
      const stopTemp = document.getElementById('temperature_switch_stop').value;
      const startTemp = document.getElementById('temperature_switch_start').value;
      tempSub.textContent = `停充 ≥${stopTemp}°C · 恢复 ≤${startTemp}°C`;
    } else {
      tempSub.textContent = '已关闭';
    }
  }
};
