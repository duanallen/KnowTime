import { AbilityConstant, Configuration, UIAbility, Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { AnalyticsService, AnalyticsEvent } from '../analytics/AnalyticsService'
import { PrivacyPreferenceService } from '../services/PrivacyPreferenceService'
import notificationManager from '@ohos.notificationManager'
import { ScreenStateService, LOCK_SAFE_DOMAIN, LOCK_SAFE_TAG } from '../services/ScreenStateService'
import { LockSafeStartupCoordinator } from '../services/LockSafeStartupCoordinator'
import { ReminderActionAdapter } from '../services/ReminderActionAdapter'
import { ThemeService } from '../services/ThemeService'
import { WhiteNoiseService } from '../services/WhiteNoiseService'

const DOMAIN = LOCK_SAFE_DOMAIN
const TAG = LOCK_SAFE_TAG

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 初始化主题服务：读取 theme_mode 偏好并应用深浅色（以 ThemeService 为准）
    ThemeService.getInstance().init(this.context as common.UIAbilityContext).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'ThemeService init failed: %{public}s', e.message)
    })
    // 初始化埋点服务
    AnalyticsService.getInstance().init(this.context as common.UIAbilityContext)
    // 注册通知槽位（支持响铃）
    this.initNotificationSlot()
    // 主动请求通知权限（提醒服务依赖通知，isNotificationEnabled 在部分设备上不可靠，直接请求）
    this.requestNotificationPermission()
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

    // 桌面卡片一键开始专注：冷启动时读取 want 中的标记
    this.handleLaunchWant(want)
  }

  /** 应用已在前台/后台时点击卡片路由到本 Ability，走 onNewWant */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onNewWant')
    this.handleLaunchWant(want)
  }

  /** 解析启动 want 中的一键开始专注标记，写入全局令牌供页面消费 */
  private handleLaunchWant(want: Want): void {
    try {
      const params: Record<string, Object> | undefined = want.parameters
      if (!params) {
        return
      }
      const raw: Object | undefined = params['autoStartFocus']
      if (raw === undefined) {
        return
      }
      const flag: string = String(raw)
      if (flag === 'true') {
        const token: number = Date.now()
        AppStorage.setOrCreate<number>('autoStartToken', token)
        hilog.info(DOMAIN, TAG, 'autoStartFocus detected, token=%{public}d', token)
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'handleLaunchWant failed: %{public}s', (e as Error).message)
    }
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

  /** 主动请求通知权限，reminderAgentManager 依赖通知通道才能响铃 */
  private requestNotificationPermission(): void {
    try {
      notificationManager.requestEnableNotification(this.context as common.UIAbilityContext).then(() => {
        hilog.info(DOMAIN, TAG, 'requestEnableNotification succeeded')
      }).catch((e: Error) => {
        hilog.warn(DOMAIN, TAG, 'requestEnableNotification rejected: %{public}s', e.message)
      })
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'requestNotificationPermission error: %{public}s', (err as Error).message)
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
    // 兜底：应用退后台立即停止白噪音（仅承诺前台专注中播放，无后台保活）
    WhiteNoiseService.getInstance().stop()
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground')
  }

  /** 系统配置变化（深浅色等）：跟随系统模式下重新解析主题 */
  onConfigurationUpdate(newConfig: Configuration): void {
    ThemeService.getInstance().onSystemConfigChange(this.context as common.UIAbilityContext)
  }
}
