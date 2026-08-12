import { defineConfig } from "vitepress";

const repoName =
  process.env.VITEPRESS_BASE?.replace(/^\//, "").replace(/\/$/, "") || "QSC-Battery";

export default defineConfig({
  title: "充电控制",
  description: "电量/温度停充与可选电流控制的 Magisk 模块（原 QSC 定量停充 WebUI 版）",
  base: `/${repoName}/`,
  lang: "zh-CN",
  head: [
    ["link", { rel: "icon", type: "image/png", href: `/${repoName}/icon.png` }],
    [
      "link",
      {
        rel: "apple-touch-icon",
        href: `/${repoName}/icon.png`,
      },
    ],
  ],
  themeConfig: {
    logo: "/icon.png",
    siteTitle: "充电控制",
    nav: [
      { text: "首页", link: "/" },
      { text: "功能介绍", link: "/guide/features" },
      { text: "安装", link: "/guide/install" },
      { text: "配置说明", link: "/guide/config" },
      { text: "WebUI", link: "/guide/webui" },
      { text: "更新日志", link: "/guide/changelog" },
    ],
    sidebar: [
      {
        text: "使用指南",
        items: [
          { text: "功能介绍", link: "/guide/features" },
          { text: "安装与升级", link: "/guide/install" },
          { text: "配置说明", link: "/guide/config" },
          { text: "WebUI 使用说明", link: "/guide/webui" },
          { text: "更新日志", link: "/guide/changelog" },
          { text: "常见问题", link: "/guide/faq" },
          { text: "致谢", link: "/guide/credits" },
        ],
      },
    ],
    socialLinks: [
      {
        icon: "github",
        link: "https://github.com/Eikeitsu/QSC-Battery",
      },
    ],
    footer: {
      message: "基于 top大佬 原作 QSC 定量停充 · 模块显示名：充电控制",
      copyright: "WebUI 版由许小墨维护",
    },
  },
});
