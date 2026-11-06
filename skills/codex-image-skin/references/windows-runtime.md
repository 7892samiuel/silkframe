# Windows 运行说明

本预览版支持 Windows x64、官方 Store/MSIX Codex 和 Owl 运行时。先打开一次原版并登录；使用 Windows PowerShell 5.1 执行脚本。需要 .NET Framework 4.8 和已验证签名的 Node 22+；允许时可下载固定 Node 22.23.1。

## 原版入口

新装后台位于 `%LOCALAPPDATA%\CodexImageSkin`。通过当前用户包激活回调，在初始挂起进程的已有命令行缓冲区中加入回环调试端口，保留协议参数和原始默认资料，不创建第二个浏览器。短目录 junction 指向同一官方程序；路径太长而空间不足时保留原版启动并报错。等待旧的无窗口退出进程有时间上限，不强杀。

注册的任务为 `CodexImageSkin`（皮肤后台）和 `CodexImageSkinLoading`（仅按需加载窗）。模型额度不是后台运行条件。更换 Codex 版本可能影响这些第三方机制，需要真实验证；不承诺所有未来版本或第一帧零闪动。

已有可验证的 Dream Skin 原版入口环境时，Apply 复用它。遇到外部 package callback、不同用户、资料路径或进程身份冲突时保留现状，不覆盖或复制账号资料。原版无参数资料与显式 `--user-data-dir` 可能是不同的存储视图，禁止盲目迁移。

## 加载配置

新装环境可在运行目录写 `loading-preferences.json` 后重新 Apply。允许字段为 `enabled`（布尔值）、`eyebrow`、`primary`、`secondary`、`hintPrimary`、`hintSecondary`、`credit`（每行最多 120 字符，不能有控制字符）。默认仅显示准备状态，没有作品名、角色或署名。配置与图像、配色、焦点一同生成 `loading-config.json`。

独立原生加载窗跨越应用内部的窗口替换；Codex 位于前台或短暂桌面交接时临时置顶，切换到其他应用时释放。使用离屏缓冲和进度条区域刷新。可跳过；20 秒显示超时和总时限确保退场；默认不保存屏幕截图。它不修改认证逻辑或 A/B 原生窗口的生命周期。复用环境的加载配置由原运行时管理，不擅自替换。

## 保存和核验

图片主题保存在 `%LOCALAPPDATA%\CodexImageSkinLibrary`，不依赖聊天附件。Apply 使用 staging、原主题备份和失败恢复。

- `prepared`、`validated`：已保存或校验，未证明当前显示。
- `applied` + `visible`：当前页面通过实时验证。
- `installed-hidden`：已安装但窗口隐藏或最小化。
- `saved-awaiting-launch/reopen`：选择已保存，当前没有已准备的通道；保留应用，等待正常重开。
- `persistence.configured=true`：后台及回调匹配，不等于已完成冷启动实测。

Pause 暂停并移除样式；Resume 恢复选择；Disable 仅注销本技能拥有的回调和任务，保留文件并等待应用正常退出关闭调试端口。复用其他产品时用 Pause，完整卸载交给原产品。删除 skill 文件夹不等于停用后台。

公开运行时的新装路径尚需干净 Windows 用户完整验收。编译、参数 fixture、渲染、退出与恢复的组件测试不能替代整机验收。旧的本技能桥接运行时须先停用再迁移，不静默升级。

## 来源

`assets/engine` 来自 Codex Dream Skin 1.5.21 的最小运行时副本，保留 MIT LICENSE。逐文件哈希和局部修改见 `assets/engine-files.json`。源码地址：https://github.com/Fei-Away/Codex-Dream-Skin

未捆绑示例有珠背景、个人资料、账号、聊天或诊断日志。
