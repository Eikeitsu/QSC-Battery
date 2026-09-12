import { defineConfig } from "vitepress";

const repoName =
  process.env.VITEPRESS_BASE?.replace(/^\//, "").replace(/\/$/, "") || "QSC-Battery";

export default defineConfig({
  title: "充电控制",
  description:
    "Magisk / KernelSU 充电管理：电量与温度停充、可选电流控制、事件驱动省电、WebUI 与伴侣 APP",
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
      { text: "功能", link: "/guide/features" },
      { text: "安装", link: "/guide/install" },
      { text: "配置", link: "/guide/config" },
      { text: "WebUI", link: "/guide/webui" },
      { text: "APP", link: "/guide/app" },
      { text: "更新日志", link: "/guide/changelog" },
    ],
    sidebar: [
      {
        text: "开始使用",
        items: [
          { text: "功能介绍", link: "/guide/features" },
          { text: "安装与升级", link: "/guide/install" },
          { text: "配置说明", link: "/guide/config" },
          { text: "常见问题", link: "/guide/faq" },
        ],
      },
      {
        text: "界面与工具",
        items: [
          { text: "WebUI", link: "/guide/webui" },
          { text: "伴侣 APP", link: "/guide/app" },
          { text: "命令行 CLI", link: "/guide/cli" },
        ],
      },
      {
        text: "其它",
        items: [
          { text: "更新日志", link: "/guide/changelog" },
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
      message: "充电控制 · QSC_Battery · Magisk / KernelSU",
      copyright: "由许小墨维护",
    },
    search: {
      provider: "local",
    },
  },
});
