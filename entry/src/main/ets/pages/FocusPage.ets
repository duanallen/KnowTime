import { FocusViewModel } from '../viewmodel/FocusViewModel'
import { FocusState, SessionType } from '../models/FocusSession'
import { AppColors } from '../common/Theme'
import { TimerRing } from '../components/TimerRing'
import { common } from '@kit.AbilityKit'

@Entry
@Component
export struct FocusPage {
  @State taskName: string = '深度学习'
  @State selectedTag: string = '学习'
  @State selectedDuration: number = 25
  @State showCustomDurationDialog: boolean = false
  @State customDurationInput: string = ''
  private durationOptions: number[] = [15, 25, 45, 60, 90]
  private tagOptions: string[] = ['学习', '工作', '阅读', '写作', '编程', '设计', '运动']
  private viewModel: FocusViewModel = new FocusViewModel()

  async aboutToAppear(): Promise<void> {
    const ctx = getContext(this) as common.UIAbilityContext
    await this.viewModel.init(ctx)
  }

  aboutToDisappear(): void {
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

  private getMaxFlowScore(): number {
    let max = 0
    const sessions = this.viewModel.todaySessions
    for (let i = 0; i < sessions.length; i++) {
      if (sessions[i].flowScore > max) max = sessions[i].flowScore
    }
    return max
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 28 }) {
          // 计时器
          Column({ space: 8 }) {
            Stack({ alignContent: Alignment.Center }) {
              TimerRing({
                elapsedSeconds: this.viewModel.focusState === FocusState.RUNNING ? this.viewModel.elapsedSeconds : 0,
                totalSeconds: this.selectedDuration * 60,
                ringColor: this.getStatusColor(),
                ringWidth: 14,
                ringSize: 220
              })

              Column({ space: 6 }) {
                Text(this.viewModel.focusState === FocusState.IDLE ?
                  `${this.selectedDuration}:00` :
                  FocusViewModel.formatTime(this.viewModel.elapsedSeconds))
                  .fontSize(56).fontWeight(FontWeight.Bold)
                  .fontColor('#1E293B').fontFamily('sans-serif-medium')

                if (this.viewModel.focusState !== FocusState.IDLE) {
                  Text(this.getStatusText())
                    .fontSize(16).fontWeight(FontWeight.Medium)
                    .fontColor(this.getStatusColor()).opacity(0.85)
                } else {
                  Text('准备好，开始一段专注时光')
                    .fontSize(14).fontColor('#94A3B8')
                }
              }
            }
            .width('100%').height(240)
          }
          .padding({ top: 16 })

          // 任务输入（专注中也允许修改任务名）
          Row() {
            TextInput({ text: $$this.taskName, placeholder: '正在做什么？' })
              .fontSize(18).fontColor('#334155').placeholderColor('#CBD5E1')
              .backgroundColor(Color.Transparent).borderRadius(0).layoutWeight(1).height(44)
          }
          .width('100%').padding({ left: 16, right: 16 })
          .backgroundColor('#FFFFFF').borderRadius(14)
          .border({ width: 1, color: '#E2E8F0' })

          // 标签区（专注中锁定不可选）
          Column({ space: 6 }) {
            Text('标签').fontSize(13).fontColor('#94A3B8').padding({ left: 4 })
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.tagOptions, (tag: string) => {
                Text(tag)
                  .fontSize(13)
                  .padding({ left: 14, right: 14, top: 8, bottom: 8 }).margin({ right: 8, bottom: 8 })
                  .fontColor(this.getTagColor(tag))
                  .backgroundColor(this.getTagBg(tag))
                  .borderRadius(20)
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
            Text('时长').fontSize(13).fontColor('#94A3B8').padding({ left: 4 })
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.durationOptions, (duration: number) => {
                Text(`${duration} 分钟`)
                  .fontSize(13)
                  .padding({ left: 16, right: 16, top: 8, bottom: 8 }).margin({ right: 8, bottom: 8 })
                  .fontColor(this.getDurationColor(duration))
                  .backgroundColor(this.getDurationBg(duration))
                  .borderRadius(20)
                  .enabled(!this.isLocked())
                  .opacity(this.isLocked() && duration !== this.selectedDuration ? 0.45 : 1)
                  .onClick(() => {
                    if (!this.isLocked()) { this.selectedDuration = duration }
                  })
              })

              // 自定义时长按钮
              if (!this.isLocked()) {
                Text(this.durationOptions.includes(this.selectedDuration) ? '自定义' : `${this.selectedDuration} 分钟`)
                  .fontSize(13)
                  .padding({ left: 16, right: 16, top: 8, bottom: 8 }).margin({ right: 8, bottom: 8 })
                  .fontColor(this.durationOptions.includes(this.selectedDuration) ? '#64748B' : '#FFFFFF')
                  .backgroundColor(this.durationOptions.includes(this.selectedDuration) ? '#F1F5F9' : AppColors.PRIMARY)
                  .borderRadius(20)
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
                .fontSize(17).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
                .width('100%').height(54)
                .backgroundColor(AppColors.PRIMARY).borderRadius(27)
                .shadow({ radius: 8, color: '#1A73E830', offsetY: 4 })
                .onClick(() => {
                  this.viewModel.startSession(this.taskName, this.selectedTag, this.selectedDuration * 60, SessionType.DEEP_FOCUS)
                })
            } else if (this.viewModel.focusState === FocusState.RUNNING) {
              Row({ space: 12 }) {
                Button('暂停')
                  .fontSize(15).fontColor(AppColors.REST)
                  .backgroundColor('#FFFBEB').borderRadius(24).height(48).layoutWeight(1)
                  .onClick(() => { this.viewModel.pauseSession() })
                Button('提前结束')
                  .fontSize(15).fontColor('#FFFFFF')
                  .backgroundColor('#94A3B8').borderRadius(24).height(48).layoutWeight(2)
                  .onClick(async () => { await this.viewModel.stopSession() })
              }
              .width('100%')
            } else if (this.viewModel.focusState === FocusState.PAUSED) {
              Row({ space: 12 }) {
                Button('继续')
                  .fontSize(16).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
                  .backgroundColor(AppColors.FOCUS_ACTIVE).borderRadius(24).height(48).layoutWeight(1)
                  .onClick(() => { this.viewModel.resumeSession() })
                Button('结束')
                  .fontSize(15).fontColor('#64748B')
                  .backgroundColor('#F1F5F9').borderRadius(24).height(48).layoutWeight(1)
                  .onClick(async () => { await this.viewModel.stopSession() })
              }
              .width('100%')
            }
          }

          // 今日统计
          if (this.viewModel.todaySessions.length > 0) {
            Column({ space: 14 }) {
              Text('今日').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#1E293B')
              Row({ space: 0 }) {
                Column() { Text(`${this.viewModel.dailyTotalMinutes}`).fontSize(30).fontWeight(FontWeight.Bold).fontColor(AppColors.PRIMARY); Text('分钟').fontSize(12).fontColor('#94A3B8') }.layoutWeight(1)
                Column() { Text(`${this.viewModel.todaySessions.length}`).fontSize(30).fontWeight(FontWeight.Bold).fontColor(AppColors.FOCUS_ACTIVE); Text('次').fontSize(12).fontColor('#94A3B8') }.layoutWeight(1)
                Column() { Text(`${this.getMaxFlowScore()}`).fontSize(30).fontWeight(FontWeight.Bold).fontColor('#F59E0B'); Text('心流').fontSize(12).fontColor('#94A3B8') }.layoutWeight(1)
              }
              .width('100%').padding({ top: 14, bottom: 14, left: 8, right: 8 })
              .backgroundColor('#FFFFFF').borderRadius(14)
            }
          }

          Blank().height(20)
        }
        .padding({ left: 24, right: 24, bottom: 40 })
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
