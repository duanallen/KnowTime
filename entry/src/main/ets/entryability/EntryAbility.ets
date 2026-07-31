import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { AnalyticsService } from '../analytics/AnalyticsService'

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
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate')
  }

  onDestroy(): void {
    AnalyticsService.getInstance().destroy()
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy')
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate')
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err))
        return
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.')
    })
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
