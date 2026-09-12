#!/usr/bin/env python3
"""Rewrite AndroidManifest activity-aliases for battery icon buckets."""
from pathlib import Path

p = Path(r"d:\Xuyingjie_wb\Downloads\magisk\QSC-Battery\app\app\src\main\AndroidManifest.xml")
levels = list(range(0, 101, 10))


def alias(name: str, icon: str, enabled: str = "false") -> str:
    return f"""        <activity-alias
            android:name=".{name}"
            android:enabled="{enabled}"
            android:exported="true"
            android:icon="@mipmap/{icon}"
            android:label="@string/app_name"
            android:roundIcon="@mipmap/{icon}"
            android:targetActivity=".MainActivity">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity-alias>
"""


parts: list[str] = []
parts.append("        <!-- 静态默认（动态电量关闭时）；清单默认启用，保证首次安装就有图标 -->\n")
parts.append(alias("MainActivityDefault", "ic_launcher", "true"))
parts.append("\n        <!-- 备用环形静态图标 -->\n")
parts.append(alias("MainActivityAlt", "ic_launcher_alt"))
parts.append("\n        <!-- 动态电量：约 10% 一档；*_chg 为充电黄闪 -->\n")
for lv in levels:
    tag = f"{lv:02d}"
    parts.append(alias(f"MainActivityBat{tag}", f"ic_launcher_bat_{tag}"))
    parts.append(alias(f"MainActivityBat{tag}c", f"ic_launcher_bat_{tag}_chg"))
parts.append("\n        <!-- 环形风格动态电量 -->\n")
for lv in levels:
    tag = f"{lv:02d}"
    parts.append(alias(f"MainActivityAlt{tag}", f"ic_launcher_alt_{tag}"))
    parts.append(alias(f"MainActivityAlt{tag}c", f"ic_launcher_alt_{tag}_chg"))

text = p.read_text(encoding="utf-8")
# Prefer Chinese comment markers; fall back to English ones
markers = [
    ("        <!-- 静态默认", "        <receiver"),
    ("        <!-- 静态默认（动态电量关闭时）", "        <receiver"),
]
start = end = None
for a, b in markers:
    if a in text and b in text:
        start = text.index(a)
        end = text.index(b)
        break
if start is None:
    raise SystemExit("alias markers not found")
new = text[:start] + "".join(parts) + "\n" + text[end:]
p.write_text(new, encoding="utf-8")
print("ok aliases=", 2 + len(levels) * 4)
