# 实现与配置

## 启动

Skill 负责图片处理、主题选择与操作；跨启动能力由本机后台完成，不依赖模型额度。

新版后台在 Windows 激活官方包时校验用户、会话、映像、初始线程和当前包。只在原始命令行的已有空间内加入本地调试端口，保留协议参数和原始默认资料，不再另起一个浏览器。短路径通过本项目管理的目录 junction 指向同一官方程序；空间不足时保留原始启动并记录失败。

皮肤后台核验回环监听进程和浏览器 GUID 后，通过 CDP 应用样式。应用更新、包类型变化或既有回调冲突会触发保留与报错，不通过强杀、复制资料或修改官方文件来修复。

此实现使用 Windows 进程参数与包调试接口，并非官方背景设置 API。该兼容性边界需要在后续版本维护。

## 加载画面

独立加载窗跟随主窗口，跨越应用内部的窗口替换；主题就绪后退出。只在 Codex 位于前台或短暂桌面交接期间临时置顶，切换其他应用后恢复普通层级。绘制采用可复用离屏缓冲，动画只刷新进度条区域。

可跳过；显示超过 20 秒自动退场，总生命周期也有上限。它改善视觉交接，不改变应用内部认证流程，也不承诺所有机器第一帧零闪动。

新装运行时的配置位于 `%LOCALAPPDATA%\CodexImageSkin`。在其中创建 `loading-preferences.json`，然后重新应用当前主题：

```json
{
  "enabled": true,
  "eyebrow": "",
  "primary": "正在准备界面",
  "secondary": "",
  "hintPrimary": "完成后将自动进入 Codex",
  "hintSecondary": "",
  "credit": ""
}
```

每行最多 120 个字符，可用两行分别放中文和日文。`credit` 可填写自己的署名；关闭加载窗使用 `enabled: false`。图片、配色、焦点与当前主题同步。默认不保存屏幕截图，不附带固定角色或标语。

## 文件位置

| 内容 | 位置 |
| --- | --- |
| 持久图片与主题库 | `%LOCALAPPDATA%\CodexImageSkinLibrary` |
| 新装后台及当前主题 | `%LOCALAPPDATA%\CodexImageSkin` |
| 复用的既有主题 | `%LOCALAPPDATA%\CodexDreamSkin` |
| 新装后台任务 | `CodexImageSkin`、`CodexImageSkinLoading` |

当前主题替换采用 staging 和备份；注入失败会恢复旧主题并尝试重新挂回。`visible` 与 `installed-hidden` 分开报告。任务存在只说明配置存在，实际恢复需要真实退出重开验证。
