export const LINKS = {
  docs: "https://eikeitsu.github.io/QSC-Battery/",
  repo: "https://github.com/Eikeitsu/QSC-Battery",
  origin: "https://github.com/410154425/QuantitativeStopCharging_switch_magisk",
  wxPay:
    "https://payapp.weixin.qq.com/qrpay/order/home2?key=idc_CHNDVI_dHFNbTNZIWMMKIEdzUZtCA--",
  coolapkAuthor: "https://www.coolapk.com/u/1373784",
  coolapkMaintainer: "https://www.coolapk.com/u/7602666",
  /** 社区机型预制档：走 Pages，改仓库即可，不必发模块版 */
  devicePresets: "https://eikeitsu.github.io/QSC-Battery/device-presets.json",
  devicePresetsRaw:
    "https://raw.githubusercontent.com/Eikeitsu/QSC-Battery/main/docs/public/device-presets.json",
} as const;

export const DEVICE_PRESETS_URLS = [LINKS.devicePresets, LINKS.devicePresetsRaw] as const;

export const ABOUT_NAV_LINKS = [
  { title: "本仓库", label: "GitHub · Releases", url: LINKS.repo },
  { title: "使用文档", label: "安装、配置与常见问题", url: LINKS.docs },
  { title: "QSC 定量停充", label: "top大佬 · GitHub", url: LINKS.origin },
] as const;

export const CREDITS = [
  { name: "top大佬", role: "原作者", url: LINKS.coolapkAuthor },
  { name: "许小墨", role: "WebUI 维护", url: LINKS.coolapkMaintainer },
] as const;

/** 兼容旧导入名 */
export const DOCS_URL = LINKS.docs;
export const REPO_URL = LINKS.repo;
export const ORIGIN_URL = LINKS.origin;
export const WX_PAY_URL = LINKS.wxPay;
