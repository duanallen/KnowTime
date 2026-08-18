import { router, promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppInfoService, AppInfo } from '../services/AppInfoService'
import { AnalyticsService, AnalyticsEvent } from '../analytics/AnalyticsService'

const TAG = 'AboutPage'
const DOMAIN = 0x0007

@Entry
@Component
struct AboutPage {
  @State appName: string = '知时'
  @State vendor: string = 'knowtime'
  @State versionName: string = ''
  @State appSlogan: string = '时间感知型深度专注助手'
  @State marketStatusText: string = '本应用已上架华为应用市场'
  @State contactEmail: string = 'support@knowtime.com'
  @State vendorStatement: string = '应用由 knowtime 开发'
  @State loadFailed: boolean = false
  @State versionDisplay: string = ''
  private pageViewEnded: boolean = false

  async aboutToAppear(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext
    try {
      const info: AppInfo = await AppInfoService.getAppInfo(context)
      this.appName = info.appName
      this.vendor = info.vendor
      this.appSlogan = info.appSlogan
      this.marketStatusText = info.marketStatusText
      this.contactEmail = info.contactEmail
      this.vendorStatement = info.vendorStatement
      if (info.versionName && info.versionName.length > 0) {
        const prefix = await this.safeGetString(context, 'about_version_prefix', '版本 ')
        this.versionDisplay = `${prefix}${info.versionName}`
      } else {
        this.versionDisplay = await this.safeGetString(context, 'about_version_unknown', '版本未知')
      }
      this.loadFailed = false
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'aboutToAppear load failed: %{public}s', JSON.stringify(e))
      this.loadFailed = true
    }

    AnalyticsService.getInstance().track(AnalyticsEvent.ABOUT_VIEW)
    AnalyticsService.getInstance().startPageView('AboutPage')
  }

  aboutToDisappear(): void {
    if (!this.pageViewEnded) {
      AnalyticsService.getInstance().endPageView('AboutPage')
      this.pageViewEnded = true
    }
  }

  private async safeGetString(context: common.UIAbilityContext, name: string, fallback: string): Promise<string> {
    try {
      return await context.resourceManager.getStringByName(name)
    } catch (e) {
      return fallback
    }
  }

  onBack(): void {
    if (!this.pageViewEnded) {
      AnalyticsService.getInstance().endPageView('AboutPage')
      this.pageViewEnded = true
    }
    router.back()
  }

  async onJumpPrivacy(): Promise<void> {
    AnalyticsService.getInstance().track(AnalyticsEvent.ABOUT_OPEN_PRIVACY)
    try {
      const routeParams: Record<string, string> = {}
      routeParams['displayMode'] = 'view'
      await router.pushUrl({ url: 'pages/PrivacyPolicyPage', params: routeParams })
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'jump privacy failed: %{public}s', JSON.stringify(e))
      const context = getContext(this) as common.UIAbilityContext
      const msg = await this.safeGetString(context, 'about_open_failed', '页面打开失败，请稍后重试')
      promptAction.showToast({ message: msg })
    }
  }

  async onJumpFeedback(): Promise<void> {
    AnalyticsService.getInstance().track(AnalyticsEvent.ABOUT_OPEN_FEEDBACK)
    const context = getContext(this) as common.UIAbilityContext
    try {
      const info: AppInfo = await AppInfoService.getAppInfo(context)
      if (info.feedbackPageUrl && info.feedbackPageUrl.length > 0) {
        await router.pushUrl({ url: info.feedbackPageUrl })
      } else {
        throw new Error('Feedback page URL not available')
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'jump feedback failed: %{public}s', JSON.stringify(e))
      const msg = await this.safeGetString(context, 'about_feedback_unavailable', '功能暂不可用，请稍后重试')
      promptAction.showToast({ message: msg })
    }
  }

  build() {
    Column() {
      this.TopBar()
      this.ContentArea()
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.about_page_bg'))
  }

  @Builder
  TopBar() {
    Row() {
      Text('返回')
        .fontSize(16)
        .fontColor($r('app.color.about_text_secondary'))
        .onClick(() => {
          this.onBack()
        })

      Text($r('app.string.about_page_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.about_text_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.Center)

      Text('').width(40)
    }
    .width('100%').height(56)
    .padding({ left: 16, right: 16 })
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  ContentArea() {
    Scroll() {
      Column({ space: 16 }) {
        this.InfoSection()
        this.EntrySection()
        Blank().height(20)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 40 })
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
  }

  @Builder
  InfoSection() {
    Column({ space: 12 }) {
      Column({ space: 8 }) {
        Image($r('app.media.layered_image'))
          .width(72).height(72)
          .borderRadius(16)
          .objectFit(ImageFit.Contain)

        Text(this.appName)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.about_text_primary'))

        Text(this.appSlogan)
          .fontSize(13)
          .fontColor($r('app.color.about_text_secondary'))
      }
      .width('100%')
      .padding({ top: 20, bottom: 16 })

      if (this.versionDisplay.length > 0) {
        Text(this.versionDisplay)
          .fontSize(13)
          .fontColor($r('app.color.about_text_hint'))
      }

      Column({ space: 8 }) {
        Text(this.vendorStatement)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.about_vendor_highlight'))

        Text(this.marketStatusText)
          .fontSize(13)
          .fontColor($r('app.color.about_text_secondary'))

        Text(this.contactEmail)
          .fontSize(13)
          .fontColor($r('app.color.about_text_secondary'))
      }
      .width('100%')
      .padding({ top: 12, bottom: 16 })
    }
    .width('100%')
    .backgroundColor($r('app.color.about_card_bg'))
    .borderRadius(16)
    .padding({ left: 16, right: 16 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  EntrySection() {
    Column() {
      Row() {
        Text($r('app.string.about_entry_privacy'))
          .fontSize(15)
          .fontColor($r('app.color.about_text_primary'))
          .layoutWeight(1)
        Text('>')
          .fontSize(16)
          .fontColor($r('app.color.about_text_hint'))
      }
      .width('100%').height(52).padding({ left: 16, right: 12 })
      .onClick(() => {
        this.onJumpPrivacy()
      })
      .border({ width: { bottom: 0.5 }, color: $r('app.color.about_border') })

      Row() {
        Text($r('app.string.about_entry_feedback'))
          .fontSize(15)
          .fontColor($r('app.color.about_text_primary'))
          .layoutWeight(1)
        Text('>')
          .fontSize(16)
          .fontColor($r('app.color.about_text_hint'))
      }
      .width('100%').height(52).padding({ left: 16, right: 12 })
      .onClick(() => {
        this.onJumpFeedback()
      })
    }
    .width('100%')
    .backgroundColor($r('app.color.about_card_bg'))
    .borderRadius(16)
  }
}