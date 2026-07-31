import { AppColors } from '../common/Theme'
import { DatabaseHelper } from '../database/DatabaseHelper'
import { FocusStatsService, DailyStats, UsageOverview } from '../viewmodel/FocusStatsService'
import { common } from '@kit.AbilityKit'

@Entry
@Component
export struct StatsPage {
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
  @State weekTotal: number = 0
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
    } else if (this.selectedTab === '周') {
      const monday = new Date(now)
      const dayOfWeek = now.getDay()
      monday.setDate(now.getDate() - ((dayOfWeek + 6) % 7))
      monday.setHours(0, 0, 0, 0)
      this.dailyList = await this.stats.getDailyStats(7)
      this.tagDistribution = await this.stats.getTagStats(monday.getTime(), todayEnd)
      this.hourlyDist = await this.stats.getHourlyDistribution(monday.getTime(), todayEnd)
      this.weekTotal = await this.db.getTotalMinutes(monday.getTime(), todayEnd)
    } else {
      const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).getTime()
      this.dailyList = await this.stats.getDailyStats(30)
      this.tagDistribution = await this.stats.getTagStats(monthStart, todayEnd)
      this.hourlyDist = await this.stats.getHourlyDistribution(monthStart, todayEnd)
    }
  }

  build() {
    Column() {
      Row() {
        Text('统计').fontSize(22).fontWeight(FontWeight.Bold).fontColor('#1E293B')
        Blank()
      }
      .width('100%').padding({ left: 20, right: 20, top: 14, bottom: 8 }).backgroundColor('#FFFFFF')

      Row({ space: 0 }) {
        ForEach(this.tabs, (tab: string) => {
          Text(tab)
            .fontSize(15)
            .fontWeight(this.selectedTab === tab ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.selectedTab === tab ? AppColors.PRIMARY : '#94A3B8')
            .layoutWeight(1).textAlign(TextAlign.Center)
            .padding({ top: 14, bottom: 10 })
            .onClick(() => { this.onTabChange(tab) })
        })
      }
      .width('100%').backgroundColor('#FFFFFF')
      .border({ width: { bottom: 0.5 }, color: '#E2E8F0' })

      Scroll() {
        Column({ space: 24 }) {
          Row({ space: 12 }) {
            Column() {
              Text(`${this.getLabel()}专注`).fontSize(12).fontColor('#94A3B8')
              Text(this.selectedTab === '周' ? `${this.weekTotal}` : `${this.overview.averageDailyMinutes}`)
                .fontSize(36).fontWeight(FontWeight.Bold).fontColor('#1A73E8')
              Text('分钟').fontSize(12).fontColor('#94A3B8')
            }.layoutWeight(1).padding(20).backgroundColor('#FFFFFF').borderRadius(16)

            Column() {
              Text('累计次数').fontSize(12).fontColor('#94A3B8')
              Text(`${this.overview.totalSessionsAll}`)
                .fontSize(36).fontWeight(FontWeight.Bold).fontColor('#0D9488')
              Text('次').fontSize(12).fontColor('#94A3B8')
            }.layoutWeight(1).padding(20).backgroundColor('#FFFFFF').borderRadius(16)
          }
          .width('100%')

          Column({ space: 12 }) {
            Text('使用习惯').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#1E293B')
            Column({ space: 10 }) {
              Row() { Text('日均专注').fontSize(13).fontColor('#64748B').layoutWeight(1); Text(this.formatHours(this.overview.averageDailyMinutes)).fontSize(15).fontWeight(FontWeight.Medium).fontColor('#1E293B') }.width('100%')
              Row() { Text('平均每次').fontSize(13).fontColor('#64748B').layoutWeight(1); Text(this.formatHours(this.overview.averageSessionMinutes)).fontSize(15).fontWeight(FontWeight.Medium).fontColor('#1E293B') }.width('100%')
              Row() { Text('最高产时段').fontSize(13).fontColor('#64748B').layoutWeight(1); Text(`${this.overview.mostProductiveHour}:00 - ${this.overview.mostProductiveHour + 1}:00`).fontSize(15).fontWeight(FontWeight.Medium).fontColor('#1E293B') }.width('100%')
              Row() { Text('当前连续').fontSize(13).fontColor('#64748B').layoutWeight(1); Text(`${this.overview.currentStreak} 天`).fontSize(15).fontWeight(FontWeight.Medium).fontColor('#F59E0B') }.width('100%')
              Row() { Text('最长连续').fontSize(13).fontColor('#64748B').layoutWeight(1); Text(`${this.overview.longestStreak} 天`).fontSize(15).fontWeight(FontWeight.Medium).fontColor('#1E293B') }.width('100%')
            }
            .width('100%').padding(16).backgroundColor('#FFFFFF').borderRadius(12)
          }
          .width('100%').padding(20).backgroundColor('#F8FAFC').borderRadius(16)

          if (this.dailyList.length > 0) {
            Column({ space: 10 }) {
              Text(`${this.getLabel()}分布`).fontSize(15).fontWeight(FontWeight.Medium).fontColor('#1E293B')
              Row({ space: 2 }) {
                ForEach(this.dailyList, (item: DailyStats) => {
                  Column({ space: 2 }) {
                    Column() {}
                      .width(this.selectedTab === '日' ? 40 : this.selectedTab === '周' ? 36 : 18)
                      .height(Math.max(4, (item.totalMinutes / Math.max(this.getMaxDailyMinutes(), 1)) * 100))
                      .backgroundColor(item.totalMinutes > 0 ? '#1A73E8' : '#E2E8F0')
                      .borderRadius(3)
                    Text(item.totalMinutes > 0 ? `${item.totalMinutes}` : '')
                      .fontSize(8).fontColor('#94A3B8')
                  }
                  .alignItems(HorizontalAlign.Center)
                })
              }
              .width('100%').height(120).alignItems(VerticalAlign.Bottom)
            }
            .width('100%').padding(20).backgroundColor('#FFFFFF').borderRadius(16)
          }

          if (this.hourlyDist.some((v: number) => v > 0)) {
            Column({ space: 10 }) {
              Text('时段分布').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#1E293B')
              Row({ space: 1 }) {
                ForEach(this.hourlyDist, (val: number, idx: number) => {
                  Column({ space: 2 }) {
                    Column() {}
                      .width(12)
                      .height(Math.max(2, (val / Math.max(...this.hourlyDist, 1)) * 60))
                      .backgroundColor(val > 0 ? '#3B82F6' : '#F1F5F9')
                      .borderRadius(2)
                    if (idx % 3 === 0) { Text(`${idx}`).fontSize(7).fontColor('#CBD5E1') }
                  }
                  .alignItems(HorizontalAlign.Center)
                })
              }
              .width('100%').height(80).alignItems(VerticalAlign.Bottom)
            }
            .width('100%').padding(20).backgroundColor('#FFFFFF').borderRadius(16)
          }

          if (Object.keys(this.tagDistribution).length > 0) {
            Column({ space: 12 }) {
              Text('标签分布').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#1E293B')
              Column({ space: 10 }) {
                ForEach(Object.keys(this.tagDistribution).sort(), (key: string) => {
                  Row({ space: 10 }) {
                    Text(key).fontSize(13).fontColor('#334155').width(50)
                    Row() {
                      Row() {}
                        .width(`${Math.min((this.tagDistribution[key] / Math.max(this.getTotalTagMins(), 1)) * 100, 100)}%`)
                        .height('100%').backgroundColor('#1A73E8').borderRadius(4)
                    }.layoutWeight(1).height(10).backgroundColor('#F1F5F9').borderRadius(4)
                    Text(`${this.tagDistribution[key]}m`).fontSize(12).fontColor('#94A3B8').width(36)
                  }.width('100%')
                })
              }
            }
            .width('100%').padding(20).backgroundColor('#FFFFFF').borderRadius(16)
          }

          Blank().height(20)
        }
        .padding({ left: 20, right: 20, bottom: 40 })
      }
      .layoutWeight(1).scrollBar(BarState.Off)
    }
    .width('100%').height('100%').backgroundColor('#F8FAFC')
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
}
