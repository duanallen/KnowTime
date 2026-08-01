import { FocusSession, FocusState, SessionType, InterruptionRecord } from '../models/FocusSession'
import { DatabaseHelper } from '../database/DatabaseHelper'
import { AnalyticsService } from '../analytics/AnalyticsService'
import { Context } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import vibrator from '@ohos.vibrator'
import notificationManager from '@ohos.notificationManager'
import { preferences } from '@kit.ArkData'
import media from '@ohos.multimedia.media'
import audio from '@ohos.multimedia.audio'
import { resourceManager } from '@kit.LocalizationKit'

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
  private appContext: Context | null = null
  private soundPool: media.SoundPool | null = null
  private bellSoundId: number = -1
  private chimeSoundId: number = -1
  private gentleSoundId: number = -1
  private soundPoolReady: boolean = false

  async init(context: Context): Promise<void> {
    this.appContext = context
    await this.db.init(context)
    await this.loadTodayData()
    this.isDbReady = true
    this.initSoundPool(context)
    hilog.info(DOMAIN, TAG, 'init() done')
  }

  private initSoundPool(context: Context): void {
    try {
      const info: audio.AudioRendererInfo = {
        usage: audio.StreamUsage.STREAM_USAGE_ALARM,
        rendererFlags: 0
      }
      media.createSoundPool(5, info, (err: BusinessError, pool: media.SoundPool) => {
        if (err) {
          hilog.error(DOMAIN, TAG, 'createSoundPool: %{public}s', err.message)
          return
        }
        this.soundPool = pool
        let loadedCount: number = 0
        pool.on('loadComplete', (id: number) => {
          loadedCount++
          hilog.info(DOMAIN, TAG, 'loadComplete #%{public}d id=%{public}d', loadedCount, id)
          if (loadedCount >= 3) {
            this.soundPoolReady = true
            hilog.info(DOMAIN, TAG, 'SoundPool fully ready')
          }
        })
        pool.on('error', (e: Error) => {
          hilog.error(DOMAIN, TAG, 'SoundPool error: %{public}s', e.message)
        })
        this.preloadAll(context, pool)
      })
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'initSoundPool: %{public}s', (e as Error).message)
    }
  }

  private preloadAll(context: Context, pool: media.SoundPool): void {
    const resMgr: resourceManager.ResourceManager = context.resourceManager
    const files: string[] = ['ringtone_bell.mp3', 'ringtone_chime.mp3', 'ringtone_gentle.mp3']
    for (let i: number = 0; i < files.length; i++) {
      const fn: string = files[i]
      resMgr.getRawFd(fn).then((raw: resourceManager.RawFileDescriptor) => {
        pool.load(raw.fd, raw.offset, raw.length, (loadErr: Error, id: number) => {
          if (loadErr) {
            hilog.error(DOMAIN, TAG, 'load %{public}s: %{public}s', fn, loadErr.message)
          } else {
            hilog.info(DOMAIN, TAG, 'Loaded %{public}s -> id=%{public}d', fn, id)
            if (fn === 'ringtone_bell.mp3') this.bellSoundId = id
            if (fn === 'ringtone_chime.mp3') this.chimeSoundId = id
            if (fn === 'ringtone_gentle.mp3') this.gentleSoundId = id
          }
          resMgr.closeRawFdSync(fn)
        })
      }).catch((e: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'getRawFd %{public}s: %{public}s', fn, e.message)
      })
    }
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
    this.analytics.trackFocusStart(tag)
  }

  pauseSession(): void {
    if (!this.currentSession || this.focusState !== FocusState.RUNNING) return
    this.currentSession.state = FocusState.PAUSED
    this.focusState = FocusState.PAUSED
    this.interruptionStartTime = Date.now()
    this.stopTimer()
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

    await this.db.insertSession(this.currentSession)

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
          if (this.elapsedSeconds >= this.currentSession.plannedDuration) {
            this.completeSession()
            return
          }
        }
      }
    }, 1000)
  }

  private async completeSession(): Promise<void> {
    this.stopTimer()
    if (!this.currentSession) {
      this.focusState = FocusState.IDLE
      return
    }
    this.currentSession.endTime = Date.now()
    this.currentSession.actualDuration = this.currentSession.plannedDuration
    this.currentSession.flowScore = this.calculateFlowScore()
    this.currentSession.state = FocusState.COMPLETED

    await this.db.insertSession(this.currentSession)

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
    this.dailyTotalMinutes += Math.floor(this.currentSession.plannedDuration / 60)

    this.triggerVibration()
    this.playRingtoneNow()
    this.sendCompleteNotification()

    this.currentSession = null
    this.elapsedSeconds = 0
    this.focusState = FocusState.IDLE
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

  private triggerVibration(): void {
    try {
      vibrator.startVibration(
        { type: 'time', duration: 500 } as vibrator.VibrateEffect,
        { id: 0, usage: 'notification' } as vibrator.VibrateAttribute
      ).catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'vib: %{public}s', err.message)
      })
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'vib err: %{public}s', (err as Error).message)
    }
  }

  private async sendCompleteNotification(): Promise<void> {
    try {
      await notificationManager.publish({
        id: 1001,
        content: {
          contentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: '专注已完成',
            text: '恭喜完成本次专注，继续加油！',
            additionalText: ''
          }
        },
        deliveryTime: new Date().getTime(),
        notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
        sound: 'ringtones://default'
      } as notificationManager.NotificationRequest)
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'notify: %{public}s', (err as Error).message)
    }
  }

  private ringtoneMap: Record<string, number> = {}

  private getSoundIdFromPrefs(): number {
    // 默认返回 bell
    if (this.bellSoundId > 0) return this.bellSoundId
    if (this.chimeSoundId > 0) return this.chimeSoundId
    if (this.gentleSoundId > 0) return this.gentleSoundId
    return -1
  }

  private async getSelectedSoundId(): Promise<number> {
    if (!this.appContext) return this.bellSoundId
    try {
      const prefs: preferences.Preferences = await preferences.getPreferences(this.appContext, 'settings_prefs')
      const selected: string = await prefs.get('ringtone_selected', 'default') as string
      if (selected === 'bell' && this.bellSoundId > 0) return this.bellSoundId
      if (selected === 'chime' && this.chimeSoundId > 0) return this.chimeSoundId
      if (selected === 'gentle' && this.gentleSoundId > 0) return this.gentleSoundId
      return this.bellSoundId > 0 ? this.bellSoundId : this.chimeSoundId > 0 ? this.chimeSoundId : this.gentleSoundId
    } catch (e) {
      return this.bellSoundId
    }
  }

  private playRingtoneNow(): void {
    if (!this.soundPool) {
      hilog.warn(DOMAIN, TAG, 'SoundPool null')
      return
    }
    const sid: number = this.getSoundIdFromPrefs()
    if (sid <= 0) {
      hilog.warn(DOMAIN, TAG, 'No sound ID ready')
      return
    }
    hilog.info(DOMAIN, TAG, 'Playing soundId=%{public}d', sid)
    this.soundPool.play(sid, {
      loop: 0,
      rate: 0,
      leftVolume: 1.0,
      rightVolume: 1.0,
      priority: 1
    } as media.PlayParameters, (err: Error, streamId: number) => {
      if (err) {
        hilog.error(DOMAIN, TAG, 'playRingtoneNow err: %{public}s', err.message)
      } else {
        hilog.info(DOMAIN, TAG, 'Ringtone streamId=%{public}d', streamId)
      }
    })
  }

  static formatTime(seconds: number): string {
    const m = Math.floor(seconds / 60)
    const s = seconds % 60
    return `${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`
  }

  reset(): void {
    this.stopTimer()
    if (this.soundPool !== null) {
      try {
        this.soundPool.release((err: Error) => {
          hilog.error(DOMAIN, TAG, 'release: %{public}s', err?.message || 'ok')
        })
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'release err')
      }
      this.soundPool = null
      this.bellSoundId = -1
      this.chimeSoundId = -1
      this.gentleSoundId = -1
      this.soundPoolReady = false
    }
    this.currentSession = null
    this.elapsedSeconds = 0
    this.focusState = FocusState.IDLE
  }
}
