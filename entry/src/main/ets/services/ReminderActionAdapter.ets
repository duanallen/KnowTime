import { common } from '@kit.AbilityKit'
import reminderAgentManager from '@ohos.reminderAgentManager'
import { ReminderAction } from './LockSafeStartupCoordinator'

export class ReminderActionAdapter {
  static wrapPreRegister(context: common.UIAbilityContext): ReminderAction {
    return async (): Promise<void> => {
      const id: number = await new Promise<number>((resolve, reject) => {
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
          }).catch((e: Error) => {
            reject(e)
          })
        } catch (err) {
          reject(err as Error)
        }
      })

      try {
        await reminderAgentManager.cancelReminder(id)
      } catch (e) {
        // cancel 失败不阻断流程，提醒已发布可正常工作
      }
    }
  }
}