import { AppColors } from '../common/Theme'
import { DatabaseHelper } from '../database/DatabaseHelper'
import { FocusStatsService, DailyStats } from '../viewmodel/FocusStatsService'
import { common } from '@kit.AbilityKit'
import { router } from '@kit.ArkUI'

interface Achievement {
  icon: string
  title: string
  desc: string
  unlocked: boolean
  /** 进度文案：未解锁显示 当前值/目标值，已解锁显示「已达成」 */
  progressText: string
}

/** 热力图单格：日期 / 分钟数 / 颜色等级 / 是否空格（无数据或未来日期） */
interface HeatDay {
  date: string
  minutes: number
  level: number
  isBlank: boolean
}

/** 热力图一列 = 一周（周一至周日） */
interface HeatWeek {
  index: number
  days: HeatDay[]
}

@Entry
@Component
export struct ProfilePage {
  @StorageLink('isDarkMode') isDarkMode: boolean = false
  @Prop @Watch('onRefresh') refreshKey: number = 0
  @State totalMinutes: number = 0
  @State sessionCount: number = 0
  @State streakDays: number = 0
  @State heatWeeks: HeatWeek[] = []
  @State heatActiveDays: number = 0
  @State heatTotalMinutes: number = 0
  @State achievements: Achievement[] = [
    { icon: '🔥', title: '初识专注', desc: '完成第一次专注', unlocked: false, progressText: '0/1 次' },
    { icon: '⭐', title: '连续7天', desc: '连续7天专注', unlocked: false, progressText: '0/7 天' },
    { icon: '💎', title: '百时达人', desc: '累计100小时', unlocked: false, progressText: '0/6000 分' },
    { icon: '🌟', title: '心流大师', desc: '心流得分>90', unlocked: false, progressText: '0/90 分' },
    { icon: '🌅', title: '早起冠军', desc: '连续5天早6点', unlocked: false, progressText: '0/5 天' },
    { icon: '🏆', title: '目标达成', desc: '完成周目标', unlocked: false, progressText: '0/300 分' },
    { icon: '🎯', title: '专注猎人', desc: '单次>120分钟', unlocked: false, progressText: '0/120 分' },
    { icon: '📚', title: '书虫', desc: '阅读累计10h', unlocked: false, progressText: '0/10 小时' },
    { icon: '🏅', title: '连续30天', desc: '连续30天专注', unlocked: false, progressText: '0/30 天' },
    { icon: '👑', title: '连续100天', desc: '连续100天专注', unlocked: false, progressText: '0/100 天' },
  ]
  private heatLegendLevels: number[] = [0, 1, 2, 3, 4]
  private db: DatabaseHelper = DatabaseHelper.getInstance()
  private stats: FocusStatsService = FocusStatsService.getInstance()
  private hasInit: boolean = false

  async aboutToAppear(): Promise<void> {
    const ctx = getContext(this) as common.UIAbilityContext
    await this.db.init(ctx)
    await this.loadData()
    this.hasInit = true
  }

  onRefresh(): void {
    if (this.hasInit && this.refreshKey > 0) {
      this.loadData()
    }
  }

  async loadData(): Promise<void> {
    const now = new Date()
    now.setHours(0, 0, 0, 0)
    const todayEnd = now.getTime() + 24 * 60 * 60 * 1000
    const yearStart = new Date()
    yearStart.setMonth(0, 1)
    yearStart.setHours(0, 0, 0, 0)
    this.totalMinutes = await this.db.getTotalMinutes(yearStart.getTime(), todayEnd)
    this.sessionCount = await this.db.getSessionCount(yearStart.getTime(), todayEnd)

    // 连续天数复用 FocusStatsService，避免重复实现统计逻辑
    const overview = await this.stats.getUsageOverview()
    this.streakDays = overview.currentStreak
    const longestStreak = overview.longestStreak

    // 最近 84 天（12 周 × 7 天）每日数据 → 热力图
    const heatDaily = await this.stats.getDailyStats(84)
    this.buildHeatData(heatDaily)

    // 查询年度所有会话，用于成就勋章判定
    const allSessions = await this.db.querySessionsByRange(yearStart.getTime(), todayEnd)
    let maxFlowScore = 0
    let maxSingleDuration = 0
    let readingTotalSeconds = 0
    const earlyMorningDaySet: Set<string> = new Set()
    for (let i = 0; i < allSessions.length; i++) {
      const s = allSessions[i]
      if (s.flowScore > maxFlowScore) maxFlowScore = s.flowScore
      if (s.actualDuration > maxSingleDuration) maxSingleDuration = s.actualDuration
      if (s.tag === '阅读') readingTotalSeconds += s.actualDuration
      const startHour = new Date(s.startTime).getHours()
      if (startHour < 6) {
        const d = new Date(s.startTime)
        d.setHours(0, 0, 0, 0)
        earlyMorningDaySet.add(d.toDateString())
      }
    }
    const earlyMorningDays = earlyMorningDaySet.size

    // 本周专注总分钟数（周目标：本周专注 >= 5 小时 = 300 分钟）
    const monday = new Date(now)
    const dayOfWeek = now.getDay()
    monday.setDate(now.getDate() - ((dayOfWeek + 6) % 7))
    monday.setHours(0, 0, 0, 0)
    const weekTotalMinutes = await this.db.getTotalMinutes(monday.getTime(), todayEnd)

    // 连续记录里程碑（连续30天/100天）取 longestStreak 而非当前 streakDays：
    // 成就是一次性里程碑，历史达成后不应因当前断链而回退；进度文案同用该口径保持一致。
    const newAchievements: Achievement[] = [
      {
        icon: '🔥', title: '初识专注', desc: '完成第一次专注', unlocked: this.sessionCount >= 1,
        progressText: this.formatProgress(this.sessionCount >= 1, this.sessionCount, 1, '次')
      },
      {
        icon: '⭐', title: '连续7天', desc: '连续7天专注', unlocked: this.streakDays >= 7,
        progressText: this.formatProgress(this.streakDays >= 7, this.streakDays, 7, '天')
      },
      {
        icon: '💎', title: '百时达人', desc: '累计100小时', unlocked: this.totalMinutes >= 6000,
        progressText: this.formatProgress(this.totalMinutes >= 6000, this.totalMinutes, 6000, '分')
      },
      {
        icon: '🌟', title: '心流大师', desc: '心流得分>90', unlocked: maxFlowScore > 90,
        progressText: this.formatProgress(maxFlowScore > 90, maxFlowScore, 90, '分')
      },
      {
        icon: '🌅', title: '早起冠军', desc: '连续5天早6点', unlocked: earlyMorningDays >= 5,
        progressText: this.formatProgress(earlyMorningDays >= 5, earlyMorningDays, 5, '天')
      },
      {
        icon: '🏆', title: '目标达成', desc: '完成周目标', unlocked: weekTotalMinutes >= 300,
        progressText: this.formatProgress(weekTotalMinutes >= 300, weekTotalMinutes, 300, '分')
      },
      {
        icon: '🎯', title: '专注猎人', desc: '单次>120分钟', unlocked: maxSingleDuration > 120 * 60,
        progressText: this.formatProgress(maxSingleDuration > 120 * 60, Math.floor(maxSingleDuration / 60), 120, '分')
      },
      {
        icon: '📚', title: '书虫', desc: '阅读累计10h', unlocked: readingTotalSeconds >= 10 * 60 * 60,
        progressText: this.formatProgress(readingTotalSeconds >= 10 * 60 * 60,
          Math.floor(readingTotalSeconds / 3600), 10, '小时')
      },
      {
        icon: '🏅', title: '连续30天', desc: '连续30天专注', unlocked: longestStreak >= 30,
        progressText: this.formatProgress(longestStreak >= 30, longestStreak, 30, '天')
      },
      {
        icon: '👑', title: '连续100天', desc: '连续100天专注', unlocked: longestStreak >= 100,
        progressText: this.formatProgress(longestStreak >= 100, longestStreak, 100, '天')
      },
    ]
    this.achievements = newAchievements
  }

  /** 未解锁：当前值/目标值 + 单位；已解锁：已达成 */
  private formatProgress(unlocked: boolean, current: number, target: number, unit: string): string {
    if (unlocked) return '已达成'
    const shown = current > target ? target : current
    return `${shown}/${target} ${unit}`
  }

  /**
   * 构建 12 周热力图：列 = 周（周一为首日，共 12 列），行 = 星期（周一至周日，共 7 行）。
   * getDailyStats 返回最早→最新，这里按日历周反推列号，今日之后的日子留空格占位。
   */
  private buildHeatData(daily: DailyStats[]): void {
    const minuteMap: Map<string, number> = new Map()
    for (let i = 0; i < daily.length; i++) {
      minuteMap.set(daily[i].date, daily[i].totalMinutes)
    }

    const now = new Date()
    now.setHours(0, 0, 0, 0)
    const todayMondayOffset = (now.getDay() + 6) % 7
    const currentMonday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - todayMondayOffset)
    currentMonday.setHours(0, 0, 0, 0)

    const weeks: HeatWeek[] = []
    let activeDays = 0
    let totalMinutes = 0
    for (let w = 0; w < 12; w++) {
      const mondayTime = currentMonday.getTime() - (11 - w) * 7 * 86400000
      const days: HeatDay[] = []
      for (let d = 0; d < 7; d++) {
        const dayDate = new Date(mondayTime + d * 86400000)
        const dateKey = this.formatDateKey(dayDate)
        const minutes = minuteMap.get(dateKey)
        const isBlank = minutes === undefined
        const value = minutes === undefined ? 0 : minutes
        if (!isBlank) {
          totalMinutes += value
          if (value > 0) activeDays++
        }
        days.push({ date: dateKey, minutes: value, level: this.calcHeatLevel(value), isBlank: isBlank })
      }
      weeks.push({ index: w, days: days })
    }
    this.heatWeeks = weeks
    this.heatActiveDays = activeDays
    this.heatTotalMinutes = totalMinutes
  }

  private formatDateKey(d: Date): string {
    return `${d.getFullYear()}-${(d.getMonth() + 1).toString().padStart(2, '0')}-${d.getDate().toString().padStart(2, '0')}`
  }

  /** 0 → 0；1-29 → 1；30-59 → 2；60-119 → 3；≥120 → 4 */
  private calcHeatLevel(minutes: number): number {
    if (minutes <= 0) return 0
    if (minutes < 30) return 1
    if (minutes < 60) return 2
    if (minutes < 120) return 3
    return 4
  }

  private getHeatColor(level: number): string {
    if (level === 1) return AppColors.HEAT_1
    if (level === 2) return AppColors.HEAT_2
    if (level === 3) return AppColors.HEAT_3
    if (level === 4) return AppColors.HEAT_4
    return AppColors.HEAT_0
  }

  private formatHeatHours(minutes: number): string {
    const hours = minutes / 60
    if (hours >= 10) return `${Math.round(hours)}`
    return hours.toFixed(1)
  }

  private formatHours(minutes: number): string {
    if (minutes < 60) return `${minutes}分钟`
    return `${(minutes / 60).toFixed(1)}`
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 24 }) {
          Row({ space: 16 }) {
            Column() {
              Text('知').fontSize(36).fontWeight(FontWeight.Bold).fontColor(AppColors.ON_ACCENT)
            }
            .width(72).height(72).borderRadius(36)
            .backgroundColor(AppColors.PRIMARY).justifyContent(FlexAlign.Center)

            Column({ space: 4 }) {
              Text('知时用户').fontSize(20).fontWeight(FontWeight.Bold).fontColor(AppColors.TEXT_PRIMARY)
              Text('让每一分钟，都被看见').fontSize(13).fontColor(AppColors.TEXT_HINT)
            }
            .alignItems(HorizontalAlign.Start).layoutWeight(1)

            Text(`#${this.streakDays}`)
              .fontSize(14).fontWeight(FontWeight.Bold).fontColor(AppColors.WARNING)
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .backgroundColor(AppColors.WARNING_BG).borderRadius(12)
          }
          .width('100%').padding(24).backgroundColor(AppColors.BG_CARD).borderRadius(20)

          Row({ space: 0 }) {
            Column() {
              Text(this.formatHours(this.totalMinutes)).fontSize(26).fontWeight(FontWeight.Bold).fontColor(AppColors.PRIMARY)
              Text('小时').fontSize(12).fontColor(AppColors.TEXT_HINT)
            }.layoutWeight(1)
            Column() {
              Text(`${this.sessionCount}`).fontSize(26).fontWeight(FontWeight.Bold).fontColor(AppColors.FOCUS_ACTIVE)
              Text('次专注').fontSize(12).fontColor(AppColors.TEXT_HINT)
            }.layoutWeight(1)
            Column() {
              Text(`${this.streakDays}`).fontSize(26).fontWeight(FontWeight.Bold).fontColor(AppColors.WARNING)
              Text('天连续').fontSize(12).fontColor(AppColors.TEXT_HINT)
            }.layoutWeight(1)
          }
          .width('100%').padding(20).backgroundColor(AppColors.BG_CARD).borderRadius(16)

          Column({ space: 12 }) {
            Row() {
              Text('专注热力图').fontSize(15).fontWeight(FontWeight.Medium).fontColor(AppColors.TEXT_PRIMARY)
              Blank()
              Text(`连续 ${this.streakDays} 天`)
                .fontSize(11).fontWeight(FontWeight.Medium).fontColor(AppColors.WARNING)
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .backgroundColor(AppColors.WARNING_BG).borderRadius(8)
            }
            .width('100%')

            Row({ space: 4 }) {
              ForEach(this.heatWeeks, (week: HeatWeek) => {
                Column({ space: 4 }) {
                  ForEach(week.days, (day: HeatDay) => {
                    Column() {}
                      .width(12).height(12).borderRadius(3)
                      .backgroundColor(day.isBlank ? Color.Transparent : this.getHeatColor(day.level))
                  }, (day: HeatDay) => day.date)
                }
              }, (week: HeatWeek) => `${week.index}`)
            }
            .width('100%')

            if (this.heatActiveDays === 0) {
              Text('还没有专注记录，开始第一段专注吧')
                .fontSize(12).fontColor(AppColors.TEXT_HINT).width('100%')
            } else {
              Row() {
                Text(`近 12 周 ${this.heatActiveDays} 天有专注 · 共 ${this.formatHeatHours(this.heatTotalMinutes)} 小时`)
                  .fontSize(11).fontColor(AppColors.TEXT_HINT).layoutWeight(1)
                Row({ space: 3 }) {
                  Text('少').fontSize(10).fontColor(AppColors.TEXT_HINT)
                  ForEach(this.heatLegendLevels, (level: number) => {
                    Column() {}
                      .width(10).height(10).borderRadius(2)
                      .backgroundColor(this.getHeatColor(level))
                  }, (level: number) => `${level}`)
                  Text('多').fontSize(10).fontColor(AppColors.TEXT_HINT)
                }
              }
              .width('100%').alignItems(VerticalAlign.Center)
            }
          }
          .width('100%').padding(20).backgroundColor(AppColors.BG_CARD).borderRadius(16)

          Column({ space: 12 }) {
            Text('成就勋章').fontSize(15).fontWeight(FontWeight.Medium).fontColor(AppColors.TEXT_PRIMARY)
            Grid() {
              ForEach(this.achievements, (item: Achievement) => {
                GridItem() {
                  Column({ space: 3 }) {
                    Text(item.icon).fontSize(30).opacity(item.unlocked ? 1 : 0.25)
                    Text(item.title).fontSize(12).fontColor(AppColors.TEXT_SUBTLE).opacity(item.unlocked ? 1 : 0.35).maxLines(1)
                    Text(item.progressText)
                      .fontSize(9)
                      .fontColor(item.unlocked ? AppColors.SUCCESS : AppColors.TEXT_HINT)
                      .opacity(item.unlocked ? 1 : 0.6)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .textAlign(TextAlign.Center)
                      .width('100%')
                  }
                  .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
                  .width('100%').padding({ top: 14, bottom: 14 })
                  .backgroundColor(AppColors.BG_CARD).borderRadius(12)
                }
              })
            }
            .columnsTemplate('1fr 1fr 1fr 1fr').rowsGap(8).columnsGap(8).width('100%')
          }
          .width('100%').padding(20).backgroundColor(AppColors.BG_PRIMARY).borderRadius(16)

          Column() {
            Row() {
              Text('隐私政策').fontSize(15).fontColor(AppColors.TEXT_PRIMARY).layoutWeight(1)
              Text('>').fontSize(16).fontColor(AppColors.MUTED)
            }
            .width('100%').height(52).padding({ left: 16, right: 12 })
            .onClick(() => {
              const routeParams: Record<string, string> = {}
              routeParams['displayMode'] = 'view'
              router.pushUrl({ url: 'pages/PrivacyPolicyPage', params: routeParams })
            })
          }
          .width('100%').backgroundColor(AppColors.BG_CARD).borderRadius(16)

          Blank().height(20)
        }
        .padding({ left: 20, right: 20, bottom: 40 })
      }
      .layoutWeight(1).scrollBar(BarState.Off)
    }
    .width('100%').height('100%').backgroundColor(AppColors.BG_PRIMARY)
  }
}
