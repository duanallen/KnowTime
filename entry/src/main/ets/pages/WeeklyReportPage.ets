import { AppColors, AppFontSizes } from '../common/Theme'
import { DatabaseHelper, InterruptionRow } from '../database/DatabaseHelper'
import { FocusStatsService, DailyStats, WeeklyReport, UsageOverview } from '../viewmodel/FocusStatsService'
import { common } from '@kit.AbilityKit'
import { picker, fileIo as fs } from '@kit.CoreFileKit'
import { router, promptAction, componentSnapshot } from '@kit.ArkUI'
import { image } from '@kit.ImageKit'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0006
const TAG = 'WeeklyReportPage'

/** 柱状图单日数据 */
interface WeekDayItem {
  label: string
  date: string
  minutes: number
  isToday: boolean
}

@Entry
@Component
export struct WeeklyReportPage {
  @StorageLink('isDarkMode') isDarkMode: boolean = false
  @State weekLabel: string = ''
  @State weekTotalMinutes: number = 0
  @State weekSessionCount: number = 0
  @State weekDailyAvg: number = 0
  @State prevWeekMinutes: number = 0
  @State weekDays: WeekDayItem[] = []
  @State bestDayText: string = '—'
  @State topTag: string = '—'
  @State streakDays: number = 0
  @State avgFlowScore: number = 0
  @State interruptionCount: number = 0
  @State interruptionSeconds: number = 0
  @State exporting: boolean = false
  private db: DatabaseHelper = DatabaseHelper.getInstance()
  private stats: FocusStatsService = FocusStatsService.getInstance()

  async aboutToAppear(): Promise<void> {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext
    await this.db.init(ctx)
    await this.loadData()
  }

  private async loadData(): Promise<void> {
    const now: Date = new Date()
    const todayStr: string = this.formatDate(now)
    const monday: Date = new Date(now.getFullYear(), now.getMonth(), now.getDate() - ((now.getDay() + 6) % 7))
    monday.setHours(0, 0, 0, 0)
    const weekEnd: number = monday.getTime() + 7 * 86400000

    const reports: WeeklyReport[] = await this.stats.getWeeklyReports(2)
    if (reports.length > 0) {
      const current: WeeklyReport = reports[reports.length - 1]
      this.weekLabel = current.weekLabel
      this.weekTotalMinutes = current.totalMinutes
      this.weekSessionCount = current.sessionCount
      this.weekDailyAvg = current.dailyAvg
      this.topTag = current.topTag
    }
    if (reports.length > 1) {
      this.prevWeekMinutes = reports[0].totalMinutes
    }

    // 近 14 天足够覆盖本周一至今天，按日期映射到周一~周日
    const daily: DailyStats[] = await this.stats.getDailyStats(14)
    const dailyMap: Map<string, DailyStats> = new Map()
    for (let i = 0; i < daily.length; i++) {
      dailyMap.set(daily[i].date, daily[i])
    }

    const labels: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日']
    const days: WeekDayItem[] = []
    let flowTotal: number = 0
    let flowDays: number = 0
    for (let i = 0; i < 7; i++) {
      const d: Date = new Date(monday.getTime() + i * 86400000)
      const key: string = this.formatDate(d)
      const stat: DailyStats | undefined = dailyMap.get(key)
      const minutes: number = stat ? stat.totalMinutes : 0
      if (stat && stat.sessionCount > 0) {
        flowTotal += stat.avgFlowScore
        flowDays++
      }
      days.push({ label: labels[i], date: key, minutes: minutes, isToday: key === todayStr })
    }
    this.weekDays = days
    this.avgFlowScore = flowDays > 0 ? Math.round(flowTotal / flowDays) : 0

    let bestMinutes: number = 0
    let bestDate: string = ''
    for (let i = 0; i < days.length; i++) {
      if (days[i].minutes > bestMinutes) {
        bestMinutes = days[i].minutes
        bestDate = days[i].date
      }
    }
    this.bestDayText = bestMinutes > 0 ? `${this.formatMonthDay(bestDate)} · ${bestMinutes} 分钟` : '—'

    const overview: UsageOverview = await this.stats.getUsageOverview()
    this.streakDays = overview.currentStreak

    const rows: InterruptionRow[] = await this.db.queryInterruptionRowsByRange(monday.getTime(), weekEnd)
    let seconds: number = 0
    for (let i = 0; i < rows.length; i++) {
      seconds += rows[i].duration
    }
    this.interruptionCount = rows.length
    this.interruptionSeconds = seconds
  }

  /** 导出当前页面为 PNG：截图 → 编码 → 用户选择路径 → 写入文件 */
  private async exportImage(): Promise<void> {
    if (this.exporting) return
    let packer: image.ImagePacker | undefined = undefined
    let pixelMap: image.PixelMap | undefined = undefined
    try {
      pixelMap = await componentSnapshot.get('weeklyReportRoot')
      this.exporting = true
      packer = image.createImagePacker()
      const buffer: ArrayBuffer = await packer.packing(pixelMap, { format: 'image/png', quality: 100 })

      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions()
      options.newFileNames = [`知时周报_${this.dateTag()}.png`]
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx)
      const uris: string[] = await docPicker.save(options)
      if (!uris || uris.length === 0) {
        return
      }

      const file: fs.File = await fs.open(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE)
      try {
        await fs.write(file.fd, buffer)
      } finally {
        await fs.close(file)
      }
      promptAction.showToast({ message: '周报已保存' })
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'export weekly report failed: %{public}s', (e as Error).message)
      promptAction.showToast({ message: '导出失败，请重试' })
    } finally {
      if (pixelMap) {
        await pixelMap.release()
      }
      if (packer) {
        await packer.release()
      }
      this.exporting = false
    }
  }

  private formatDate(d: Date): string {
    const y: string = d.getFullYear().toString()
    const m: string = (d.getMonth() + 1).toString().padStart(2, '0')
    const day: string = d.getDate().toString().padStart(2, '0')
    return `${y}-${m}-${day}`
  }

  private dateTag(): string {
    const d: Date = new Date()
    return `${d.getFullYear()}${(d.getMonth() + 1).toString().padStart(2, '0')}${d.getDate().toString().padStart(2, '0')}`
  }

  /** yyyy-MM-dd → M月D日 */
  private formatMonthDay(date: string): string {
    const parts: string[] = date.split('-')
    if (parts.length < 3) return date
    return `${Number(parts[1])}月${Number(parts[2])}日`
  }

  /** 分钟 → 小时文本，保留 1 位小数并去掉多余的 .0 */
  private formatHours(minutes: number): string {
    const fixed: string = (minutes / 60).toFixed(1)
    if (fixed.endsWith('.0')) {
      return fixed.substring(0, fixed.length - 2)
    }
    return fixed
  }

  private formatInterruptionMinutes(seconds: number): string {
    const m: number = seconds / 60
    if (m >= 10) return `${Math.round(m)} 分钟`
    return `${m.toFixed(1)} 分钟`
  }

  private getCompareText(): string {
    const diff: number = this.weekTotalMinutes - this.prevWeekMinutes
    if (diff > 0) return `比上周 +${diff} 分钟`
    if (diff < 0) return `比上周 ${diff} 分钟`
    return '与上周持平'
  }

  private getCompareColor(): string {
    const diff: number = this.weekTotalMinutes - this.prevWeekMinutes
    if (diff > 0) return AppColors.SUCCESS
    if (diff < 0) return AppColors.WARNING
    return AppColors.TEXT_HINT
  }

  private getMaxWeekMinutes(): number {
    let max: number = 1
    for (let i = 0; i < this.weekDays.length; i++) {
      if (this.weekDays[i].minutes > max) {
        max = this.weekDays[i].minutes
      }
    }
    return max
  }

  private getBarHeight(minutes: number): number {
    const max: number = this.getMaxWeekMinutes()
    return Math.max(3, (minutes / max) * 90)
  }

  private getBarColor(day: WeekDayItem): string {
    if (day.isToday) return AppColors.PRIMARY
    if (day.minutes > 0) return AppColors.FOCUS_ACTIVE
    return AppColors.MUTED
  }

  @Builder
  Header() {
    Row() {
      Text('返回')
        .fontSize(14)
        .fontColor(AppColors.PRIMARY)
        .width(72)
        .onClick(() => {
          router.back()
        })
      Text('本周专注报告')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.TEXT_PRIMARY)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
      Text(this.exporting ? '导出中…' : '导出图片')
        .fontSize(14)
        .fontColor(this.exporting ? AppColors.TEXT_HINT : AppColors.PRIMARY)
        .width(72)
        .textAlign(TextAlign.End)
        .onClick(() => {
          this.exportImage()
        })
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .backgroundColor(AppColors.BG_PRIMARY)
  }

  @Builder
  SummaryCard() {
    Column({ space: 14 }) {
      Row() {
        Text('本周专注')
          .fontSize(AppFontSizes.SMALL)
          .fontColor(AppColors.TEXT_HINT)
        Blank()
        if (this.weekLabel.length > 0) {
          Text(this.weekLabel)
            .fontSize(11)
            .fontColor(AppColors.TEXT_HINT)
        }
      }
      .width('100%')

      Row() {
        Text(this.formatHours(this.weekTotalMinutes))
          .fontSize(42)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.PRIMARY)
        Text(' 小时')
          .fontSize(13)
          .fontColor(AppColors.TEXT_SECONDARY)
          .margin({ top: 18 })
        Blank()
        Column({ space: 10 }) {
          Row() {
            Text('专注次数').fontSize(12).fontColor(AppColors.TEXT_SECONDARY)
            Blank()
            Text(`${this.weekSessionCount} 次`).fontSize(14).fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)
          }
          .width('100%')
          Row() {
            Text('日均时长').fontSize(12).fontColor(AppColors.TEXT_SECONDARY)
            Blank()
            Text(`${this.weekDailyAvg} 分钟`).fontSize(14).fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)
          }
          .width('100%')
        }
        .width(150)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)

      Divider().color(AppColors.DIVIDER)

      Row() {
        Text('较上周').fontSize(12).fontColor(AppColors.TEXT_SECONDARY)
        Blank()
        Text(this.getCompareText())
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.getCompareColor())
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
    .backgroundColor(AppColors.BG_CARD)
    .borderRadius(16)
  }

  @Builder
  ChartCard() {
    Column({ space: 14 }) {
      Row() {
        Text('每日专注')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY)
        Blank()
        Text('单位：分钟')
          .fontSize(10)
          .fontColor(AppColors.TEXT_HINT)
      }
      .width('100%')

      Row() {
        ForEach(this.weekDays, (day: WeekDayItem) => {
          Column({ space: 4 }) {
            Text(day.minutes > 0 ? `${day.minutes}` : '')
              .fontSize(9)
              .fontColor(day.isToday ? AppColors.PRIMARY : AppColors.TEXT_HINT)
              .height(12)
              .maxLines(1)
            Column() {}
              .width(18)
              .height(this.getBarHeight(day.minutes))
              .backgroundColor(this.getBarColor(day))
              .borderRadius(4)
            Text(day.label)
              .fontSize(10)
              .fontColor(day.isToday ? AppColors.PRIMARY : AppColors.TEXT_HINT)
          }
          .height(138)
          .justifyContent(FlexAlign.End)
          .alignItems(HorizontalAlign.Center)
          .layoutWeight(1)
        }, (day: WeekDayItem) => day.date)
      }
      .width('100%')
      .height(138)
    }
    .width('100%')
    .padding(20)
    .backgroundColor(AppColors.BG_CARD)
    .borderRadius(16)
  }

  @Builder
  InsightCell(label: string, value: string, valueColor: string) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(11)
        .fontColor(AppColors.TEXT_HINT)
      Text(value)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(valueColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .backgroundColor(AppColors.BG_PRIMARY)
    .borderRadius(12)
  }

  @Builder
  InsightCard() {
    Column({ space: 12 }) {
      Text('本周洞察')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColors.TEXT_PRIMARY)

      if (this.weekTotalMinutes === 0) {
        Text('本周还没有专注记录，开始第一段专注，让这一周被看见')
          .fontSize(13)
          .fontColor(AppColors.TEXT_HINT)
          .width('100%')
          .padding({ top: 4, bottom: 4 })
      } else {
        Row({ space: 12 }) {
          this.InsightCell('最好的一天', this.bestDayText, AppColors.TEXT_PRIMARY)
          this.InsightCell('最常用标签', this.topTag, AppColors.FOCUS_ACTIVE)
        }
        .width('100%')

        Row({ space: 12 }) {
          this.InsightCell('当前连续', `${this.streakDays} 天`, AppColors.WARNING)
          this.InsightCell('本周平均心流分', `${this.avgFlowScore}`, AppColors.PRIMARY)
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(20)
    .backgroundColor(AppColors.BG_CARD)
    .borderRadius(16)
  }

  @Builder
  InterruptionCard() {
    Column({ space: 10 }) {
      Text('中断小结')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColors.TEXT_PRIMARY)
      Text(this.interruptionCount === 0
        ? '本周没有中断记录，专注节奏保持得很好'
        : `本周中断 ${this.interruptionCount} 次，累计 ${this.formatInterruptionMinutes(this.interruptionSeconds)}`)
        .fontSize(13)
        .fontColor(this.interruptionCount === 0 ? AppColors.TEXT_HINT : AppColors.WARNING)
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(20)
    .backgroundColor(AppColors.BG_CARD)
    .borderRadius(16)
  }

  build() {
    Column() {
      this.Header()
      Scroll() {
        Column({ space: 16 }) {
          this.SummaryCard()
          this.ChartCard()
          this.InsightCard()
          this.InterruptionCard()

          Text('知时 · 让每一分钟，都被看见')
            .fontSize(11)
            .fontColor(AppColors.TEXT_HINT)
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 12, bottom: 8 })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 24 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .id('weeklyReportRoot')
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.BG_PRIMARY)
  }
}
