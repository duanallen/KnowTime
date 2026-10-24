import { AppColors } from '../common/Theme'
import { DatabaseHelper } from '../database/DatabaseHelper'
import { FocusStatsService, DailyStats, UsageOverview } from '../viewmodel/FocusStatsService'
import { common } from '@kit.AbilityKit'

@Entry
@Component
export struct StatsPage {
  @StorageLink('isDarkMode') isDarkMode: boolean = false
  @Prop @Watch('onRefresh') refreshKey: number = 0
  @State selectedTab: string = '日'
  private tabs: string[] = ['日', '周', '月']
  @State overview: UsageOverview = {
    totalMinutesAll: 0, totalSessionsAll: 0, daysSinceFirstUse: 0,
    averageDailyMinutes: 0, averageSessionMinutes: 0,
    mostProductiveHour: 0, currentStreak: 0, longestStreak: 0
  }
  @State dailyList: DailyStats[] = []
  @State tagDistribution: Record<string, number> = {}
  @State hourlyDist: number[] = new Array<number>(24).fill(0)
  @State dayTotal: number = 0
  @State dayCount: number = 0
  @State weekTotal: number = 0
  @State weekCount: number = 0
  @State monthTotal: number = 0
  @State monthCount: number = 0
  private db: DatabaseHelper = DatabaseHelper.getInstance()
  private stats: FocusStatsService = FocusStatsService.getInstance()
  private hasInit: boolean = false

  async aboutToAppear(): Promise<void> {
    const ctx = getContext(this) as common.UIAbilityContext
    await this.db.init(ctx)
    await this.loadAll()
    this.hasInit = true
  }

  onRefresh(): void {
    if (this.hasInit && this.refreshKey > 0) {
      this.loadAll()
    }
  }

  private getLabel(): string {
    if (this.selectedTab === '日') return '今天'
    if (this.selectedTab === '周') return '本周'
    return '本月'
  }

  async onTabChange(value: string): Promise<void> {
    this.selectedTab = value
    await this.loadAll()
  }

  async loadAll(): Promise<void> {
    const now = new Date()
    now.setHours(0, 0, 0, 0)
    const todayEnd = now.getTime() + 24 * 60 * 60 * 1000

    this.overview = await this.stats.getUsageOverview()

    if (this.selectedTab === '日') {
      this.dailyList = await this.stats.getDailyStats(1)
      this.tagDistribution = await this.stats.getTagStats(now.getTime(), todayEnd)
      this.hourlyDist = await this.stats.getHourlyDistribution(now.getTime(), todayEnd)
      this.dayTotal = await this.db.getTotalMinutes(now.getTime(), todayEnd)
      this.dayCount = await this.db.getSessionCount(now.getTime(), todayEnd)
    } else if (this.selectedTab === '周') {
      const monday = new Date(now)
      const dayOfWeek = now.getDay()
      monday.setDate(now.getDate() - ((dayOfWeek + 6) % 7))
      monday.setHours(0, 0, 0, 0)
      this.dailyList = await this.stats.getDailyStats(7)
      this.tagDistribution = await this.stats.getTagStats(monday.getTime(), todayEnd)
      this.hourlyDist = await this.stats.getHourlyDistribution(monday.getTime(), todayEnd)
      this.weekTotal = await this.db.getTotalMinutes(monday.getTime(), todayEnd)
      this.weekCount = await this.db.getSessionCount(monday.getTime(), todayEnd)
    } else {
      const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).getTime()
      this.dailyList = await this.stats.getDailyStats(30)
      this.tagDistribution = await this.stats.getTagStats(monthStart, todayEnd)
      this.hourlyDist = await this.stats.getHourlyDistribution(monthStart, todayEnd)
      this.monthTotal = await this.db.getTotalMinutes(monthStart, todayEnd)
      this.monthCount = await this.db.getSessionCount(monthStart, todayEnd)
    }
  }

  build() {
    Column() {
      Row() {
        Text('统计').fontSize(22).fontWeight(FontWeight.Bold).fontColor(AppColors.TEXT_PRIMARY)
        Blank()
      }
      .width('100%').padding({ left: 20, right: 20, top: 14, bottom: 8 }).backgroundColor(AppColors.BG_CARD)

      Row({ space: 0 }) {
        ForEach(this.tabs, (tab: string) => {
          Text(tab)
            .fontSize(15)
            .fontWeight(this.selectedTab === tab ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.selectedTab === tab ? AppColors.PRIMARY : AppColors.TEXT_HINT)
            .layoutWeight(1).textAlign(TextAlign.Center)
            .padding({ top: 14, bottom: 10 })
            .onClick(() => { this.onTabChange(tab) })
        })
      }
      .width('100%').backgroundColor(AppColors.BG_CARD)
      .border({ width: { bottom: 0.5 }, color: AppColors.BORDER })

      Scroll() {
        Column({ space: 24 }) {
          Row({ space: 12 }) {
            Column() {
              Text(`${this.getLabel()}专注`).fontSize(12).fontColor(AppColors.TEXT_HINT)
              Text(this.selectedTab === '日' ? `${this.dayTotal}` :
                  this.selectedTab === '周' ? `${this.weekTotal}` : `${this.monthTotal}`)
                .fontSize(36).fontWeight(FontWeight.Bold).fontColor(AppColors.PRIMARY)
              Text('分钟').fontSize(12).fontColor(AppColors.TEXT_HINT)
            }.layoutWeight(1).padding(20).backgroundColor(AppColors.BG_CARD).borderRadius(16)

            Column() {
              Text(`${this.getLabel()}次数`).fontSize(12).fontColor(AppColors.TEXT_HINT)
              Text(this.selectedTab === '日' ? `${this.dayCount}` :
                  this.selectedTab === '周' ? `${this.weekCount}` : `${this.monthCount}`)
                .fontSize(36).fontWeight(FontWeight.Bold).fontColor(AppColors.FOCUS_ACTIVE)
              Text('次').fontSize(12).fontColor(AppColors.TEXT_HINT)
            }.layoutWeight(1).padding(20).backgroundColor(AppColors.BG_CARD).borderRadius(16)
          }
          .width('100%')

          Column({ space: 12 }) {
            Text('使用习惯').fontSize(15).fontWeight(FontWeight.Medium).fontColor(AppColors.TEXT_PRIMARY)
            Column({ space: 10 }) {
              Row() { Text('日均专注').fontSize(13).fontColor(AppColors.TEXT_SECONDARY).layoutWeight(1); Text(this.formatHours(this.overview.averageDailyMinutes)).fontSize(15).fontWeight(FontWeight.Medium).fontColor(AppColors.TEXT_PRIMARY) }.width('100%')
              Row() { Text('平均每次').fontSize(13).fontColor(AppColors.TEXT_SECONDARY).layoutWeight(1); Text(this.formatHours(this.overview.averageSessionMinutes)).fontSize(15).fontWeight(FontWeight.Medium).fontColor(AppColors.TEXT_PRIMARY) }.width('100%')
              Row() { Text('最高产时段').fontSize(13).fontColor(AppColors.TEXT_SECONDARY).layoutWeight(1); Text(`${this.overview.mostProductiveHour}:00 - ${this.overview.mostProductiveHour + 1}:00`).fontSize(15).fontWeight(FontWeight.Medium).fontColor(AppColors.TEXT_PRIMARY) }.width('100%')
              Row() { Text('当前连续').fontSize(13).fontColor(AppColors.TEXT_SECONDARY).layoutWeight(1); Text(`${this.overview.currentStreak} 天`).fontSize(15).fontWeight(FontWeight.Medium).fontColor(AppColors.WARNING) }.width('100%')
              Row() { Text('最长连续').fontSize(13).fontColor(AppColors.TEXT_SECONDARY).layoutWeight(1); Text(`${this.overview.longestStreak} 天`).fontSize(15).fontWeight(FontWeight.Medium).fontColor(AppColors.TEXT_PRIMARY) }.width('100%')
            }
            .width('100%').padding(16).backgroundColor(AppColors.BG_CARD).borderRadius(12)
          }
          .width('100%').padding(20).backgroundColor(AppColors.BG_PRIMARY).borderRadius(16)

          if (this.dailyList.length > 0) {
            Column({ space: 10 }) {
              Text(`${this.getLabel()}分布`).fontSize(15).fontWeight(FontWeight.Medium).fontColor(AppColors.TEXT_PRIMARY)
              Scroll() {
                Row({ space: 2 }) {
                  ForEach(this.dailyList, (item: DailyStats) => {
                    Column({ space: 2 }) {
                      // 柱顶标注：专注时间（分钟），字体随数字长度自适应
                      Text(item.totalMinutes > 0 ? this.formatMinutesShort(item.totalMinutes) : '')
                        .fontSize(item.totalMinutes > 0
                          ? this.getAdaptiveFontSize(this.formatMinutesShort(item.totalMinutes), 16, 10, 6)
                          : 6)
                        .fontColor(AppColors.TEXT_SUBTLE).maxLines(1).fontWeight(FontWeight.Medium)
                      Column() {}
                        .width(14)
                        .height(Math.max(4, (item.totalMinutes / Math.max(this.getMaxDailyMinutes(), 1)) * 100))
                        .backgroundColor(item.totalMinutes > 0 ? AppColors.PRIMARY : AppColors.BORDER)
                        .borderRadius(3)
                      Text(item.totalMinutes > 0 ? `${item.totalMinutes}` : '')
                        .fontSize(7).fontColor(AppColors.TEXT_HINT).maxLines(1)
                    }
                    .alignItems(HorizontalAlign.Center)
                  })
                }
                .height(140).alignItems(VerticalAlign.Bottom).padding({ left: 2, right: 2 })
              }
              .width('100%').height(150).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
            }
            .width('100%').padding(20).backgroundColor(AppColors.BG_CARD).borderRadius(16)
          }

          if (this.hourlyDist.some((v: number) => v > 0)) {
            Column({ space: 10 }) {
              Text('时段分布').fontSize(15).fontWeight(FontWeight.Medium).fontColor(AppColors.TEXT_PRIMARY)
              Scroll() {
                Row({ space: 1 }) {
                  ForEach(this.hourlyDist, (val: number, idx: number) => {
                    Column({ space: 2 }) {
                      // 柱顶标注：该时段专注时间（分钟），仅在有数据时显示，字体自适应
                      Text(val > 0 ? this.formatMinutesShort(val) : '')
                        .fontSize(val > 0
                          ? this.getAdaptiveFontSize(this.formatMinutesShort(val), 12, 8, 5)
                          : 5)
                        .fontColor(AppColors.TEXT_SUBTLE).maxLines(1).fontWeight(FontWeight.Medium)
                      Column() {}
                        .width(10)
                        .height(Math.max(2, (val / Math.max(...this.hourlyDist, 1)) * 60))
                        .backgroundColor(val > 0 ? AppColors.ACCENT_BLUE : AppColors.DIVIDER)
                        .borderRadius(2)
                      if (idx % 2 === 0) { Text(`${idx}`).fontSize(7).fontColor(AppColors.MUTED) }
                    }
                    .alignItems(HorizontalAlign.Center)
                  })
                }
                .height(100).alignItems(VerticalAlign.Bottom).padding({ left: 2, right: 2 })
              }
              .width('100%').height(110).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
            }
            .width('100%').padding(20).backgroundColor(AppColors.BG_CARD).borderRadius(16)
          }

          if (Object.keys(this.tagDistribution).length > 0) {
            Column({ space: 12 }) {
              Text('标签分布').fontSize(15).fontWeight(FontWeight.Medium).fontColor(AppColors.TEXT_PRIMARY)
              Column({ space: 10 }) {
                ForEach(Object.keys(this.tagDistribution).sort(), (key: string) => {
                  Row({ space: 10 }) {
                    Text(key).fontSize(13).fontColor(AppColors.TEXT_BODY).width(50)
                    Row() {
                      Row() {}
                        .width(`${Math.min((this.tagDistribution[key] / Math.max(this.getTotalTagMins(), 1)) * 100, 100)}%`)
                        .height('100%').backgroundColor(AppColors.PRIMARY).borderRadius(4)
                    }.layoutWeight(1).height(10).backgroundColor(AppColors.DIVIDER).borderRadius(4)
                    Text(`${this.tagDistribution[key]}m`).fontSize(12).fontColor(AppColors.TEXT_HINT).width(36)
                  }.width('100%')
                })
              }
            }
            .width('100%').padding(20).backgroundColor(AppColors.BG_CARD).borderRadius(16)
          }

          Blank().height(20)
        }
        .padding({ left: 20, right: 20, bottom: 40 })
      }
      .layoutWeight(1).scrollBar(BarState.Off)
    }
    .width('100%').height('100%').backgroundColor(AppColors.BG_PRIMARY)
  }

  private getMaxDailyMinutes(): number {
    let max = 1
    for (const d of this.dailyList) {
      if (d.totalMinutes > max) max = d.totalMinutes
    }
    return max
  }

  private getTotalTagMins(): number {
    let t = 0
    const keys = Object.keys(this.tagDistribution)
    for (const k of keys) { t += this.tagDistribution[k] }
    return Math.max(t, 1)
  }

  private formatHours(min: number): string {
    if (min < 60) return `${min}分钟`
    return `${(min / 60).toFixed(1)}h`
  }

  /**
   * 根据内容长度和容器宽度计算自适应字体大小
   * 原则：保证文字在容器宽度内完整显示，同时不小于最小可读字号
   * @param content 待显示内容（数字或字符串）
   * @param containerWidth 容器宽度（vp）
   * @param baseFontSize 基础字号（vp）
   * @param minFontSize 最小字号（vp），默认 6
   * @returns 计算后的字号
   */
  private getAdaptiveFontSize(content: number | string, containerWidth: number, baseFontSize: number,
    minFontSize: number = 6): number {
    const len: number = String(content).length
    // 数字字符宽度约为字号的 0.55 倍，预留 0.5vp 间距
    const charWidthRatio: number = 0.55
    const requiredWidth: number = len * baseFontSize * charWidthRatio + 0.5
    if (requiredWidth <= containerWidth) {
      return baseFontSize
    }
    // 按比例缩小：fontSize = (containerWidth - 0.5) / (len * charWidthRatio)
    const scaled: number = Math.floor((containerWidth - 0.5) / (len * charWidthRatio))
    return Math.max(minFontSize, scaled)
  }

  /**
   * 格式化专注分钟数为简短文本（用于柱状图标注）
   * 超过 60 分钟时使用 "xh" 或 "x.xh" 形式，避免数字过长
   */
  private formatMinutesShort(min: number): string {
    if (min <= 0) return ''
    if (min < 60) return `${min}`
    const h: number = min / 60
    if (h < 10) return `${h.toFixed(1)}h`
    return `${Math.floor(h)}h`
  }
}
