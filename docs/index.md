---
layout: home
hero:
  name: 充电控制
  text: 管好充电，少伤电池
  tagline: Magisk / KernelSU 模块 · 电量与温度停充 · 可选电流控制 · 事件驱动省电 · WebUI 与伴侣 APP
  image:
    src: /icon-mark-light.png
    alt: 充电控制
  actions:
    - theme: brand
      text: 功能介绍
      link: /guide/features
    - theme: alt
      text: 安装模块
      link: /guide/install
features:
  - title: 停充策略
    details: 电量阈值、温度保护、时段与 App 停充；无线策略可单独忽略部分触发条件。
  - title: 电流控制
    details: 安装时可选。模拟旁路、硬件旁路节点、慢充、温控阶梯限流与游戏限流，默认关闭。
  - title: 省电主循环
    details: power_saver + 可选 qscd 事件守护；未插电跳过整轮停充脚本，插拔即时响应。
  - title: WebUI · APP · CLI
    details: 模块内 WebUI、Compose 伴侣 APP、qsc.sh 命令行，按需选用。
---
