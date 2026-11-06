# 安装与恢复

## 安装 skill

在下载后的仓库目录按 README 的 PowerShell 命令运行 `scripts/Install-Skill.ps1`，它只复制 skill，不启动换肤后台。该命令只为这次进程设置执行策略，不修改系统策略。默认位置为用户目录下的 `.agents/skills/codex-image-skin`；已有同名目录时保留原目录并报错。不要同时安装到多个技能发现目录。

也可以手动复制 `skills/codex-image-skin` 到自己的技能目录。Codex 的目录规则见 [OpenAI 官方说明](https://learn.chatgpt.com/docs/build-skills#where-codex-loads-local-skills)。

## 第一次使用

先正常打开官方 Codex 并完成登录，再给 Codex 一张 PNG/JPEG 图片并调用 `$codex-image-skin`。脚本会检查 Windows、当前包、现有资料和运行依赖。

第一次配置需要编译并保存用户级后台、注册两个本项目任务及包启动回调。一个任务维护皮肤，另一个仅在应用启动时按需显示加载画面。无需修改系统 ACL 或以管理员身份运行。

需要 Windows PowerShell 5.1、.NET Framework 4.8 和经过签名验证的 Node 22+。缺少 Node 时，可由安装脚本下载固定版本并校验哈希和签名。下载发生在首次安装，不是每次启动。

如果当前窗口启动时没有准备调试通道，选择会保存为 `saved-awaiting-reopen`。正常退出 Codex（含托盘）后，从原版图标重新打开即可；脚本不会为了换图强行结束应用。

## 常用操作

让 Codex 调用 skill 并说明“换这张图”“暂停皮肤”“恢复皮肤”或“停用自动换肤”。也可在 skill 目录手动运行：

```powershell
.\scripts\Manage-Skin.ps1 -Action Doctor
.\scripts\Manage-Skin.ps1 -Action Status
.\scripts\Manage-Skin.ps1 -Action Pause
.\scripts\Manage-Skin.ps1 -Action Resume
.\scripts\Manage-Skin.ps1 -Action Disable
```

`Pause` 移除当前样式并阻止自动应用；`Resume` 恢复已保存的选择。`Disable` 注销本项目拥有的启动回调、停用本项目任务并保留主题和诊断文件。调试端口会随应用正常退出关闭；停用不会伪造端口已关闭。

删除 skill 文件夹只移除技能说明，不等于停用已经安装的后台。需要彻底停止自动换肤时先执行 `Disable`，再正常退出 Codex。

## 现有换肤环境

有已验证的 Dream Skin 原版入口环境时，skill 复用其主题引擎；不会覆盖其他程序的启动回调，也不另装一个控制器。复用模式下 `Pause` 可用，完整停用请使用原安装程序。加载窗的配置也由原运行时管理。

早期版本的旧启动机制不会被静默升级。先用旧版本停用自己的后台，再按新版流程安装。原版界面、账号和聊天资料不应迁移或复制。
