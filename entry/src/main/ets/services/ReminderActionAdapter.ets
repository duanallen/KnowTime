import { common } from '@kit.AbilityKit'
import reminderAgentManager from '@ohos.reminderAgentManager'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { ReminderAction } from './LockSafeStartupCoordinator'

const DOMAIN = 0x0040
const TAG = 'LockSafeStartup'

export class ReminderActionAdapter {
  static wrapPreRegister(context: common.UIAbilityContext): ReminderAction {
    return async (): Promise<void> => {
      const id: number = await new Promise<number>((resolve, reject) => {
        let retryCount: number = 0
        const tryPublish = () => {
          try {
            reminderAgentManager.publishReminder({
              reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER,
              triggerTimeInSeconds: 1,
              ringDuration: 60,
              title: '知时',
              content: '专注已完成，需要停止提醒吗？',
              expiredContent: '',
              snoozeTimes: 0,
              ringChannel: reminderAgentManager.RingChannel.RING_CHANNEL_ALARM,
              actionButton: [
                { title: '停止提醒', type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE }
              ]
            } as reminderAgentManager.ReminderRequestTimer).then((reminderId: number) => {
              resolve(reminderId)
            }).catch((e: BusinessError) => {
              const errCode = e.code
              // 提醒数量超限(1700002)：清空残留提醒后最多重试一次，避免无限循环
              if (errCode === 1700002 && retryCount === 0) {
                retryCount++
                hilog.warn(DOMAIN, TAG, 'publishReminder limit exceeded, cancelAllReminders and retry once')
                reminderAgentManager.cancelAllReminders().then(() => {
                  tryPublish()
                }).catch((cancelErr: Error) => {
                  reject(cancelErr)
                })
                return
              }
              reject(e)
            })
          } catch (err) {
            reject(err as Error)
          }
        }
        tryPublish()
      })

      try {
        await reminderAgentManager.cancelReminder(id)
      } catch (e) {
        // cancel 失败不阻断流程，提醒已发布可正常工作
      }
    }
  }
}