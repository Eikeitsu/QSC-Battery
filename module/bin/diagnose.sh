#!/system/bin/sh
# QSC 诊断脚本 - 扫描充电控制节点，用于适配新机型
# 在终端执行: sh /data/adb/modules/QSC_Battery/bin/diagnose.sh
# 结果保存到 /sdcard/qsc_diagnose.txt

OUT="/sdcard/qsc_diagnose.txt"
echo "========================================" > "$OUT"
echo "QSC 充电控制节点诊断报告 v2" >> "$OUT"
echo "时间: $(date +%F_%T)" >> "$OUT"
echo "设备: $(getprop ro.product.model)" >> "$OUT"
echo "芯片: $(getprop ro.product.board) / $(getprop ro.board.platform)" >> "$OUT"
echo "系统: $(getprop ro.build.version.incremental)" >> "$OUT"
echo "内核: $(uname -r)" >> "$OUT"
echo "HyperOS: $(getprop ro.mi.os.version)" >> "$OUT"
echo "SOC: $(getprop ro.soc.model)" >> "$OUT"
echo "========================================" >> "$OUT"

# 1. 扫描所有 power_supply 目录
echo "" >> "$OUT"
echo "[1] /sys/class/power_supply/ 下所有可写文件:" >> "$OUT"
for ps in /sys/class/power_supply/*/; do
  if [ -d "$ps" ]; then
    echo "  --- $(basename $ps) ---" >> "$OUT"
    find "$ps" -maxdepth 1 -type f 2>/dev/null | while read f; do
      perm=$(stat -c '%a' "$f" 2>/dev/null)
      val=$(cat "$f" 2>/dev/null | tr '\n' ' ')
      echo "    $(basename $f) [$perm] = $val" >> "$OUT"
    done
  fi
done

# 2. 扫描所有 handle_state 节点
echo "" >> "$OUT"
echo "[2] 全系统 handle_state 节点:" >> "$OUT"
find /sys/devices/platform/ -maxdepth 8 -type f -name "handle_state" 2>/dev/null | while read f; do
  val=$(cat "$f" 2>/dev/null | tr '\n' ' ')
  echo "  $f = $val" >> "$OUT"
done

# 3. 扫描 mca 相关所有文件
echo "" >> "$OUT"
echo "[3] /sys/devices/platform/soc/ 下 mca 充电相关所有文件:" >> "$OUT"
find /sys/devices/platform/soc/ -maxdepth 6 -path "*mca*charg*" -type f 2>/dev/null | while read f; do
  val=$(cat "$f" 2>/dev/null | tr '\n' ' ')
  echo "  $f = $val" >> "$OUT"
done
find /sys/devices/platform/soc/ -maxdepth 6 -path "*mca*" -type f 2>/dev/null | while read f; do
  val=$(cat "$f" 2>/dev/null | tr '\n' ' ')
  echo "  $f = $val" >> "$OUT"
done

# 4. 扫描 charger 相关可写文件
echo "" >> "$OUT"
echo "[4] battery/charger 目录下疑似开关节点 (含 charge/charging/enable/disable/suspend/stop):" >> "$OUT"
find /sys/class/power_supply/ /sys/devices/platform/soc/ -maxdepth 6 -type f \( \
  -iname "*charge_disable*" -o -iname "*charging_enabled*" -o -iname "*charge_enabled*" \
  -o -iname "*disable_charging*" -o -iname "*stop_charging*" -o -iname "*input_suspend*" \
  -o -iname "*batt_slate*" -o -iname "*store_mode*" -o -iname "*chg_suspend*" \
  -o -iname "*chg_mode*" -o -iname "*charger_limit*" -o -iname "*pin_enabled*" \
  -o -iname "*charge_control*" -o -iname "*force_charging*" -o -iname "*enable_charging*" \
  -o -iname "*battery_charging*" \
\) 2>/dev/null | while read f; do
  val=$(cat "$f" 2>/dev/null | tr '\n' ' ')
  echo "  $f = $val" >> "$OUT"
done

# 5. 扫描所有 /sys/devices/platform/soc/ 下 charger/battery 目录文件
echo "" >> "$OUT"
echo "[5] /sys/devices/platform/soc/ 下所有 charger 相关目录的全部文件:" >> "$OUT"
for dir in $(find /sys/devices/platform/soc/ -maxdepth 5 -type d \( -iname "*charg*" -o -iname "*batter*" \) 2>/dev/null); do
  echo "  --- $dir ---" >> "$OUT"
  ls -la "$dir" 2>/dev/null | while read line; do
    echo "    $line" >> "$OUT"
  done
done

# 6. 当前充电状态
echo "" >> "$OUT"
echo "[6] 当前充电状态 (dumpsys battery):" >> "$OUT"
dumpsys battery >> "$OUT"

# 6b. cmd battery 状态
echo "" >> "$OUT"
echo "[6b] cmd battery 支持的命令:" >> "$OUT"
cmd battery 2>&1 | head -30 >> "$OUT"

# 6c. 所有 power_supply 的 current_now 和 voltage_now
echo "" >> "$OUT"
echo "[6c] 所有 power_supply 电流/电压/在线状态:" >> "$OUT"
for ps in /sys/class/power_supply/*/; do
  name=$(basename "$ps")
  online=$(cat "$ps/online" 2>/dev/null)
  current=$(cat "$ps/current_now" 2>/dev/null)
  voltage=$(cat "$ps/voltage_now" 2>/dev/null)
  type=$(cat "$ps/type" 2>/dev/null)
  echo "  $name: type=$type online=$online current=$current voltage=$voltage" >> "$OUT"
done

# 6d. 电流限制节点当前值
echo "" >> "$OUT"
echo "[6d] 电流限制节点当前值 (设0可停充):" >> "$OUT"
for node in \
  "/sys/class/power_supply/battery/constant_charge_current_max" \
  "/sys/class/power_supply/battery/current_max" \
  "/sys/class/power_supply/battery/input_current_max" \
  "/sys/class/power_supply/battery/charge_current" \
  "/sys/class/power_supply/battery/fast_charge_current_max" \
  "/sys/class/power_supply/battery/charge_type" \
; do
  if [ -f "$node" ]; then
    val=$(cat "$node" 2>/dev/null | tr '\n' ' ')
    echo "  $node = $val" >> "$OUT"
  fi
done

# 7. 尝试写入已知节点并检测效果
echo "" >> "$OUT"
echo "[7] 尝试向疑似节点写入停充值并读取结果:" >> "$OUT"
for node in \
  "/sys/class/power_supply/battery/charging_enabled" \
  "/sys/class/power_supply/battery/charge_disable" \
  "/sys/class/power_supply/battery/charge_enabled" \
  "/sys/class/power_supply/battery/disable_charging" \
  "/sys/class/power_supply/battery/input_suspend" \
  "/sys/class/power_supply/battery/batt_slate_mode" \
  "/sys/class/power_supply/battery/store_mode" \
  "/sys/class/power_supply/bms/charging_enabled" \
  "/sys/class/power_supply/charger/charge_disable" \
  "/sys/class/qcom-battery/charging_enabled" \
  "/sys/class/qcom-battery/charge_disable" \
  "/sys/class/qcom-battery/input_suspend" \
  "/sys/class/qcom-battery/battery_charging_enabled" \
  "/sys/kernel/debug/google_charger/chg_suspend" \
  "/sys/kernel/debug/google_charger/chg_mode" \
  "/proc/driver/charger_limit_enable" \
; do
  if [ -f "$node" ]; then
    before=$(cat "$node" 2>/dev/null | tr '\n' ' ')
    echo "  $node: 存在, 当前值=$before" >> "$OUT"
  fi
done

echo "" >> "$OUT"
echo "========================================" >> "$OUT"
echo "报告完成。请将此文件内容发给开发者。" >> "$OUT"
echo "文件位置: $OUT" >> "$OUT"
echo "========================================" >> "$OUT"

echo "诊断完成！报告保存到: $OUT"
echo "请运行: cat $OUT"
