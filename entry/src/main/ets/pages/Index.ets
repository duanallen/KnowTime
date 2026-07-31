import { AppColors } from '../common/Theme'
import { FocusPage } from './FocusPage'
import { StatsPage } from './StatsPage'
import { SettingsPage } from './SettingsPage'
import { ProfilePage } from './ProfilePage'
import { AnalyticsService } from '../analytics/AnalyticsService'

@Entry
@Component
struct Index {
  @State currentTabIndex: number = 0
  @Provide refreshKey: number = 0
  private tabIcons: string[] = ['◉', '☰', '⚙', '◈']
  private tabNames: string[] = ['FocusPage', 'StatsPage', 'SettingsPage', 'ProfilePage']
  private prevIndex: number = 0
  private analytics: AnalyticsService = AnalyticsService.getInstance()

  aboutToAppear(): void {
    this.analytics.startPageView(this.tabNames[this.currentTabIndex])
  }

  onPageShow(): void {
    // 页面显示时触发刷新
    this.refreshKey = Date.now()
  }

  build() {
    Column() {
      Tabs({ index: $$this.currentTabIndex }) {
        TabContent() { FocusPage() }
        TabContent() { StatsPage({ refreshKey: this.refreshKey }) }
        TabContent() { SettingsPage({ refreshKey: this.refreshKey }) }
        TabContent() { ProfilePage({ refreshKey: this.refreshKey }) }
      }
      .barHeight(0)
      .onChange((index: number) => {
        if (this.prevIndex !== index) {
          this.analytics.endPageView(this.tabNames[this.prevIndex])
          this.analytics.startPageView(this.tabNames[index])
          this.prevIndex = index
        }
        this.refreshKey = Date.now()
        this.currentTabIndex = index
      })
      .layoutWeight(1)
      .scrollable(false)

      Row() {
        ForEach(['专注', '统计', '设置', '我的'], (title: string, index: number) => {
          Column({ space: 2 }) {
            Text(this.tabIcons[index])
              .fontSize(20)
              .fontColor(this.currentTabIndex === index ? AppColors.PRIMARY : '#CBD5E1')
            Text(title)
              .fontSize(10)
              .fontColor(this.currentTabIndex === index ? AppColors.PRIMARY : '#94A3B8')
              .fontWeight(this.currentTabIndex === index ? FontWeight.Medium : FontWeight.Normal)
          }
          .layoutWeight(1)
          .padding({ top: 8, bottom: 6 })
          .onClick(() => { this.currentTabIndex = index })
        })
      }
      .width('100%')
      .height(56)
      .backgroundColor('#FFFFFF')
      .shadow({ radius: 16, color: '#0F172A10', offsetY: -4 })
    }
    .width('100%')
    .height('100%')
  }
}
