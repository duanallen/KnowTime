import { router, promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { PrivacyPreferenceService, DisplayMode } from '../services/PrivacyPreferenceService'
import { PrivacyPolicyContent, PolicyMeta } from '../services/PrivacyPolicyContent'
import { AnalyticsService, AnalyticsEvent } from '../analytics/AnalyticsService'

interface PrivacyRouteParams {
  displayMode: string
}

@Entry
@Component
struct PrivacyPolicyPage {
  @State displayMode: string = 'first_launch'
  @State policyText: string = ''
  @State policyVersion: string = ''
  @State updateDate: string = ''
  @State loadFailed: boolean = false
  @State isAgreeButtonDisabled: boolean = false
  private pageViewEnded: boolean = false

  aboutToAppear(): void {
    const params = router.getParams() as PrivacyRouteParams
    if (params && params.displayMode) {
      this.displayMode = params.displayMode
    }

    const context = getContext(this) as common.UIAbilityContext

    PrivacyPolicyContent.loadPolicyText(context).then((text: string) => {
      if (text.startsWith('隐私政策内容加载失败')) {
        this.loadFailed = true
        this.policyText = text
      } else {
        this.policyText = text
        this.loadFailed = false
      }
    }).catch((e: Error) => {
      this.loadFailed = true
    })

    PrivacyPolicyContent.getPolicyMeta(context).then((meta: PolicyMeta) => {
      this.policyVersion = meta.version
      this.updateDate = meta.updateDate
    })

    if (this.displayMode === DisplayMode.VIEW) {
      AnalyticsService.getInstance().track(AnalyticsEvent.PRIVACY_VIEW)
      AnalyticsService.getInstance().startPageView('PrivacyPolicyPage')
    }
  }

  aboutToDisappear(): void {
    if (this.displayMode === DisplayMode.VIEW && !this.pageViewEnded) {
      AnalyticsService.getInstance().endPageView('PrivacyPolicyPage')
      this.pageViewEnded = true
    }
  }

  build() {
    Column() {
      this.TopBar()
      this.ContentArea()
      if (this.displayMode === DisplayMode.FIRST_LAUNCH) {
        this.BottomActionBar()
      }
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.privacy_page_bg'))
  }

  @Builder
  TopBar() {
    Row() {
      if (this.displayMode === DisplayMode.VIEW) {
        Text('返回')
          .fontSize(16)
          .fontColor($r('app.color.privacy_text_secondary'))
          .onClick(() => {
            AnalyticsService.getInstance().endPageView('PrivacyPolicyPage')
            this.pageViewEnded = true
            router.back()
          })
      } else {
        Text('').width(40)
      }

      Text('隐私政策')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.privacy_text_primary'))
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
      Column() {
        if (!this.loadFailed && this.policyVersion.length > 0) {
          Row({ space: 8 }) {
            Text('V' + this.policyVersion)
              .fontSize(13)
              .fontColor($r('app.color.privacy_text_secondary'))
            Text('更新日期：' + this.updateDate)
              .fontSize(13)
              .fontColor($r('app.color.privacy_text_hint'))
          }
          .width('100%')
          .padding({ left: 16, top: 8, bottom: 8 })
        }

        if (this.loadFailed) {
          Text($r('app.string.privacy_policy_load_failed'))
            .fontSize(14)
            .fontColor($r('app.color.privacy_text_hint'))
            .padding(16)
            .textAlign(TextAlign.Center)
            .width('100%')
        } else {
          Text(this.policyText)
            .fontSize(14)
            .fontColor($r('app.color.privacy_text_primary'))
            .lineHeight(24)
            .padding({ left: 16, right: 16, bottom: 16 })
            .width('100%')
        }
      }
      .width('100%')
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
  }

  @Builder
  BottomActionBar() {
    Row({ space: 12 }) {
      Button('不同意')
        .layoutWeight(1)
        .height(48)
        .backgroundColor($r('app.color.privacy_button_secondary'))
        .fontColor($r('app.color.privacy_button_text_secondary'))
        .fontSize(16)
        .onClick(() => {
          this.onDisagree()
        })

      Button('同意')
        .layoutWeight(1)
        .height(48)
        .backgroundColor($r('app.color.privacy_button_primary'))
        .fontColor($r('app.color.privacy_button_text_primary'))
        .fontSize(16)
        .enabled(!this.isAgreeButtonDisabled && !this.loadFailed)
        .onClick(() => {
          this.onAgree()
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 16 })
  }

  async onAgree(): Promise<void> {
    if (this.isAgreeButtonDisabled || this.loadFailed) {
      return
    }
    this.isAgreeButtonDisabled = true

    const context = getContext(this) as common.UIAbilityContext
    const version = this.policyVersion.length > 0 ? this.policyVersion : '1.0'
    const success = await PrivacyPreferenceService.getInstance().saveConsent(context, version)

    if (success) {
      const trackProps: Record<string, string | number> = {}
      trackProps['policy_version'] = version
      AnalyticsService.getInstance().track(AnalyticsEvent.PRIVACY_AGREE, trackProps)
      router.replaceUrl({ url: 'pages/Index' })
    } else {
      promptAction.showToast({ message: '同意结果保存失败，请重试' })
      this.isAgreeButtonDisabled = false
    }
  }

  async onDisagree(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext
    await PrivacyPreferenceService.getInstance().saveDisconsent(context)
    AnalyticsService.getInstance().track(AnalyticsEvent.PRIVACY_DISAGREE)

    promptAction.showDialog({
      title: '提示',
      message: '不同意隐私政策将无法使用知时',
      buttons: [
        { text: '退出应用', color: '#EF4444' },
        { text: '返回阅读', color: '#3B82F6' }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 0) {
        const ctx = getContext(this) as common.UIAbilityContext
        ctx.terminateSelf()
      }
    })
  }
}
