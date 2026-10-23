# debug-offscreen-alarm-miss

## 现象
设置 3 分钟专注 → 熄屏 → 到点无响铃、无震动（此前 25 分钟同样无响应；历史版本 3 分钟曾晚 8~13 秒响）。

## 假设与证据
| ID | 假设 | 观测点 | 结论 |
|----|------|--------|------|
| H1 | 通知权限被关闭，系统提醒被 `ReminderControl` 拦截，且进程被杀后无任何响铃通道 | hilog `ReminderControl ... notification not allowed` | CONFIRMED（历史设备日志） |
| H2 | `AUDIO_PLAYBACK` 长时任务因未使用 AVSession/音频未真正运行被系统取消，进程随后被冻结/杀死 | SDK `ContinuousTaskCancelReason.SYSTEM_CANCEL_AUDIO_PLAYBACK_NOT_USE_AVSESSION=5` / `NOT_RUNNING=6`；设备日志无法复采 | INCONCLUSIVE（API 契约证据） |
| H3 | `completeSession()` 无条件 `cancelEndReminder()`，把唯一可靠的系统闹钟取消，随后应用进程被冻结 → 完全不响 | 源码调用链 | CONFIRMED（确定性代码路径） |
| H4 | 静音 AVPlayer(volume=0) 保活不可行，反而引入音频会话/复杂度风险 | 无 runtime 日志（无法从命令行安装签名包） | INCONCLUSIVE |
| H5 | 设备闹钟音量/震动开关被关闭导致静音 | 系统设置 | INCONCLUSIVE（需用户侧确认） |

## 证据采集状态
- `progress_status: blocked`（命令行无法签名安装，必须由 DevEco Studio Run 后复现）
- 证据通道：hilog（项目既有日志），关键 TAG：`FocusVM`
- 待采集日志：
  - `notification enabled` / `notification disabled, request enable from user`
  - `end reminder pre-registered id=... atMs=...`
  - `page visible=false`
  - `session completed while hidden, keep system reminder`

## 修复方案
1. 系统提醒（reminderAgentManager CALENDAR 绝对时刻 + ALARM 通道，ringDuration 60s）作为熄屏后的唯一主触发，不依赖应用进程。
2. 开始专注前检查并请求通知权限（`requestEnableNotification`），未开启时 Toast 提示。
3. 移除无法被系统认可的 AUDIO_PLAYBACK 长时任务与静音 AVPlayer 保活。
4. 页面不可见时不再取消系统闹钟；仅前台到点才取消并播放自定义铃声（闹钟留 1 秒余量防双响）。
5. 保留 250ms 计时轮询，前台到点误差 ≤0.25s。

## 待验证
- 用户 Run 安装 → 允许通知 → 3 分钟熄屏 → 检查是否到点响铃+震动，并采集上述日志。
