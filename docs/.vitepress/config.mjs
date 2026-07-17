import { defineConfig } from 'vitepress';

const repoName =
  process.env.VITEPRESS_BASE?.replace(/^\//, '').replace(/\/$/, '') ||
  'QSC-Battery';

export default defineConfig({
  title: 'QSC 定量停充',
  description: '到达指定电量 / 温度自动停充与恢复的 Magisk 模块',
  base: `/${repoName}/`,
  lang: 'zh-CN',
  themeConfig: {
    nav: [
      { text: '首页', link: '/' },
      { text: '功能介绍', link: '/guide/features' },
      { text: '安装', link: '/guide/install' },
      { text: '配置说明', link: '/guide/config' }
    ],
    sidebar: [
      {
        text: '使用指南',
        items: [
          { text: '功能介绍', link: '/guide/features' },
          { text: '安装与升级', link: '/guide/install' },
          { text: '配置说明', link: '/guide/config' },
          { text: '常见问题', link: '/guide/faq' },
          { text: '致谢', link: '/guide/credits' }
        ]
      }
    ],
    socialLinks: [
      {
        icon: 'github',
        link: 'https://github.com/Eikeitsu/QSC-Battery'
      }
    ],
    footer: {
      message: '基于 top大佬 原作 QSC 定量停充',
      copyright: 'WebUI 版由许小墨维护'
    }
  }
});
