# 鍙戠増涓庢洿鏂版棩蹇楋紙缁欑淮鎶よ€?/ AI锛?

> 缂栫爜鏀瑰姛鑳芥垨淇?bug 鏃讹細**鍏堝啓 `changelog.md` 鐨?`## Unreleased`**锛屽啀鏀逛唬鐮併€?
> 鐢ㄦ埛鍙鐨勬枃妗ｇ珯鏃ュ織鍦ㄥ彂鐗堟椂鐢卞伐浣滄祦浠?`changelog.md` 鍚屾锛涘紑鍙戜腑涔熷彲鎵嬪姩鍚屾浠ヤ究棰勮鏂囨。绔欍€?

## 鏃ュ織鍐欏摢閲?

| 鏂囦欢                        | 鐢ㄩ€?                                                                                |
| ----------------------------- | ------------------------------------------------------------------------------------- |
| 浠撳簱鏍圭洰褰?`changelog.md` | **鍞竴鎵嬪啓婧?*銆傚紑鍙戜腑鎶婃潯鐩啓鍦?`## Unreleased` 涓?                        |
| `docs/guide/changelog.md`     | 鏂囨。绔欍€屾洿鏂版棩蹇椼€嶉〉锛堝彂鐗堝伐浣滄祦鍚屾锛涘紑鍙戦瑙堝彲鎵嬪姩澶嶅埗锛? |
| `docs/public/changelog.md`    | Pages / `updateJson` 鎸囧悜鐨?changelog锛堝悓涓婏級                                   |

### Unreleased 鍐欐硶

````markdown
## Unreleased

- 鐢ㄤ竴涓ゅ彞璇存竻鐢ㄦ埛鑳芥劅鐭ョ殑鍙樺寲锛堜慨浜嗕粈涔?/ 鏂板浠€涔堬級
- 涓€鏉′竴涓鐐癸紱閲嶅ぇ鐗堟湰鍙敤灏忔爣棰樺垎缁?```

- 鍙戠増鍓嶄繚鎸?`## Unreleased` 鍦ㄦ枃浠舵渶涓婃柟锛堟爣棰?`# 鏇存柊鏃ュ織` 涔嬪悗锛夈€?- 鐗堟湰鍙锋牸寮忥細`## 2026.07.25` 鎴?`## 2026.07.25.2`锛堢敱鍙戠増宸ヤ綔娴佸啓鍏ワ級銆?

## 鍙戠増鏃跺伐浣滄祦鍋氫粈涔?

Actions 鈫?**Release Module**锛堟垨鎺ㄩ€?`v*` tag锛夛細

鍙戠増瀵硅瘽妗嗗彲鍕鹃€?4 椤癸紙榛樿鍏ㄩ€夛級锛?

| 鍕鹃€?      | GitHub Release 璧勪骇                       | 浼氭敼鍝潯鏇存柊閫氶亾                                          |
| ----------- | ------------------------------------------- | ---------------------------------------------------------------- |
| 妯″潡 zip   | 5 涓彉浣?zip锛坄update.json` 鈫?`-full`锛? | `update.json` + `module.prop`锛圡agisk / APP銆屾ā鍧楁洿鏂般€嶏級 |
| Rust 瀹堟姢 | `qscd-rust-arm64` / `qscd-rust-arm`         | `qscd/manifest.json`锛圵ebUI 瀹堟姢鍗＄墖锛?                     |
| C 瀹堟姢    | `qscd-c-arm64` / `qscd-c-arm`               | 鍚屼笂                                                           |
| 浼翠荆 APK  | `QSC-Battery_v*.apk`                        | `app-update.json`锛圓PP 鑷韩鏇存柊锛?                           |

### 鍗曠嫭鍙戠増鏃躲€屾ā鍧楁娴嬫洿鏂般€嶆€庝箞澶勭悊

涓夊閫氶亾褰兼鐙珛锛?*鍙敼鍕鹃€夐」瀵瑰簲鐨勬竻鍗?*锛屼笉浼氫簰鐩歌鎶ワ細

| 鍦烘櫙             | Magisk / APP 妯″潡鏇存柊              | WebUI 瀹堟姢鏇存柊               | APP 鑷韩鏇存柊                       |
| ------------------ | ------------------------------------- | -------------------------------- | ------------------------------------- |
| 鍙嬀 zip          | 鏈夛紙`update.json` 鏂?versionCode锛? | 鍚?                              | 鍚?                                   |
| 鍙嬀 Rust 鍜?鎴?C | **鍚?*锛堜笉纰?`update.json`锛?       | 鏈夛紙`manifest.version` bump锛? | 鍚?                                   |
| 鍙嬀 APK          | *_鍚?_                                | 鍚?                              | 鏈夛紙闇€鍏?bump APP `versionCode`锛? |
| 鍏ㄩ€?             | 鏈?                                   | 鏈?                              | 鏈?                                   |

瑕佺偣锛?

1. **妯″潡鏇存柊鍙 `update.json`**銆傚崟鐙彂浜岃繘鍒?/ APK 鏃?post 鑴氭湰鏁呮剰涓嶆敼瀹冿紝Magisk 绠＄悊鍣ㄥ拰 APP銆屾鏌ユā鍧楁洿鏂般€嶄笉浼氳楠椼€?2. **瀹堟姢鏇存柊鍙 `qscd/manifest.json`**銆傚彧鍙?Rust 鏃朵繚鐣?Pages 涓婃棫鐨?C 鏂囦欢锛涘彧鍙?C 鍚岀悊銆備换涓€濂楀彂甯冮兘浼氬啓鍏ユ湰娆?`version`锛學ebUI 鍙鍑烘柊瀹堟姢銆?3. **APP 鏇存柊鍙 `app-update.json`**銆傚彧鍙?APK 鍓嶈鍏堟彁楂?`apps/android/build.gradle.kts` 鐨?`versionCode` / `versionName`銆?4. 鍚屾棩鍙慨瀹堟姢鎴?APK锛氱増鏈彲鐢?`20260717.2` 杩欑被鍚庣紑锛沜hangelog 浠嶄細 promote锛屼絾妯″潡 `update.json` 鍙繚鎸佹棫鐗堛€?
   宸ヤ綔娴佹楠わ細

1. 鎵撳寘妯″潡 zip + 缂栬瘧瀹堟姢 / APK锛屾寜鍕鹃€夊垱寤?GitHub Release锛堟鏂囦紭鍏堝彇褰撳墠鐗堟湰鑺傦紱娌℃湁鍒欏洖閫€ Unreleased锛?2. `promote-changelog.py <version>`锛氶潪绌?`Unreleased` 鈫?褰撳墠鏃ユ湡鐗堟湰鍙凤紝骞剁暀涓嬬┖ stub
1. `promote-changelog.py --export-docs`锛氭枃妗ｇ珯涓や唤 changelog **鍘绘帀 Unreleased**
1. 鎸夊嬀閫夋洿鏂?`update.json` / `qscd/manifest` / `app-update.json` 绛夊苟鎺ㄩ€佷富鍒嗘敮锛涘洜 `GITHUB_TOKEN` 鎺ㄩ€佷笉浼氳繛閿佽Е鍙戝叾瀹?Actions锛岃剼鏈細鍐?`gh workflow run build-docs.yml`

宸ヤ綔娴佹媶涓?`build` 鈫?`publish` 鈫?`post` 涓夐樁娈碉紱鐗堟湰瑙ｆ瀽瑙?`resolve-release-version.py`锛屽洖鍐欒 `post-release-update.sh`銆?

### 灞曠ず鐗堝彿鎬庝箞鍗?

`version` 杈撳叆**鍙┖**銆傜┖鏃舵寜姝ｅ紡 / 棰勫彂甯冮€氶亾褰撳墠娓呭崟鑷姩鍗囧彿锛?

| 褰撳墠鐗堟湰鐩稿銆屽綋澶╅鐗堛€?       | 缁撴灉                                         |
| --------------------------------------- | ---------------------------------------------- |
| 灏忎簬褰撳ぉ棣栫増锛堟垨灏氭棤鐗堟湰锛? | 鍗囧埌褰撳ぉ棣栫増 `yyyy.MM.dd`                |
| 绛変簬鎴栧ぇ浜庡綋澶╅鐗?               | 鍦ㄥ綋鍓嶇増鍙蜂笂 +1锛堝 `鈥?2` 鈫?`鈥?3`锛? |

鎵嬪～浠嶅彲鐢細`20260916` / `2026.09.16.2`銆?
鍙戠増 `versionCode` 涓庡睍绀虹増瀵归綈锛歚YYYYMMDD * 100 + 淇鍙穈锛堝 `2026.09.16` 鈫?`2026091601`锛宍.2` 鈫?`2026091602`锛夛紝骞朵笌璺ㄩ€氶亾宸茬煡鏈€澶у€煎彇杈冨ぇ锛岄伩鍏嶅洖閫€銆侰I 閫氶亾浠嶇敤鍗曡皟 +1銆?

## 鏈湴鍛戒护锛堝彲閫夛級

```bash
python3 tooling/scripts/promote-changelog.py 2026.07.25 changelog.md

python3 tooling/scripts/promote-changelog.py --export-docs changelog.md \
  docs/guide/changelog.md docs/public/changelog.md
```
````

## AI / 鍗忎綔鑰呮鏌ユ竻鍗?

1. 鏈夌敤鎴峰彲瑙佹敼鍔?鈫?`changelog.md` 鈫?`## Unreleased` 杩藉姞 bullet
2. 涓嶈鎶?Unreleased 鍐欒繘 `docs/**/changelog.md`
3. 涓嶈鍒犵┖鐨?`## Unreleased` stub
4. 鍙戠増鐢ㄥ伐浣滄祦锛屽嬁婕忓悓姝ユ枃妗ｇ珯涓や唤鏃ュ織
5. 鍙彂 APK 鏃?bump APP `versionCode`锛涘彧鍙戝畧鎶ゆ椂涓嶅繀 bump 妯″潡 `update.json`

鐩稿叧鑴氭湰锛歚promote-changelog.py`銆乣prepare-release-notes.py`銆乣resolve-release-version.py`銆乣version_code.py` / `next-version_code.py`銆乣stamp-ci-module-version.py`銆乣git-push-tree.sh`銆乣publish-ci-dist.sh`銆乣publish-ci-product.sh`銆乣publish-updates.sh`銆乣fetch-ci-packaging-deps.sh`銆乣seed-updates-channels.sh`銆乣post-release-update.sh`銆?
鏋勫缓缁嗚妭瑙?[`BUILD.md`](./BUILD.md)銆?

## 鏇存柊閫氶亾涓庝骇鐗╀粨

涓夊鍏紑鍦板潃锛岃亴璐ｅ垎寮€锛?

| 浠?                  | 鐢ㄩ€?                                                                                                                                               |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| **GitHub Pages**     | Magisk / KSU / APatch `updateJson`銆佹枃妗ｇ珯銆佺ǔ瀹氶暅鍍忓浠姐€?_绠＄悊鍣ㄥ彧璁よ繖閲屻€?_                                                       |
| **GitHub Release**   | 姝ｅ紡 / 棰勫彂甯冪殑妯″潡 zip銆丄PK銆佸畧鎶や簩杩涘埗鍏紑涓嬭浇锛坄鈥?releases/download/<tag>/鈥锛夈€侫PP/WebUI 鏇存柊閫氶亾涓嬭浇鎸囧悜杩欓噷銆? |
| **`ci-dist` 鍒嗘敮** | CI 浜х墿锛屽垎鐩綍锛歚module/`路`app/`路`qscd/`銆傚悇宸ヤ綔娴佸彧鏀硅嚜宸辩殑鐩綍锛?*鏅€氭帹閫佷繚鐣欏巻鍙?*锛堜笉鍐?orphan force-push锛夈€?      |
| **`updates` 鍒嗘敮** | APP / WebUI **妫€娴?*鍏冩暟鎹細`stable/` 路 `prerelease/` 路 `ci/` 涓嬪悇鏈?`update.json`銆乣app-update.json`銆乣qscd/manifest.json`銆?             |

| 閫氶亾    | 妫€娴嬶紙updates锛?    | 涓嬭浇鎸囧悜                                           |
| --------- | ---------------------- | ------------------------------------------------------ |
| 姝ｅ紡    | `updates/stable/*`     | Pages锛坄eikeitsu.github.io/鈥?releases`路`鈥?qscd`锛? |
| 棰勫彂甯? | `updates/prerelease/*` | 璇ユ棰勫彂甯?Release 璧勪骇                           |
| CI        | `updates/ci/*`         | `ci-dist/{module,app,qscd}/鈥锛坖sDelivr/raw锛?       |

- Magisk `module.prop` 鐨?`updateJson` **濮嬬粓** `https://eikeitsu.github.io/QSC-Battery/update.json`锛堜笌 APP/WebUI 鏇存柊閫氶亾鍒嗙锛夈€?- 妯″潡 / APP / 瀹堟姢涓夐」 **鐙珛宸ヤ綔娴?+ 鐙珛 `versionCode`**锛涘畧鎶ゅ唴 Rust / C **鍒嗗埆缂栬瘧**锛屾湭鏀逛晶缁ф壙锛屽叡鐢ㄩ€氶亾 `versionCode`锛堟洿鏂版娴嬩粛鏄竴涓€屽畧鎶ゃ€嶄骇鍝侊紝鍝堝笇鍚勮嚜鐙珛锛夈€?- 鍙戠増鍙敤澶氶」鍕鹃€夈€屽彂甯冩ā鍧?/ APK / Rust 瀹堟姢 / C 瀹堟姢銆嶏紙GitHub 鏃犲閫?select锛夈€佹瀯寤烘柟寮?choice锛堥噸鏂版瀯寤?/ 鏅嬪崌 CI锛夈€佸彂甯冨舰鎬?choice锛堟寮忕増 / 棰勫彂甯?/ 鑽夌锛夈€?- **姝ｅ紡鐗?*锛歚post`鍐?Pages锛屽苟鍚屾`updates/stable`锛堜笅杞?URL 涔熸寚鍚?Pages锛夈€?*棰勫彂甯?*锛氫笉鍐?Pages锛屽啓 `updates/prerelease`锛圧elease 璧勪骇锛夈€?*鑽夌**锛氶兘涓嶅啓銆?
