import { FocusSession, FocusState, SessionType, InterruptionRecord } from '../models/FocusSession'
import { DatabaseHelper } from '../database/DatabaseHelper'
import { AnalyticsService } from '../analytics/AnalyticsService'
import { Context } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'

const TAG = 'FocusVM'
const DOMAIN = 0x0003

@ObservedV2
export class FocusViewModel {
  @Trace currentSession: FocusSession | null = null
  @Trace elapsedSeconds: number = 0
  @Trace focusState: FocusState = FocusState.IDLE
  @Trace dailyTotalMinutes: number = 0
  @Trace todaySessions: FocusSession[] = []
  @Trace isDbReady: boolean = false

  private timerId: number = -1
  private interruptionStartTime: number = 0
  private db: DatabaseHelper = DatabaseHelper.getInstance()
  private analytics: AnalyticsService = AnalyticsService.getInstance()

  async init(context: Context): Promise<void> {
    await this.db.init(context)
    await this.loadTodayData()
    this.isDbReady = true
    hilog.info(DOMAIN, TAG, 'init() done, %{public}d sessions loaded', this.todaySessions.length)
  }

  private async loadTodayData(): Promise<void> {
    const sessions = await this.db.queryTodaySessions()
    this.todaySessions = sessions
    let total = 0
    for (let i = 0; i < sessions.length; i++) {
      total += Math.floor(sessions[i].actualDuration / 60)
    }
    this.dailyTotalMinutes = total
  }

  generateId(): string {
    const ts = Date.now()
    const rand = Math.floor(Math.random() * 1000000).toString(36)
    return `${ts}_${rand}`
  }

  startSession(taskName: string, tag: string, plannedSeconds: number, sessionType: SessionType): void {
    this.stopTimer()
    const session: FocusSession = {
      id: this.generateId(),
      taskName, tag,
      startTime: Date.now(),
      endTime: 0,
      plannedDuration: plannedSeconds,
      actualDuration: 0,
      state: FocusState.RUNNING,
      sessionType,
      interruptions: [],
      flowScore: 0,
      notes: ''
    }
    this.currentSession = session
    this.elapsedSeconds = 0
    this.focusState = FocusState.RUNNING
    this.startTimer()
    // 埋点：开始专注
    this.analytics.trackFocusStart(tag)
  }

  pauseSession(): void {
    if (!this.currentSession || this.focusState !== FocusState.RUNNING) return
    this.currentSession.state = FocusState.PAUSED
    this.focusState = FocusState.PAUSED
    this.interruptionStartTime = Date.now()
    this.stopTimer()
    // 埋点：暂停
    this.analytics.trackFocusPause(this.elapsedSeconds)
  }

  resumeSession(): void {
    if (!this.currentSession || this.focusState !== FocusState.PAUSED) return
    const pauseDuration = Math.floor((Date.now() - this.interruptionStartTime) / 1000)
    if (pauseDuration > 0) {
      const ir: InterruptionRecord = {
        id: this.generateId(),
        timestamp: this.interruptionStartTime,
        duration: pauseDuration,
        reason: '用户暂停'
      }
      this.currentSession.interruptions.push(ir)
    }
    this.currentSession.state = FocusState.RUNNING
    this.focusState = FocusState.RUNNING
    this.startTimer()
    // 埋点：恢复
    this.analytics.trackFocusResume()
  }

  async stopSession(): Promise<void> {
    this.stopTimer()
    if (!this.currentSession) {
      this.focusState = FocusState.IDLE
      return
    }
    this.currentSession.endTime = Date.now()
    this.currentSession.actualDuration = this.elapsedSeconds
    this.currentSession.flowScore = this.calculateFlowScore()
    this.currentSession.state = FocusState.COMPLETED

    // 存入数据库
    await this.db.insertSession(this.currentSession)

    // 更新内存列表
    const saved: FocusSession = {
      id: this.currentSession.id,
      taskName: this.currentSession.taskName,
      tag: this.currentSession.tag,
      startTime: this.currentSession.startTime,
      endTime: this.currentSession.endTime,
      plannedDuration: this.currentSession.plannedDuration,
      actualDuration: this.currentSession.actualDuration,
      state: this.currentSession.state,
      sessionType: this.currentSession.sessionType,
      interruptions: this.currentSession.interruptions.slice(),
      flowScore: this.currentSession.flowScore,
      notes: this.currentSession.notes
    }
    this.todaySessions.unshift(saved)
    this.dailyTotalMinutes += Math.floor(this.elapsedSeconds / 60)

    // 埋点：完成专注（核心指标）
    this.analytics.trackFocusComplete(
      this.elapsedSeconds,
      this.currentSession.flowScore,
      this.currentSession.tag,
      this.currentSession.taskName
    )

    this.currentSession = null
    this.elapsedSeconds = 0
    this.focusState = FocusState.IDLE
  }

  private startTimer(): void {
    this.timerId = setInterval(() => {
      if (this.focusState === FocusState.RUNNING) {
        this.elapsedSeconds++
        if (this.currentSession) {
          this.currentSession.actualDuration = this.elapsedSeconds
        }
      }
    }, 1000)
  }

  private stopTimer(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
  }

  private calculateFlowScore(): number {
    if (!this.currentSession) return 0
    const planned = this.currentSession.plannedDuration
    const actual = this.elapsedSeconds
    const rate = Math.min(actual / Math.max(planned, 1), 1)
    const interruptionCount = this.currentSession.interruptions.length
    return Math.max(0, Math.min(100, Math.floor(rate * 100 - interruptionCount * 15)))
  }

  static formatTime(seconds: number): string {
    const m = Math.floor(seconds / 60)
    const s = seconds % 60
    return `${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`
  }

  reset(): void {
    this.stopTimer()
    this.currentSession = null
    this.elapsedSeconds = 0
    this.focusState = FocusState.IDLE
  }
}
