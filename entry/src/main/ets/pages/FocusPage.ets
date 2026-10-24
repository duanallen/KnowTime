import { FocusViewModel } from '../viewmodel/FocusViewModel'
import { FocusState, SessionType } from '../models/FocusSession'
import { AppColors } from '../common/Theme'
import { TimerRing } from '../components/TimerRing'
import { common } from '@kit.AbilityKit'
import { promptAction } from '@kit.ArkUI'
import { preferences } from '@kit.ArkData'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { DatabaseHelper } from '../database/DatabaseHelper'
import { FocusStatsService } from '../viewmodel/FocusStatsService'
import { TagService, DEFAULT_TAGS } from '../services/TagService'
import { WhiteNoiseService, WHITE_NOISE_OFF } from '../services/WhiteNoiseService'
import vibrator from '@ohos.vibrator'

const DOMAIN = 0x0001
const TAG = 'FocusPage'

@Entry
@Component
export struct FocusPage {
  @StorageLink('isDarkMode') isDarkMode: boolean = false
  @State taskName: string = '深度学习'
  @State selectedTag: string = '学习'
  @State selectedDuration: number = 25
  @State showCustomDurationDialog: boolean = false
  @State customDurationInput: string = ''
  
  // 今日统计 - 使用独立的 @State 变量避免 ViewModel 异步初始化问题
  @State dailyTotalMinutes: number = 0
  @State todaySessionsCount: number = 0
  @State maxFlowScore: number = 0
  // 每日目标（分钟），从 settings_prefs 读取
  @State dailyGoal: number = 60
  // 停止按钮状态
  @State showStopButton: boolean = false
  
  private durationOptions: number[] = [15, 25, 45, 60, 90]
  // 标签列表改为 @State，从 TagService 加载（设置页可自定义增删）
  @State tagOptions: string[] = DEFAULT_TAGS.slice()
  private viewModel: FocusViewModel = new FocusViewModel()
  private db: DatabaseHelper = DatabaseHelper.getInstance()
  
  // 刷新机制 - 当此值变化时触发今日统计刷新
  @Prop @Watch('onRefresh') refreshKey: number = 0
  
  // 记录之前的专注状态，用于判断是否完成
  private previousFocusState: FocusState = FocusState.IDLE
  // 状态检查定时器
  private stateCheckTimerId: number = -1
  // 防止重复刷新的标记
  private isRefreshing: boolean = false
  // 页面可见性（白噪音只在页面可见且专注 RUNNING 时播放）
  private pageVisible: boolean = true
  
  async aboutToAppear(): Promise<void> {
    const ctx = getContext(this) as common.UIAbilityContext
    hilog.info(DOMAIN, TAG, 'aboutToAppear start')
    
    try {
      await this.db.init(ctx)
      hilog.info(DOMAIN, TAG, 'db.init done')
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'db.init failed: %{public}s', (e as Error).message)
    }

    // 读取设置页配置的默认专注时长（未配置时为 25 分钟）与每日目标（未配置时为 60 分钟）
    try {
      const prefs: preferences.Preferences = await preferences.getPreferences(ctx, 'settings_prefs')
      const defDur: number = await prefs.get('default_duration_minutes', 25) as number
      if (defDur >= 1 && defDur <= 180) {
        this.selectedDuration = defDur
      }
      const goal: number = await prefs.get('daily_goal_minutes', 60) as number
      if (goal >= 0 && goal <= 1440) {
        this.dailyGoal = goal
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'load default duration failed: %{public}s', (e as Error).message)
    }

    // 加载自定义标签列表（服务内部在无持久化数据时回退内置默认）
    await this.loadTags()

    // 检查权限
    try {
      const hasPermission = await this.viewModel.checkPermissions()
      hilog.info(DOMAIN, TAG, 'Permission check done: %{public}s', hasPermission ? 'granted' : 'denied')
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Permission check failed: %{public}s', (e as Error).message)
    }
    
    await this.loadTodayStats(true)  // 首次加载用 setTimeout(0) 确保刷新
    hilog.info(DOMAIN, TAG, 'loadTodayStats done')
    
    try {
      await this.viewModel.init(ctx)
      hilog.info(DOMAIN, TAG, 'viewModel.init done')
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'viewModel.init failed: %{public}s', (e as Error).message)
    }
    
    // 启动状态检查定时器，每500ms检查一次专注状态
    this.stateCheckTimerId = setInterval(() => {
      this.syncTimerState()
    }, 500)
  }
  
  aboutToDisappear(): void {
    // 停止状态检查定时器
    if (this.stateCheckTimerId !== -1) {
      clearInterval(this.stateCheckTimerId)
      this.stateCheckTimerId = -1
    }
    // 页面销毁即停止白噪音（不承诺任何后台播放）
    WhiteNoiseService.getInstance().stop()
    this.viewModel.reset()
  }

  onPageShow(): void {
    // 页面恢复（如熄屏后亮屏返回）时，基于时间戳重新计算已用时长，
    // 确保熄屏期间计时正常累计，不受页面 inactive 导致 setInterval 挂起的影响
    this.pageVisible = true
    this.viewModel.setPageVisible(true)
    this.viewModel.recalculateElapsed()
    // 补偿恢复：页面重新可见且仍在专注中，按偏好补播白噪音
    if (this.viewModel.focusState === FocusState.RUNNING) {
      this.tryPlayWhiteNoise()
    }
  }

  onPageHide(): void {
    // 熄屏/切后台：页面不可见，到点改由系统闹钟负责响铃与震动
    this.pageVisible = false
    this.viewModel.setPageVisible(false)
    // 页面不可见立即停止白噪音（无后台保活）
    WhiteNoiseService.getInstance().stop()
  }
  
  private isLocked(): boolean {
    return this.viewModel.focusState !== FocusState.IDLE
  }
  
  private getStatusText(): string {
    if (this.viewModel.focusState === FocusState.RUNNING) return '专注中'
    if (this.viewModel.focusState === FocusState.PAUSED) return '已暂停'
    if (this.viewModel.focusState === FocusState.REMINDING) return '专注已完成'
    return ''
  }
  
  private getStatusColor(): string {
    if (this.viewModel.focusState === FocusState.RUNNING) return AppColors.FOCUS_ACTIVE
    if (this.viewModel.focusState === FocusState.PAUSED) return AppColors.REST
    if (this.viewModel.focusState === FocusState.REMINDING) return AppColors.REMIND_RED
    return AppColors.PRIMARY
  }
  
  // 刷新触发器 - 当 refreshKey 变化时重新加载今日统计
  onRefresh(): void {
    hilog.info(DOMAIN, TAG, 'onRefresh triggered')
    this.loadTodayStats(false)  // 后续刷新不需要 setTimeout
    this.loadTags()  // 设置页可能增删过标签，切回本页时同步
  }

  // 从 TagService 加载标签列表；当前选中标签已被删除时重置为列表第一项
  private async loadTags(): Promise<void> {
    try {
      const ctx = getContext(this) as common.UIAbilityContext
      const tags: string[] = await TagService.getInstance().getTags(ctx)
      if (tags.length > 0) {
        this.tagOptions = tags
      }
      if (this.tagOptions.indexOf(this.selectedTag) < 0) {
        this.selectedTag = this.tagOptions[0]
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'loadTags failed: %{public}s', (e as Error).message)
    }
  }
  // 加载今日统计数据 - 从数据库直接查询
  private async loadTodayStats(useDelay: boolean = false): Promise<void> {
    try {
      const sessions = await this.db.queryTodaySessions()
      hilog.info(DOMAIN, TAG, 'queryTodaySessions: %{public}d sessions', sessions.length)
      
      // 计算总分钟数
      let totalSeconds = 0
      let maxFlow = 0
      for (let i = 0; i < sessions.length; i++) {
        totalSeconds += sessions[i].actualDuration
        if (sessions[i].flowScore > maxFlow) maxFlow = sessions[i].flowScore
      }
      const total = Math.floor(totalSeconds / 60)

      // 同步读取每日目标，保证设置页修改后回到本页能即时生效
      let goal: number = this.dailyGoal
      try {
        const ctx = getContext(this) as common.UIAbilityContext
        const prefs: preferences.Preferences = await preferences.getPreferences(ctx, 'settings_prefs')
        goal = await prefs.get('daily_goal_minutes', 60) as number
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'load daily goal failed: %{public}s', (e as Error)?.message)
      }

      hilog.info(DOMAIN, TAG, 'loadTodayStats result: minutes=%{public}d count=%{public}d flow=%{public}d',
        total, sessions.length, maxFlow)

      // ArkUI @State 在 aboutToAppear 中使用 setTimeout(0) 确保触发刷新
      const updateUI = () => {
        this.todaySessionsCount = sessions.length
        this.dailyTotalMinutes = total
        this.maxFlowScore = maxFlow
        if (goal >= 0 && goal <= 1440) {
          this.dailyGoal = goal
        }
        hilog.info(DOMAIN, TAG, 'UI state updated: minutes=%{public}d count=%{public}d flow=%{public}d',
          this.dailyTotalMinutes, this.todaySessionsCount, this.maxFlowScore)
      }
      
      if (useDelay) {
        setTimeout(updateUI, 0)
      } else {
        updateUI()
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'loadTodayStats failed: %{public}s', (e as Error)?.message)
    }
  }
  
  // 同步计时状态 - 当专注完成时刷新今日统计
  private syncTimerState(): void {
    const currentFocusState = this.viewModel.focusState
    
    // 当从运行/暂停状态变为空闲状态时，说明专注完成了
    if (currentFocusState === FocusState.IDLE && 
        (this.previousFocusState === FocusState.RUNNING || this.previousFocusState === FocusState.PAUSED)) {
      hilog.info(DOMAIN, TAG, 'Focus completed, refreshing today stats')
      // 防止重复刷新
      if (!this.isRefreshing) {
        this.isRefreshing = true
        // 记录刷新前的今日总分钟，用于达标跨越判断
        const prevTotal: number = this.dailyTotalMinutes
        // 延迟刷新，确保数据库操作完成
        setTimeout(() => {
          this.loadTodayStats(false).then(() => {
            this.checkGoalCelebration(prevTotal)
            this.isRefreshing = false
          })
        }, 300)
      }
    }
    
    // 更新提醒状态
    this.checkReminderState()

    // 白噪音联动：专注状态变化时按规则播放/停止
    if (currentFocusState !== this.previousFocusState) {
      this.onFocusStateForWhiteNoise(currentFocusState)
    }

    this.previousFocusState = currentFocusState
  }
  
  // 检查提醒状态
  private checkReminderState(): void {
    this.showStopButton = this.viewModel.isReminding
  }

  // 白噪音联动：进入 RUNNING 播放；暂停/完成/中断/提醒/回到空闲均停止
  // （暂停后恢复会再次进入 RUNNING，届时按规则重新播放）
  private onFocusStateForWhiteNoise(state: FocusState): void {
    if (state === FocusState.RUNNING) {
      this.tryPlayWhiteNoise()
    } else if (state === FocusState.PAUSED ||
               state === FocusState.IDLE ||
               state === FocusState.COMPLETED ||
               state === FocusState.INTERRUPTED ||
               state === FocusState.REMINDING) {
      WhiteNoiseService.getInstance().stop()
    }
  }

  // 读取白噪音偏好：非关闭且页面可见时播放；任何失败仅记日志，不影响专注流程
  private async tryPlayWhiteNoise(): Promise<void> {
    if (!this.pageVisible) return
    try {
      const ctx = getContext(this) as common.UIAbilityContext
      const prefs: preferences.Preferences = await preferences.getPreferences(ctx, 'settings_prefs')
      const type: string = await prefs.get('white_noise_type', WHITE_NOISE_OFF) as string
      if (type === WHITE_NOISE_OFF) return
      await WhiteNoiseService.getInstance().play(ctx, type)
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'white noise play failed: %{public}s', (e as Error).message)
    }
  }

  /**
   * 达标庆祝：本次专注使今日总分钟从 < 目标 跨越到 >= 目标，且今天未庆祝过时弹窗。
   * 庆祝记录存 preferences key 'goal_celebrated_date'（yyyy-MM-dd），一天只弹一次。
   */
  private async checkGoalCelebration(prevTotal: number): Promise<void> {
    if (this.dailyGoal <= 0) return
    if (prevTotal >= this.dailyGoal) return
    if (this.dailyTotalMinutes < this.dailyGoal) return
    try {
      const ctx = getContext(this) as common.UIAbilityContext
      const prefs: preferences.Preferences = await preferences.getPreferences(ctx, 'settings_prefs')
      const d: Date = new Date()
      const p = (n: number): string => n.toString().padStart(2, '0')
      const today: string = `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`
      const celebrated: string = await prefs.get('goal_celebrated_date', '') as string
      if (celebrated === today) return
      const streak: number = await FocusStatsService.getInstance().calcGoalStreak(this.dailyGoal)
      await prefs.put('goal_celebrated_date', today)
      await prefs.flush()
      promptAction.showDialog({
        title: '今日目标已达成',
        message: streak > 1 ? `连续 ${streak} 天达标，继续保持` : '今天的第一场达标，继续保持',
        buttons: [
          { text: '好的', color: AppColors.PRIMARY }
        ]
      })
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'checkGoalCelebration failed: %{public}s', (e as Error)?.message)
    }
  }

  build() {
    Stack() {
      // 主内容容器
      Column() {
        // 顶部今日统计 - 一屏显示，无需滚动
        if (this.todaySessionsCount > 0) {
          Column({ space: 12 }) {
          Text('今日')
            .fontSize(13).fontWeight(FontWeight.Medium).fontColor(AppColors.TEXT_PRIMARY)
            .textAlign(TextAlign.Center)
            .width('100%')
          
          Row({ space: 0 }) {
            Column() { 
              Text(`${this.dailyTotalMinutes}`).fontSize(24).fontWeight(FontWeight.Bold).fontColor(AppColors.PRIMARY);
              Text('分钟').fontSize(10).fontColor(AppColors.TEXT_HINT)
            }.layoutWeight(1)
            Column() {
              Text(`${this.todaySessionsCount}`).fontSize(24).fontWeight(FontWeight.Bold).fontColor(AppColors.FOCUS_ACTIVE);
              Text('次').fontSize(10).fontColor(AppColors.TEXT_HINT)
            }.layoutWeight(1)
            Column() {
              Text(`${this.maxFlowScore}`).fontSize(24).fontWeight(FontWeight.Bold).fontColor(AppColors.WARNING);
              Text('心流').fontSize(10).fontColor(AppColors.TEXT_HINT)
            }.layoutWeight(1)
          }
          .width('100%')
          .padding({ top: 12, bottom: 12, left: 8, right: 8 })
          .backgroundColor(AppColors.BG_CARD)
          .borderRadius(14)

          // 每日目标进度
          if (this.dailyGoal > 0) {
            Row({ space: 10 }) {
              Text(`今日 ${this.dailyTotalMinutes}/${this.dailyGoal} 分钟`)
                .fontSize(11).fontColor(AppColors.TEXT_HINT)
              Progress({ value: Math.min(this.dailyTotalMinutes, this.dailyGoal), total: this.dailyGoal, type: ProgressType.Linear })
                .color(AppColors.PRIMARY)
                .backgroundColor(AppColors.DIVIDER)
                .style({ strokeWidth: 4 })
                .layoutWeight(1)
            }
            .width('100%')
            .padding({ top: 8, bottom: 8, left: 12, right: 12 })
            .backgroundColor(AppColors.BG_CARD)
            .borderRadius(10)
          }
        }
        .width('100%')
        .margin({ top: 16, left: 16, right: 16 })
      }

      // 主要内容 - 可滚动区域
      Scroll() {
        Column({ space: 20 }) {
          // 计时器 - 缩小
          Column({ space: 6 }) {
            Stack({ alignContent: Alignment.Center }) {
              TimerRing({
                elapsedSeconds: this.viewModel.focusState === FocusState.RUNNING ? this.viewModel.elapsedSeconds : 0,
                totalSeconds: this.selectedDuration * 60,
                ringColor: this.getStatusColor(),
                ringWidth: 12,
                ringSize: 180
              })

              Column({ space: 4 }) {
                Text(this.viewModel.focusState === FocusState.IDLE ?
                  `${this.selectedDuration}:00` :
                  FocusViewModel.formatTime(this.viewModel.elapsedSeconds))
                  .fontSize(44).fontWeight(FontWeight.Bold)
                  .fontColor(AppColors.TEXT_PRIMARY).fontFamily('sans-serif-medium')

                if (this.viewModel.focusState !== FocusState.IDLE) {
                  Text(this.getStatusText())
                    .fontSize(14).fontWeight(FontWeight.Medium)
                    .fontColor(this.getStatusColor()).opacity(0.85)
                } else {
                  Text('准备好，开始一段专注时光')
                    .fontSize(12).fontColor(AppColors.TEXT_HINT)
                }
              }
            }
            .width('100%').height(190)
          }
          .padding({ top: 8 })

          // 任务输入（专注中也允许修改任务名）
          Row() {
            TextInput({ placeholder: '正在做什么？' })
              .fontSize(16).fontColor(AppColors.TEXT_BODY).placeholderColor(AppColors.MUTED)
              .backgroundColor(Color.Transparent).borderRadius(0).layoutWeight(1).height(40)
              .onChange((value: string) => {
                this.taskName = value
              })
          }
          .width('100%').padding({ left: 16, right: 16 })
          .backgroundColor(AppColors.BG_CARD).borderRadius(12)
          .border({ width: 1, color: AppColors.BORDER })

          // 标签区（专注中锁定不可选）
          Column({ space: 6 }) {
            Text('标签').fontSize(12).fontColor(AppColors.TEXT_HINT).padding({ left: 4 })
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.tagOptions, (tag: string) => {
                Text(tag)
                  .fontSize(12)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 }).margin({ right: 6, bottom: 6 })
                  .fontColor(this.getTagColor(tag))
                  .backgroundColor(this.getTagBg(tag))
                  .borderRadius(16)
                  .enabled(!this.isLocked())
                  .opacity(this.isLocked() && tag !== this.selectedTag ? 0.45 : 1)
                  .onClick(() => {
                    if (!this.isLocked()) { this.selectedTag = tag }
                  })
              })
            }
            .width('100%')
          }

          // 时长区（专注中锁定不可选）
          Column({ space: 6 }) {
            Text('时长').fontSize(12).fontColor(AppColors.TEXT_HINT).padding({ left: 4 })
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.durationOptions, (duration: number) => {
                Text(`${duration} 分钟`)
                  .fontSize(12)
                  .padding({ left: 14, right: 14, top: 6, bottom: 6 }).margin({ right: 6, bottom: 6 })
                  .fontColor(this.getDurationColor(duration))
                  .backgroundColor(this.getDurationBg(duration))
                  .borderRadius(16)
                  .enabled(!this.isLocked())
                  .opacity(this.isLocked() && duration !== this.selectedDuration ? 0.45 : 1)
                  .onClick(() => {
                    if (!this.isLocked()) { this.selectedDuration = duration }
                  })
              })

              // 自定义时长按钮
              if (!this.isLocked()) {
                Text(this.durationOptions.includes(this.selectedDuration) ? '自定义' : `${this.selectedDuration} 分钟`)
                  .fontSize(12)
                  .padding({ left: 14, right: 14, top: 6, bottom: 6 }).margin({ right: 6, bottom: 6 })
                  .fontColor(this.durationOptions.includes(this.selectedDuration) ? AppColors.TEXT_SECONDARY : AppColors.ON_ACCENT)
                  .backgroundColor(this.durationOptions.includes(this.selectedDuration) ? AppColors.DIVIDER : AppColors.PRIMARY)
                  .borderRadius(16)
                  .onClick(() => {
                    this.showCustomDurationDialog = true
                    this.customDurationInput = this.selectedDuration.toString()
                  })
              }
            }
            .width('100%')
          }

          // 按钮
          Column({ space: 12 }) {
            if (this.viewModel.focusState === FocusState.IDLE) {
              Button('开始专注')
                .fontSize(16).fontWeight(FontWeight.Bold).fontColor(AppColors.ON_ACCENT)
                .width('100%').height(48)
                .backgroundColor(AppColors.PRIMARY).borderRadius(24)
                .shadow({ radius: 8, color: AppColors.PRIMARY_SHADOW, offsetY: 4 })
                .onClick(() => {
                  this.viewModel.startSession(this.taskName, this.selectedTag, this.selectedDuration * 60, SessionType.DEEP_FOCUS)
                    .then((reminderRegistered: boolean) => {
                      if (!reminderRegistered) {
                        promptAction.showToast({ message: '系统提醒注册失败，请在 设置→通知 中开启知时的通知权限，否则熄屏后无法响铃' })
                      }
                    })
                })
            } else if (this.viewModel.focusState === FocusState.RUNNING) {
              Row({ space: 12 }) {
                Button('暂停')
                  .fontSize(14).fontColor(AppColors.REST)
                  .backgroundColor(AppColors.REST_BG).borderRadius(22).height(44).layoutWeight(1)
                  .onClick(() => { this.viewModel.pauseSession() })
                Button('提前结束')
                  .fontSize(14).fontColor(AppColors.ON_ACCENT)
                  .backgroundColor(AppColors.TEXT_HINT).borderRadius(22).height(44).layoutWeight(2)
                  .onClick(async () => { 
                    await this.viewModel.stopSession()
                    this.syncTimerState()  // 完成后刷新统计
                  })
              }
              .width('100%')
            } else if (this.viewModel.focusState === FocusState.PAUSED) {
              Row({ space: 12 }) {
                Button('继续')
                  .fontSize(15).fontWeight(FontWeight.Bold).fontColor(AppColors.ON_ACCENT)
                  .backgroundColor(AppColors.FOCUS_ACTIVE).borderRadius(22).height(44).layoutWeight(1)
                  .onClick(() => { this.viewModel.resumeSession() })
                Button('结束')
                  .fontSize(14).fontColor(AppColors.TEXT_SECONDARY)
                  .backgroundColor(AppColors.DIVIDER).borderRadius(22).height(44).layoutWeight(1)
                  .onClick(async () => { 
                    await this.viewModel.stopSession()
                    this.syncTimerState()  // 完成后刷新统计
                  })
              }
              .width('100%')
            }
            // REMINDING 状态不显示按钮，因为会显示覆盖层
          }

          Blank().height(16)
        }
        .padding({ left: 16, right: 16, bottom: 40 })
      }
      .layoutWeight(1).scrollBar(BarState.Off)

      // 自定义时长弹窗
      if (this.showCustomDurationDialog) {
        Stack({ alignContent: Alignment.Center }) {
          Column({ space: 20 }) {
            Text('自定义时长')
              .fontSize(18).fontWeight(FontWeight.Bold).fontColor(AppColors.TEXT_PRIMARY)
            Text('设置专注时长（1-180 分钟）')
              .fontSize(13).fontColor(AppColors.TEXT_HINT).margin({ top: -12 })
            TextInput({ placeholder: '输入分钟数' })
              .fontSize(28).fontWeight(FontWeight.Bold).fontColor(AppColors.TEXT_PRIMARY)
              .type(InputType.Number).maxLength(3)
              .textAlign(TextAlign.Center)
              .width('60%').height(48)
              .backgroundColor(AppColors.DIVIDER).borderRadius(12)
              .onChange((value: string) => {
                this.customDurationInput = value.replace(/[^0-9]/g, '')
              })
            Row({ space: 12 }) {
              Button('取消')
                .fontSize(14).fontColor(AppColors.TEXT_SECONDARY)
                .backgroundColor(AppColors.DIVIDER).borderRadius(22).height(44).layoutWeight(1)
                .onClick(() => {
                  this.showCustomDurationDialog = false
                })
              Button('确定')
                .fontSize(14).fontWeight(FontWeight.Bold).fontColor(AppColors.ON_ACCENT)
                .backgroundColor(AppColors.PRIMARY).borderRadius(22).height(44).layoutWeight(1)
                .onClick(() => {
                  const val = parseInt(this.customDurationInput)
                  if (!isNaN(val) && val >= 1 && val <= 180) {
                    this.selectedDuration = val
                    this.showCustomDurationDialog = false
                  }
                })
            }
            .width('100%')
          }
          .width('78%').padding(24)
          .backgroundColor(AppColors.BG_CARD).borderRadius(20)
          .shadow({ radius: 20, color: AppColors.CARD_SHADOW })
        }
        .width('100%').height('100%')
        .backgroundColor(AppColors.MASK)
        .position({ x: 0, y: 0 })
        .onClick(() => {
          this.showCustomDurationDialog = false
        })
      }
    }
    .width('100%').height('100%').backgroundColor(AppColors.BG_PRIMARY)
    
    // 停止按钮覆盖层
      if (this.showStopButton) {
        Stack() {
          // 半透明遮罩
          Rect()
            .fill(AppColors.MASK_STRONG)
            .width('100%')
            .height('100%')

          Column() {
            Text('专注已完成')
              .fontSize(20).fontWeight(FontWeight.Bold)
              .fontColor(AppColors.ON_ACCENT).margin({ bottom: 16 })

            Text('点击停止提醒')
              .fontSize(14).fontColor(AppColors.TEXT_SECONDARY)

            Button('停止提醒')
              .fontSize(16).fontWeight(FontWeight.Bold).fontColor(AppColors.ON_ACCENT)
              .width(200).height(50).margin({ top: 24 })
              .backgroundColor(AppColors.REMIND_RED).borderRadius(25)
              .onClick(() => {
                this.viewModel.stopReminder()
              })
          }
          .padding(32)
          .backgroundColor(AppColors.BG_CARD)
          .borderRadius(20)
        }
        .width('100%').height('100%')
        .position({ x: 0, y: 0 })
        .zIndex(1000)
}
      }
    }
  
  private getTagColor(tag: string): string {
    if (tag === this.selectedTag) return AppColors.ON_ACCENT
    if (this.isLocked()) return AppColors.TEXT_HINT
    return AppColors.TEXT_SECONDARY
  }

  private getTagBg(tag: string): string {
    if (tag === this.selectedTag) return AppColors.PRIMARY
    return AppColors.DIVIDER
  }

  private getDurationColor(dur: number): string {
    if (dur === this.selectedDuration) return AppColors.ON_ACCENT
    if (this.isLocked()) return AppColors.TEXT_HINT
    return AppColors.TEXT_SECONDARY
  }

  private getDurationBg(dur: number): string {
    if (dur === this.selectedDuration) return AppColors.PRIMARY
    return AppColors.DIVIDER
  }
}