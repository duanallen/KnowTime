import { FocusViewModel } from '../viewmodel/FocusViewModel'
import { FocusState, SessionType } from '../models/FocusSession'
import { AppColors } from '../common/Theme'
import { TimerRing } from '../components/TimerRing'
import { common } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { DatabaseHelper } from '../database/DatabaseHelper'

const DOMAIN = 0x0001
const TAG = 'FocusPage'

@Entry
@Component
export struct FocusPage {
  @State taskName: string = '深度学习'
  @State selectedTag: string = '学习'
  @State selectedDuration: number = 25
  @State showCustomDurationDialog: boolean = false
  @State customDurationInput: string = ''
  
  // 今日统计 - 使用独立的 @State 变量避免 ViewModel 异步初始化问题
  @State dailyTotalMinutes: number = 0
  @State todaySessionsCount: number = 0
  @State maxFlowScore: number = 0
  
  private durationOptions: number[] = [15, 25, 45, 60, 90]
  private tagOptions: string[] = ['学习', '工作', '阅读', '写作', '编程', '设计', '运动']
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
  
  async aboutToAppear(): Promise<void> {
    const ctx = getContext(this) as common.UIAbilityContext
    hilog.info(DOMAIN, TAG, 'aboutToAppear start')
    
    try {
      await this.db.init(ctx)
      hilog.info(DOMAIN, TAG, 'db.init done')
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'db.init failed: %{public}s', (e as Error).message)
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
    this.viewModel.reset()
  }
  
  private isLocked(): boolean {
    return this.viewModel.focusState !== FocusState.IDLE
  }
  
  private getStatusText(): string {
    if (this.viewModel.focusState === FocusState.RUNNING) return '专注中'
    if (this.viewModel.focusState === FocusState.PAUSED) return '已暂停'
    return ''
  }
  
  private getStatusColor(): string {
    if (this.viewModel.focusState === FocusState.RUNNING) return AppColors.FOCUS_ACTIVE
    if (this.viewModel.focusState === FocusState.PAUSED) return AppColors.REST
    return AppColors.PRIMARY
  }
  
  // 刷新触发器 - 当 refreshKey 变化时重新加载今日统计
  onRefresh(): void {
    hilog.info(DOMAIN, TAG, 'onRefresh triggered')
    this.loadTodayStats(false)  // 后续刷新不需要 setTimeout
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
      
      hilog.info(DOMAIN, TAG, 'loadTodayStats result: minutes=%{public}d count=%{public}d flow=%{public}d',
        total, sessions.length, maxFlow)
      
      // ArkUI @State 在 aboutToAppear 中使用 setTimeout(0) 确保触发刷新
      const updateUI = () => {
        this.todaySessionsCount = sessions.length
        this.dailyTotalMinutes = total
        this.maxFlowScore = maxFlow
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
        // 延迟刷新，确保数据库操作完成
        setTimeout(() => {
          this.loadTodayStats(false)
          this.isRefreshing = false
        }, 300)
      }
    }
    
    this.previousFocusState = currentFocusState
  }

  build() {
    Column() {
      // 顶部今日统计 - 一屏显示，无需滚动
      if (this.todaySessionsCount > 0) {
        Column({ space: 12 }) {
          Text('今日')
            .fontSize(13).fontWeight(FontWeight.Medium).fontColor('#1E293B')
            .textAlign(TextAlign.Center)
            .width('100%')
          
          Row({ space: 0 }) {
            Column() { 
              Text(`${this.dailyTotalMinutes}`).fontSize(24).fontWeight(FontWeight.Bold).fontColor(AppColors.PRIMARY); 
              Text('分钟').fontSize(10).fontColor('#94A3B8') 
            }.layoutWeight(1)
            Column() { 
              Text(`${this.todaySessionsCount}`).fontSize(24).fontWeight(FontWeight.Bold).fontColor(AppColors.FOCUS_ACTIVE); 
              Text('次').fontSize(10).fontColor('#94A3B8') 
            }.layoutWeight(1)
            Column() { 
              Text(`${this.maxFlowScore}`).fontSize(24).fontWeight(FontWeight.Bold).fontColor('#F59E0B'); 
              Text('心流').fontSize(10).fontColor('#94A3B8') 
            }.layoutWeight(1)
          }
          .width('100%')
          .padding({ top: 12, bottom: 12, left: 8, right: 8 })
          .backgroundColor('#FFFFFF')
          .borderRadius(14)
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
                  .fontColor('#1E293B').fontFamily('sans-serif-medium')

                if (this.viewModel.focusState !== FocusState.IDLE) {
                  Text(this.getStatusText())
                    .fontSize(14).fontWeight(FontWeight.Medium)
                    .fontColor(this.getStatusColor()).opacity(0.85)
                } else {
                  Text('准备好，开始一段专注时光')
                    .fontSize(12).fontColor('#94A3B8')
                }
              }
            }
            .width('100%').height(190)
          }
          .padding({ top: 8 })

          // 任务输入（专注中也允许修改任务名）
          Row() {
            TextInput({ text: $$this.taskName, placeholder: '正在做什么？' })
              .fontSize(16).fontColor('#334155').placeholderColor('#CBD5E1')
              .backgroundColor(Color.Transparent).borderRadius(0).layoutWeight(1).height(40)
          }
          .width('100%').padding({ left: 16, right: 16 })
          .backgroundColor('#FFFFFF').borderRadius(12)
          .border({ width: 1, color: '#E2E8F0' })

          // 标签区（专注中锁定不可选）
          Column({ space: 6 }) {
            Text('标签').fontSize(12).fontColor('#94A3B8').padding({ left: 4 })
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
            Text('时长').fontSize(12).fontColor('#94A3B8').padding({ left: 4 })
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
                  .fontColor(this.durationOptions.includes(this.selectedDuration) ? '#64748B' : '#FFFFFF')
                  .backgroundColor(this.durationOptions.includes(this.selectedDuration) ? '#F1F5F9' : AppColors.PRIMARY)
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
                .fontSize(16).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
                .width('100%').height(48)
                .backgroundColor(AppColors.PRIMARY).borderRadius(24)
                .shadow({ radius: 8, color: '#1A73E830', offsetY: 4 })
                .onClick(() => {
                  this.viewModel.startSession(this.taskName, this.selectedTag, this.selectedDuration * 60, SessionType.DEEP_FOCUS)
                })
            } else if (this.viewModel.focusState === FocusState.RUNNING) {
              Row({ space: 12 }) {
                Button('暂停')
                  .fontSize(14).fontColor(AppColors.REST)
                  .backgroundColor('#FFFBEB').borderRadius(22).height(44).layoutWeight(1)
                  .onClick(() => { this.viewModel.pauseSession() })
                Button('提前结束')
                  .fontSize(14).fontColor('#FFFFFF')
                  .backgroundColor('#94A3B8').borderRadius(22).height(44).layoutWeight(2)
                  .onClick(async () => { 
                    await this.viewModel.stopSession()
                    this.syncTimerState()  // 完成后刷新统计
                  })
              }
              .width('100%')
            } else if (this.viewModel.focusState === FocusState.PAUSED) {
              Row({ space: 12 }) {
                Button('继续')
                  .fontSize(15).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
                  .backgroundColor(AppColors.FOCUS_ACTIVE).borderRadius(22).height(44).layoutWeight(1)
                  .onClick(() => { this.viewModel.resumeSession() })
                Button('结束')
                  .fontSize(14).fontColor('#64748B')
                  .backgroundColor('#F1F5F9').borderRadius(22).height(44).layoutWeight(1)
                  .onClick(async () => { 
                    await this.viewModel.stopSession()
                    this.syncTimerState()  // 完成后刷新统计
                  })
              }
              .width('100%')
            }
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
              .fontSize(18).fontWeight(FontWeight.Bold).fontColor('#1E293B')
            Text('设置专注时长（1-180 分钟）')
              .fontSize(13).fontColor('#94A3B8').margin({ top: -12 })
            TextInput({ text: $$this.customDurationInput, placeholder: '输入分钟数' })
              .fontSize(28).fontWeight(FontWeight.Bold).fontColor('#1E293B')
              .type(InputType.Number).maxLength(3)
              .textAlign(TextAlign.Center)
              .width('60%').height(48)
              .backgroundColor('#F1F5F9').borderRadius(12)
              .onChange((value: string) => {
                this.customDurationInput = value.replace(/[^0-9]/g, '')
              })
            Row({ space: 12 }) {
              Button('取消')
                .fontSize(14).fontColor('#64748B')
                .backgroundColor('#F1F5F9').borderRadius(22).height(44).layoutWeight(1)
                .onClick(() => {
                  this.showCustomDurationDialog = false
                })
              Button('确定')
                .fontSize(14).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
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
          .backgroundColor('#FFFFFF').borderRadius(20)
          .shadow({ radius: 20, color: '#00000020' })
        }
        .width('100%').height('100%')
        .backgroundColor('#00000050')
        .position({ x: 0, y: 0 })
        .onClick(() => {
          this.showCustomDurationDialog = false
        })
      }
    }
    .width('100%').height('100%').backgroundColor('#F8FAFC')
  }

  private getTagColor(tag: string): string {
    if (tag === this.selectedTag) return '#FFFFFF'
    if (this.isLocked()) return '#94A3B8'
    return '#64748B'
  }

  private getTagBg(tag: string): string {
    if (tag === this.selectedTag) return AppColors.PRIMARY
    return '#F1F5F9'
  }

  private getDurationColor(dur: number): string {
    if (dur === this.selectedDuration) return '#FFFFFF'
    if (this.isLocked()) return '#94A3B8'
    return '#64748B'
  }

  private getDurationBg(dur: number): string {
    if (dur === this.selectedDuration) return AppColors.PRIMARY
    return '#F1F5F9'
  }
}