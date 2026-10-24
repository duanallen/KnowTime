import { AppColors } from '../common/Theme'
import { DatabaseHelper, InterruptionRow } from '../database/DatabaseHelper'
import { FocusStatsService, DailyStats, UsageOverview } from '../viewmodel/FocusStatsService'
import { common } from '@kit.AbilityKit'
import { router } from '@kit.ArkUI'

/** 中断分析分组：原因 + 次数 + 累计秒数 */
interface InterruptionGroup {
  reason: string
  count: number
  seconds: number
}

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
  // 中断分析
  @State interruptionTotal: number = 0
  @State interruptionTotalSeconds: number = 0
  @State interruptionGroups: InterruptionGroup[] = []
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
      await this.loadInterruptions(now.getTime(), todayEnd)
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
      await this.loadInterruptions(monday.getTime(), todayEnd)
    } else {
      const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).getTime()
      this.dailyList = await this.stats.getDailyStats(30)
      this.tagDistribution = await this.stats.getTagStats(monthStart, todayEnd)
      this.hourlyDist = await this.stats.getHourlyDistribution(monthStart, todayEnd)
      this.monthTotal = await this.db.getTotalMinutes(monthStart, todayEnd)
      this.monthCount = await this.db.getSessionCount(monthStart, todayEnd)
      await this.loadInterruptions(monthStart, todayEnd)
    }
  }

  /** 汇总所选时间范围内的中断：总次数/总时长/按原因分组（按次数降序） */
  private async loadInterruptions(from: number, to: number): Promise<void> {
    const rows: InterruptionRow[] = await this.db.queryInterruptionRowsByRange(from, to)
    let totalSeconds = 0
    const groups: InterruptionGroup[] = []
    for (let i = 0; i < rows.length; i++) {
      const row: InterruptionRow = rows[i]
      totalSeconds += row.duration
      let found: number = -1
      for (let j = 0; j < groups.length; j++) {
        if (groups[j].reason === row.reason) {
          found = j
          break
        }
      }
      if (found >= 0) {
        groups[found].count += 1
        groups[found].seconds += row.duration
      } else {
        groups.push({ reason: row.reason, count: 1, seconds: row.duration })
      }
    }
    groups.sort((a: InterruptionGroup, b: InterruptionGroup) => b.count - a.count)
    this.interruptionTotal = rows.length
    this.interruptionTotalSeconds = totalSeconds
    this.interruptionGroups = groups
  }

  /** 中断秒数转分钟文本，1 位小数；10 分钟以上取整 */
  private formatInterruptionMinutes(seconds: number): string {
    const m: number = seconds / 60
    if (m >= 10) return `${Math.round(m)} 分钟`
    return `${m.toFixed(1)} 分钟`
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
          Column() {
            Row() {
              Column({ space: 3 }) {
                Text('本周专注报告')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(AppColors.TEXT_PRIMARY)
                Text('查看本周完整复盘')
                  .fontSize(12)
                  .fontColor(AppColors.TEXT_HINT)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Text('>')
                .fontSize(16)
                .fontColor(AppColors.MUTED)
            }
            .width('100%')
            .height(64)
            .padding({ left: 16, right: 12 })
            .onClick(() => {
              router.pushUrl({ url: 'pages/WeeklyReportPage' })
            })
          }
          .width('100%')
          .backgroundColor(AppColors.BG_CARD)
          .borderRadius(16)

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

          // 中断分析
          Column({ space: 12 }) {
            Text('中断分析').fontSize(15).fontWeight(FontWeight.Medium).fontColor(AppColors.TEXT_PRIMARY)

            if (this.interruptionTotal === 0) {
              Text('这段时间没有中断记录').fontSize(13).fontColor(AppColors.TEXT_HINT)
                .width('100%').padding({ top: 4, bottom: 4 })
            } else {
              Row({ space: 12 }) {
                Column() {
                  Text(`${this.interruptionTotal}`).fontSize(28).fontWeight(FontWeight.Bold)
                    .fontColor(AppColors.WARNING)
                  Text('次中断').fontSize(11).fontColor(AppColors.TEXT_HINT)
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)

                Column() {
                  Text(this.formatInterruptionMinutes(this.interruptionTotalSeconds)).fontSize(24)
                    .fontWeight(FontWeight.Bold).fontColor(AppColors.TEXT_PRIMARY)
                  Text('总中断时长').fontSize(11).fontColor(AppColors.TEXT_HINT)
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)
              }
              .width('100%').padding({ top: 4, bottom: 4 })

              Column({ space: 10 }) {
                ForEach(this.interruptionGroups, (group: InterruptionGroup) => {
                  Column({ space: 6 }) {
                    Row({ space: 8 }) {
                      Text(group.reason).fontSize(13).fontColor(AppColors.TEXT_BODY).width(64)
                      Text(`${group.count} 次`).fontSize(12).fontColor(AppColors.TEXT_HINT)
                      Blank()
                      Text(this.formatInterruptionMinutes(group.seconds))
                        .fontSize(12).fontColor(AppColors.TEXT_SECONDARY)
                    }
                    .width('100%')

                    Row() {
                      Row() {}
                        .width(`${Math.min((group.count / Math.max(this.interruptionTotal, 1)) * 100, 100)}%`)
                        .height('100%').backgroundColor(AppColors.WARNING).borderRadius(4)
                    }
                    .width('100%').height(8).backgroundColor(AppColors.DIVIDER).borderRadius(4)
                  }
                  .width('100%')
                }, (group: InterruptionGroup) => group.reason)
              }
              .width('100%')
            }
          }
          .width('100%').padding(20).backgroundColor(AppColors.BG_CARD).borderRadius(16)

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
