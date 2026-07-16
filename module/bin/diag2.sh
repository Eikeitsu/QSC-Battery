#!/system/bin/sh
OUT="/sdcard/qsc_diag2.txt"
> "$OUT"

echo "=== [1] MCA charger 目录完整列表 ===" >> "$OUT"
ls -laR /sys/devices/platform/soc/soc:mca_business_charger/ >> "$OUT" 2>&1

echo "" >> "$OUT"
echo "=== [2] 所有 handle_state 节点值 ===" >> "$OUT"
find /sys/devices/platform/ -maxdepth 7 -name "handle_state" 2>/dev/null | while read f; do
  val=$(cat "$f" 2>/dev/null)
  echo "$f = $val" >> "$OUT"
done

echo "" >> "$OUT"
echo "=== [3] MCA charger 下所有 force/enable 节点 ===" >> "$OUT"
find /sys/devices/platform/soc/ -maxdepth 6 \( -name "force_charging" -o -name "enable_charging" -o -name "charge_control" -o -name "stop_charging" -o -name "disable_charging" \) 2>/dev/null | while read f; do
  val=$(cat "$f" 2>/dev/null)
  echo "$f = $val" >> "$OUT"
done

echo "" >> "$OUT"
echo "=== [4] charge_control_limit ===" >> "$OUT"
for f in /sys/class/power_supply/battery/charge_control_limit /sys/class/power_supply/battery/charge_control_limit_max; do
  if [ -f "$f" ]; then
    perms=$(stat -c '%a' "$f" 2>/dev/null)
    val=$(cat "$f" 2>/dev/null)
    echo "$f (perm=$perms) = $val" >> "$OUT"
  else
    echo "$f NOT FOUND" >> "$OUT"
  fi
done

echo "" >> "$OUT"
echo "=== [5] USB input_current_limit ===" >> "$OUT"
ls -la /sys/class/power_supply/usb/input_current_limit >> "$OUT" 2>&1
cat /sys/class/power_supply/usb/input_current_limit >> "$OUT" 2>&1

echo "" >> "$OUT"
echo "=== [6] battery 所有 control/limit/enable/disable 节点 ===" >> "$OUT"
find /sys/class/power_supply/battery/ -maxdepth 1 -type f 2>/dev/null | grep -iE 'control|limit|enable|disable|suspend|stop' | while read f; do
  perms=$(stat -c '%a' "$f" 2>/dev/null)
  val=$(cat "$f" 2>/dev/null | tr '\n' ' ')
  echo "$f (perm=$perms) = $val" >> "$OUT"
done

echo "" >> "$OUT"
echo "=== [7] 写入测试: charge_control_limit = 16 ===" >> "$OUT"
if [ -f /sys/class/power_supply/battery/charge_control_limit ]; then
  echo 16 > /sys/class/power_supply/battery/charge_control_limit 2>> "$OUT"
  echo "写入后值: $(cat /sys/class/power_supply/battery/charge_control_limit 2>/dev/null)" >> "$OUT"
fi

echo "" >> "$OUT"
echo "=== [8] 写入测试: USB input_current_limit = 0 ===" >> "$OUT"
if [ -f /sys/class/power_supply/usb/input_current_limit ]; then
  echo 0 > /sys/class/power_supply/usb/input_current_limit 2>> "$OUT"
  echo "写入后值: $(cat /sys/class/power_supply/usb/input_current_limit 2>/dev/null)" >> "$OUT"
fi

echo "" >> "$OUT"
echo "=== [9] 写入测试: handle_state = 1 (尝试反向) ===" >> "$OUT"
HANDLE="/sys/devices/platform/soc/soc:mca_business_charger/handle_state"
if [ -f "$HANDLE" ]; then
  echo 1 > "$HANDLE" 2>> "$OUT"
  sleep 1
  echo "写入1后值: $(cat $HANDLE 2>/dev/null)" >> "$OUT"
  echo "电池电流: $(cat /sys/class/power_supply/battery/current_now 2>/dev/null)" >> "$OUT"
  echo 0 > "$HANDLE" 2>> "$OUT"
  echo "恢复0后值: $(cat $HANDLE 2>/dev/null)" >> "$OUT"
fi

echo "" >> "$OUT"
echo "=== 完成 ===" >> "$OUT"