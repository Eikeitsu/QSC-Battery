# 发版与更新日志（给维护者 / AI）

> 编码改功能或修 bug 时：**先写 `changelog.md` 的 `## Unreleased`**，再改代码。  
> 用户可见的文档站日志在发版时自动生成，**不含 Unreleased**。

## 日志写哪里

| 文件 | 用途 |
| --- | --- |
| 仓库根目录 `changelog.md` | **唯一手写源**。开发中把条目写在 `## Unreleased` 下 |
| `docs/guide/changelog.md` | 文档站「更新日志」页；**发版工作流生成**，勿手写 Unreleased |
| `docs/public/changelog.md` | Pages / `updateJson` 指向的 changelog；**发版工作流生成**，勿手写 Unreleased |

### Unreleased 写法

```markdown
## Unreleased

- 用一两句说清用户能感知的变化（修了什么 / 新增什么）
- 一条一个要点
```

- 发版前保持 `## Unreleased` 在文件最上方（标题 `# 更新日志` 之后）。  
- 空的 stub 可以保留。  
- 版本号格式与本仓库一致：`## 2026.07.25` 或 `## 2026.07.25.2`（由发版工作流写入，开发中只维护 Unreleased）。

## 发版时工作流做什么

Actions → **Release Module**（或推送 `v*` tag）：

1. 打包模块 zip，创建 GitHub Release（正文优先取当前版本节；没有则回退 Unreleased）  
2. `promote-changelog.py <version>`：非空 `Unreleased` → 当前日期版本号，并留下空 stub  
3. `promote-changelog.py --export-docs`：文档站两份 changelog **去掉 Unreleased**  
4. 更新 `update.json` / `module.prop` 等，提交并触发文档构建  

## 本地命令（可选）

```bash
python3 tooling/scripts/promote-changelog.py 2026.07.25 changelog.md

python3 tooling/scripts/promote-changelog.py --export-docs changelog.md \
  docs/guide/changelog.md docs/public/changelog.md
```

## AI / 协作者检查清单

1. 有用户可见改动 → `changelog.md` → `## Unreleased` 追加 bullet  
2. 不要把 Unreleased 写进 `docs/**/changelog.md`  
3. 不要删空的 `## Unreleased` stub  
4. 发版用工作流，勿漏同步文档站两份日志  

相关脚本：`tooling/scripts/promote-changelog.py`、`tooling/scripts/prepare-release-notes.py`。  
构建细节见 [`BUILD.md`](./BUILD.md)。
