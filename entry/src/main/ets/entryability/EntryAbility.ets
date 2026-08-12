import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { AnalyticsService, AnalyticsEvent } from '../analytics/AnalyticsService'
import { PrivacyPreferenceService } from '../services/PrivacyPreferenceService'
import notificationManager from '@ohos.notificationManager'
import reminderAgentManager from '@ohos.reminderAgentManager'

const DOMAIN = 0x0000

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err))
    }
    // 初始化埋点服务
    AnalyticsService.getInstance().init(this.context as common.UIAbilityContext)
    // 注册通知槽位（支持响铃）
    this.initNotificationSlot()
    // 注册系统提醒槽位（手表等设备上也能震动+响铃1分钟）
    this.initSystemReminderSlot()
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate')
  }

  private initSystemReminderSlot(): void {
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
      } as reminderAgentManager.ReminderRequestTimer).then((id: number) => {
        reminderAgentManager.cancelReminder(id).catch((e: Error) => {
          hilog.error(DOMAIN, 'testTag', 'cleanup reminder failed: %{public}s', e.message)
        })
      }).catch((e: Error) => {
        hilog.error(DOMAIN, 'testTag', 'reminder slot test failed: %{public}s', e.message)
      })
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'initSystemReminderSlot error: %{public}s', (err as Error).message)
    }
  }

  private initNotificationSlot(): void {
    try {
      notificationManager.addSlot(
        notificationManager.SlotType.SOCIAL_COMMUNICATION,
        (err: Error) => {
          if (err) {
            hilog.error(DOMAIN, 'testTag', 'Failed to add notification slot: %{public}s', JSON.stringify(err))
          } else {
            hilog.info(DOMAIN, 'testTag', 'Notification slot added successfully')
          }
        }
      )
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'addSlot error: %{public}s', JSON.stringify(err))
    }
  }

  onDestroy(): void {
    AnalyticsService.getInstance().destroy()
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy')
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate')

    const context = this.context as common.UIAbilityContext
    let needsConsent = true
    let isVersionUpdate = false

    try {
      const state = await PrivacyPreferenceService.getInstance().getConsentState(context)
      if (state.isAgreed) {
        needsConsent = await PrivacyPreferenceService.getInstance().needsReconsent(context, '1.0')
        if (needsConsent) {
          isVersionUpdate = true
        }
      }
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'consent check failed: %{public}s', JSON.stringify(e))
      needsConsent = true
    }

    if (needsConsent) {
      if (isVersionUpdate) {
        AnalyticsService.getInstance().track(AnalyticsEvent.PRIVACY_VERSION_UPDATE)
      }
      windowStage.loadContent('pages/PrivacyPolicyPage', (err) => {
        if (err.code) {
          hilog.error(DOMAIN, 'testTag', 'Failed to load privacy page. Cause: %{public}s', JSON.stringify(err))
          return
        }
        hilog.info(DOMAIN, 'testTag', 'Succeeded in loading privacy page.')
      })
    } else {
      windowStage.loadContent('pages/Index', (err) => {
        if (err.code) {
          hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err))
          return
        }
        hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.')
      })
    }
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy')
  }

  onForeground(): void {
    AnalyticsService.getInstance().onForeground()
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground')
  }

  onBackground(): void {
    AnalyticsService.getInstance().onBackground()
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground')
  }
}
