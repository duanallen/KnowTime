import { AppColors } from '../common/Theme'
import { DatabaseHelper } from '../database/DatabaseHelper'
import { common } from '@kit.AbilityKit'
import { router } from '@kit.ArkUI'

interface Achievement {
  icon: string
  title: string
  desc: string
  unlocked: boolean
}

@Entry
@Component
export struct ProfilePage {
  @StorageLink('isDarkMode') isDarkMode: boolean = false
  @Prop @Watch('onRefresh') refreshKey: number = 0
  @State totalMinutes: number = 0
  @State sessionCount: number = 0
  @State streakDays: number = 0
  @State achievements: Achievement[] = [
    { icon: '🔥', title: '初识专注', desc: '完成第一次专注', unlocked: false },
    { icon: '⭐', title: '连续7天', desc: '连续7天专注', unlocked: false },
    { icon: '💎', title: '百时达人', desc: '累计100小时', unlocked: false },
    { icon: '🌟', title: '心流大师', desc: '心流得分>90', unlocked: false },
    { icon: '🌅', title: '早起冠军', desc: '连续5天早6点', unlocked: false },
    { icon: '🏆', title: '目标达成', desc: '完成周目标', unlocked: false },
    { icon: '🎯', title: '专注猎人', desc: '单次>120分钟', unlocked: false },
    { icon: '📚', title: '书虫', desc: '阅读累计10h', unlocked: false },
  ]
  private db: DatabaseHelper = DatabaseHelper.getInstance()
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
    this.streakDays = await this.calcStreak()

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

    // 判定全部 8 个成就勋章
    const newAchievements: Achievement[] = [
      { icon: '🔥', title: '初识专注', desc: '完成第一次专注', unlocked: this.sessionCount >= 1 },
      { icon: '⭐', title: '连续7天', desc: '连续7天专注', unlocked: this.streakDays >= 7 },
      { icon: '💎', title: '百时达人', desc: '累计100小时', unlocked: this.totalMinutes >= 6000 },
      { icon: '🌟', title: '心流大师', desc: '心流得分>90', unlocked: maxFlowScore > 90 },
      { icon: '🌅', title: '早起冠军', desc: '连续5天早6点', unlocked: earlyMorningDays >= 5 },
      { icon: '🏆', title: '目标达成', desc: '完成周目标', unlocked: weekTotalMinutes >= 300 },
      { icon: '🎯', title: '专注猎人', desc: '单次>120分钟', unlocked: maxSingleDuration > 120 * 60 },
      { icon: '📚', title: '书虫', desc: '阅读累计10h', unlocked: readingTotalSeconds >= 10 * 60 * 60 },
    ]
    this.achievements = newAchievements
  }

  private async calcStreak(): Promise<number> {
    let streak = 0
    const now = new Date()
    for (let i = 0; i < 365; i++) {
      const check = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i)
      check.setHours(0, 0, 0, 0)
      const from = check.getTime()
      const count = await this.db.getSessionCount(from, from + 86400000)
      if (count > 0) { streak++ }
      else if (i === 0) { continue }
      else { break }
    }
    return streak
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
            Text('成就勋章').fontSize(15).fontWeight(FontWeight.Medium).fontColor(AppColors.TEXT_PRIMARY)
            Grid() {
              ForEach(this.achievements, (item: Achievement) => {
                GridItem() {
                  Column({ space: 4 }) {
                    Text(item.icon).fontSize(30).opacity(item.unlocked ? 1 : 0.25)
                    Text(item.title).fontSize(12).fontColor(AppColors.TEXT_SUBTLE).opacity(item.unlocked ? 1 : 0.35).maxLines(1)
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
