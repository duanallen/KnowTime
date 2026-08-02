import { FocusSession, FocusState, SessionType, InterruptionRecord } from '../models/FocusSession'
import { DatabaseHelper } from '../database/DatabaseHelper'
import { AnalyticsService } from '../analytics/AnalyticsService'
import { Context } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import vibrator from '@ohos.vibrator'
import notificationManager from '@ohos.notificationManager'
import reminderAgentManager from '@ohos.reminderAgentManager'
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
  @Trace isReminding: boolean = false
  @Trace reminderStartTime: number = 0

  private timerId: number = -1
  private interruptionStartTime: number = 0
  private reminderTimerId: number = -1
  private reminderCycleId: number = -1
  private reminderVibrationId: number = -1
  private reminderAudioStreamId: number = -1
  private reminderAgentId: number = -1
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

  /**
   * 检查必要的权限
   * @returns 是否有必要的权限
   */
  public async checkPermissions(): Promise<boolean> {
    try {
      // 检查震动权限
      const vibratorInfo = vibrator.getVibratorInfoSync()
      if (vibratorInfo.length === 0) {
        hilog.warn(DOMAIN, TAG, 'Device does not support vibration')
        return false
      }
      
      // 检查通知权限
      const hasNotificationPermission = true // 暂时跳过权限检查，避免bundleManager问题
      // TODO: 在实际项目中需要添加通知权限检查
      // const bundleInfo = await bundleManager.getBundleInfo(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      // const hasNotificationPermission = bundleInfo.requestPermissions.some(permission => 
      //   permission.permissionName === 'ohos.permission.NOTIFICATION_CONTROLLER' ||
      //   permission.permissionName === 'ohos.permission.POST_NOTIFICATION'
      // )
      
      if (!hasNotificationPermission) {
        hilog.warn(DOMAIN, TAG, 'Notification permission not granted')
        return false
      }
      
      hilog.info(DOMAIN, TAG, 'All permissions checked successfully')
      return true
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Permission check failed: %{public}s', (err as Error).message)
      return false
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

    // 启动持续提醒，而不是立即重置状态
    this.startReminder()
  }

  private stopTimer(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
  }
  
  private async startReminder(): Promise<void> {
    // 检查权限
    const hasPermission = await this.checkPermissions()
    if (!hasPermission) {
      hilog.error(DOMAIN, TAG, 'Missing permissions for reminder')
      return
    }
    
    this.isReminding = true
    this.reminderStartTime = Date.now()
    this.focusState = FocusState.REMINDING

    // 发布1分钟系统闹钟提醒（手表等也支持震动+响铃1分钟，可点通知上的“停止提醒”关闭）
    try {
      const reminderId: number = await reminderAgentManager.publishReminder({
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER,
        triggerTimeInSeconds: 0,
        ringDuration: 60,
        title: '知时',
        content: '专注已完成，1分钟内可手动结束提醒',
        expiredContent: '专注提醒已结束',
        snoozeTimes: 0,
        ringChannel: reminderAgentManager.RingChannel.RING_CHANNEL_ALARM,
        actionButton: [
          {
            title: '停止提醒',
            type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE
          }
        ]
      } as reminderAgentManager.ReminderRequestTimer)
      this.reminderAgentId = reminderId
    } catch (autoErr) {
      hilog.error(DOMAIN, TAG, 'publish system reminder failed: %{public}s', (autoErr as Error).message)
    }

    // 设置1分钟自动停止的定时器
    this.reminderTimerId = setTimeout(() => {
      this.stopReminder()
    }, 60000)
    
    // 启动提醒循环
    this.startReminderCycle()
  }
  
  private startReminderCycle(): void {
    // 启动持续响铃（无限循环）和连续震动，一直持续到用户手动停止或1分钟超时
    this.playRingtoneLoop()
    this.startVibrationPattern()
    
    // 只保留一个1分钟自动停止检查，不需要重复播放
    this.reminderCycleId = setInterval(() => {
      if (!this.isReminding) {
        clearInterval(this.reminderCycleId)
        return
      }
      
      // 检查是否已经1分钟
      if (Date.now() - this.reminderStartTime >= 60000) {
        this.stopReminder()
      }
    }, 1000)
  }
  
  private playRingtoneLoop(): void {
    if (!this.soundPool || this.getSoundIdFromPrefs() < 0) return
    
    const sid: number = this.getSoundIdFromPrefs()
    this.soundPool.play(sid, {
      loop: -1,
      volume: 1.0,
      rate: 1.0,
      leftVolume: 1.0,
      rightVolume: 1.0,
      priority: 1
    } as media.PlayParameters, (err: Error, streamId: number) => {
      if (err) {
        hilog.error(DOMAIN, TAG, 'playRingtoneLoop err: %{public}s', err.message)
      } else {
        this.reminderAudioStreamId = streamId
        hilog.info(DOMAIN, TAG, 'Reminder ringtone looping, streamId=%{public}d', streamId)
      }
    })
  }
  
  private async startVibrationPattern(): Promise<void> {
    try {
      // 检查震动器是否存在
      const vibratorInfo = vibrator.getVibratorInfoSync()
      if (vibratorInfo.length === 0) {
        hilog.error(DOMAIN, TAG, 'Vibrator not available')
        return
      }

      // 方式一：尝试使用预设时钟震动无限重复（部分设备/手表支持 count=-1）
      const presetSupported: boolean = vibrator.isSupportEffectSync('haptic.clock.timer')
      if (presetSupported) {
        try {
          await vibrator.startVibration(
            { type: 'preset', effectId: 'haptic.clock.timer', count: -1 } as vibrator.VibrateEffect,
            { id: 0, usage: 'alarm' } as vibrator.VibrateAttribute
          )
          hilog.info(DOMAIN, TAG, 'Vibration preset loop started for reminder')
          return
        } catch (presetErr) {
          hilog.error(DOMAIN, TAG, 'preset vibration failed, use time pattern: %{public}s', (presetErr as Error).message)
        }
      }

      // 方式二：构造一个60秒连续震动 pattern。
      // API 18+ 的 VibratorPatternBuilder 可生成连续震动事件，手表/手机都遵循这个时长，直到用户停止或自动超时。
      try {
        const pattern: vibrator.VibratorPattern = new vibrator.VibratorPatternBuilder()
          .addContinuousEvent(0, 60000, { intensity: 1, frequency: 120 } as vibrator.ContinuousParam)
          .build()
        await vibrator.startVibration(
          { type: 'pattern', pattern: pattern } as vibrator.VibrateEffect,
          { id: 0, usage: 'alarm' } as vibrator.VibrateAttribute
        )
        hilog.info(DOMAIN, TAG, 'Vibration pattern (60s) started for reminder')
        return
      } catch (patternErr) {
        hilog.error(DOMAIN, TAG, 'pattern vibration failed, use repeat loop: %{public}s', (patternErr as Error).message)
      }

      // 方式三：如果设备不支持 pattern，退化为每300ms重发一次时长震动，直到手动结束/1分钟超时
      const continueVibration = (): void => {
        if (!this.isReminding) return
        vibrator.startVibration(
          { type: 'time', duration: 300 } as vibrator.VibrateEffect,
          { id: 0, usage: 'alarm' } as vibrator.VibrateAttribute
        ).then(() => {
          setTimeout(continueVibration, 350)
        }).catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'vibration repeat failed: %{public}s', err.message)
          setTimeout(continueVibration, 500)
        })
      }
      continueVibration()
      hilog.info(DOMAIN, TAG, 'Vibration repeat loop started for reminder')
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Vibration start failed: %{public}s', (err as Error).message)
    }
  }
  
  public stopReminder(): void {
    this.isReminding = false

    // 取消系统提醒（若取消失败，兜底取消当前应用的全部提醒）
    if (this.reminderAgentId >= 0) {
      try {
        reminderAgentManager.cancelReminder(this.reminderAgentId).catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'cancel system reminder failed: %{public}s', err.message)
          reminderAgentManager.cancelAllReminders().catch((allErr: Error) => {
            hilog.error(DOMAIN, TAG, 'cancel all reminders failed: %{public}s', allErr.message)
          })
        })
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'cancel system reminder error: %{public}s', (err as Error).message)
      }
      this.reminderAgentId = -1
    }

    // 清除定时器
    if (this.reminderTimerId !== -1) {
      clearTimeout(this.reminderTimerId)
      this.reminderTimerId = -1
    }
    
    if (this.reminderCycleId !== -1) {
      clearInterval(this.reminderCycleId)
      this.reminderCycleId = -1
    }
    
    // 停止循环响铃
    if (this.reminderAudioStreamId > 0 && this.soundPool) {
      try {
        this.soundPool.stop(this.reminderAudioStreamId)
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'stop reminder audio failed: %{public}s', (e as Error).message)
      }
      this.reminderAudioStreamId = -1
    }
    
    // 停止震动
    try {
      vibrator.stopVibration()
      hilog.info(DOMAIN, TAG, 'Vibration stopped')
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Vibration stop failed: %{public}s', (err as Error).message)
    }
    
    // 播放完成提示音
    this.playCompletionSound()
    
    // 重置状态
    this.focusState = FocusState.IDLE
    this.currentSession = null
    this.elapsedSeconds = 0
    
    hilog.info(DOMAIN, TAG, 'Reminder stopped')
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
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
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
  
  private playCompletionSound(): void {
    if (!this.soundPool || this.getSoundIdFromPrefs() < 0) return
    
    this.soundPool.play(this.getSoundIdFromPrefs(), {
      loop: 0,
      volume: 1.0,
      rate: 1.0,
      priority: 1
    } as media.PlayParameters, (err: Error, streamId: number) => {
      if (err) {
        hilog.error(DOMAIN, TAG, 'playCompletionSound err: %{public}s', err.message)
      } else {
        hilog.info(DOMAIN, TAG, 'Completion sound played, streamId=%{public}d', streamId)
      }
    })
  }

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
    this.stopReminder()
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
