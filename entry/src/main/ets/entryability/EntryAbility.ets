import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { AnalyticsService, AnalyticsEvent } from '../analytics/AnalyticsService'
import { PrivacyPreferenceService } from '../services/PrivacyPreferenceService'
import notificationManager from '@ohos.notificationManager'
import { ScreenStateService, LOCK_SAFE_DOMAIN, LOCK_SAFE_TAG } from '../services/ScreenStateService'
import { LockSafeStartupCoordinator } from '../services/LockSafeStartupCoordinator'
import { ReminderActionAdapter } from '../services/ReminderActionAdapter'

const DOMAIN = LOCK_SAFE_DOMAIN
const TAG = LOCK_SAFE_TAG

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err))
    }
    // 初始化埋点服务
    AnalyticsService.getInstance().init(this.context as common.UIAbilityContext)
    // 注册通知槽位（支持响铃）
    this.initNotificationSlot()
    // 锁屏安全启动编排：锁屏时跳过预注册，待解锁或前台时补偿
    LockSafeStartupCoordinator.getInstance().orchestrateOnCreate(
      ReminderActionAdapter.wrapPreRegister(this.context as common.UIAbilityContext)
    ).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'orchestrateOnCreate unexpected error: %{public}s', e.message)
    })
    // 订阅屏幕解锁事件驱动补偿
    ScreenStateService.getInstance().subscribeUnlock((isLocked: boolean) => {
      if (!isLocked) {
        LockSafeStartupCoordinator.getInstance().triggerCompensation('SCREEN_UNLOCK').catch((e: Error) => {
          hilog.error(DOMAIN, TAG, 'SCREEN_UNLOCK compensation failed: %{public}s', e.message)
        })
      }
    }).then((ok: boolean) => {
      if (!ok) {
        hilog.warn(DOMAIN, TAG, 'subscribeUnlock failed, degrade to onForeground compensation only')
      }
    })
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate')
  }


  private initNotificationSlot(): void {
    try {
      notificationManager.addSlot(
        notificationManager.SlotType.SOCIAL_COMMUNICATION,
        (err: Error) => {
          if (err) {
            hilog.error(DOMAIN, TAG, 'Failed to add notification slot: %{public}s', JSON.stringify(err))
          } else {
            hilog.info(DOMAIN, TAG, 'Notification slot added successfully')
          }
        }
      )
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'addSlot error: %{public}s', JSON.stringify(err))
    }
  }

  onDestroy(): void {
    AnalyticsService.getInstance().destroy()
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy')
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate')

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
      hilog.error(DOMAIN, TAG, 'consent check failed: %{public}s', JSON.stringify(e))
      needsConsent = true
    }

    if (needsConsent) {
      if (isVersionUpdate) {
        AnalyticsService.getInstance().track(AnalyticsEvent.PRIVACY_VERSION_UPDATE)
      }
      windowStage.loadContent('pages/PrivacyPolicyPage', (err) => {
        if (err.code) {
          hilog.error(DOMAIN, TAG, 'Failed to load privacy page. Cause: %{public}s', JSON.stringify(err))
          return
        }
        hilog.info(DOMAIN, TAG, 'Succeeded in loading privacy page.')
      })
    } else {
      windowStage.loadContent('pages/Index', (err) => {
        if (err.code) {
          hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err))
          return
        }
        hilog.info(DOMAIN, TAG, 'Succeeded in loading the content.')
      })
    }
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy')
  }

  onForeground(): void {
    AnalyticsService.getInstance().onForeground()
    // 前台补偿触发：幂等守卫，多次进入不重复
    LockSafeStartupCoordinator.getInstance().triggerCompensation('FOREGROUND').catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'FOREGROUND compensation failed: %{public}s', e.message)
    })
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onForeground')
  }

  onBackground(): void {
    AnalyticsService.getInstance().onBackground()
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground')
  }
}
