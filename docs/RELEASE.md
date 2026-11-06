# 发布准备

目标版本：`0.2.0-preview.1`。仓库说明与展示素材已准备；本文件记录发布验证的实际范围。

本机演示对应的 Codex 版本为 `26.1103.3517.0`。已通过通用运行时编译、主题生成与引擎校验、参数保留与容量不足拒绝、缓冲绘制、窗口交接及可移植性检查。GitHub Windows CI 已通过编译、无界面组件检查与打包，见 [运行记录](https://github.com/7892samiuel/silkframe/actions/runs/42266581755)；原生窗口 fixture 在本机通过，CI 不运行窗口 fixture。

本地验证摘要见 [validation.json](validation.json)。完整输出由检查脚本写入被 Git 忽略的 `.validation` 目录，避免把本机路径和运行状态放进公开仓库。

## 核对方式

```powershell
.\scripts\Test-Release.ps1
.\scripts\Build-Release.ps1
```

检查覆盖脚本语法、运行时编译、主题生成与校验、原生命令行参数保留、加载画面渲染与窗口交接，以及归档范围。

自动检查不安装或重启当前用户的 Codex，也不注册真实启动回调。状态检查可以只读访问当前安装。

## 发布前人工验收

- [ ] 在没有现有换肤后台的 Windows 用户中首次安装。
- [ ] 正常退出托盘，从原版入口重开，确认单实例及自动恢复。
- [ ] 换成另一张图片，确认背景与加载画面均更新。
- [ ] 暂停、恢复、停用后确认行为符合说明。
- [ ] 确认异常与不支持的应用版本保留原版启动。

当前截图和视频来自本机的已实测主题。通用版的代码检查与独立组件验证不能替代上述整机验收。通过后再把发行状态从预览调整为稳定版。

## GitHub 材料

项目名称：`Silkframe`。仓库：`7892samiuel/silkframe`。

简介：`Persistent image skins for Codex on Windows. Original app entry, startup-aware loading, local automatic restore.`

建议 topics：`codex`、`agent-skills`、`windows`、`customization`、`themes`。

Release 标题：`Silkframe v0.2.0-preview.1`，勾选 Pre-release。将构建出的 skill ZIP 和 SHA-256 校验文件作为附件；不上传本机状态、账号资料、日志、旧诊断视频或编译缓存。
