import { FocusSession, FocusState, SessionType, InterruptionRecord } from '../models/FocusSession'
import { DatabaseHelper } from '../database/DatabaseHelper'
import { AnalyticsService } from '../analytics/AnalyticsService'
import { Context, common } from '@kit.AbilityKit'
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
// 系统闹钟比计划结束时刻晚 1 秒：前台时应用在到点瞬间取消系统闹钟并播放自定义铃声，
// 1 秒余量避免系统闹钟先响造成双响；熄屏时仅晚 1 秒，仍满足"准时"。
const END_REMINDER_DELAY_SECONDS = 1

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
  // 开始/恢复专注时预注册的"到点"系统闹钟，熄屏后台时由系统独立触发响铃
  private endReminderAgentId: number = -1
  private endReminderSeq: number = 0
  private runningStartMs: number = 0
  private accumulatedSeconds: number = 0
  private db: DatabaseHelper = DatabaseHelper.getInstance()
  private analytics: AnalyticsService = AnalyticsService.getInstance()
  private appContext: Context | null = null
  private soundPool: media.SoundPool | null = null
  private bellSoundId: number = -1
  private chimeSoundId: number = -1
  private gentleSoundId: number = -1
  private soundPoolReady: boolean = false
  // 页面是否可见。熄屏/切后台时页面不可见，此时到点交由系统闹钟响铃，
  // 避免应用去取消系统闹钟后自身进程又被冻结导致完全不响。
  private isPageVisible: boolean = true

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
      let hasNotificationPermission = false
      try {
        hasNotificationPermission = await notificationManager.isNotificationEnabled()
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'isNotificationEnabled failed: %{public}s', (e as Error).message)
      }
      
      if (!hasNotificationPermission) {
        hilog.warn(DOMAIN, TAG, 'Notification not enabled, reminders will not fire')
        return false
      }
      
      hilog.info(DOMAIN, TAG, 'All permissions checked successfully')
      return true
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Permission check failed: %{public}s', (err as Error).message)
      return false
    }
  }

  /**
   * 确保通知权限已开启。
   * reminderAgentManager 的提醒由系统通知通道承载，通知被关闭时系统会直接拦截
   * （设备日志：ReminderControl ... notification not allowed），熄屏后就不会响铃。
   *
   * 注意：isNotificationEnabled() 在部分设备上返回值不可靠（实测 allowEnableNotification=false
   * 时仍返回 true），因此不再依赖其判断，而是直接调用 requestEnableNotification。
   * 该 API 在通知已开启时为空操作，未开启时弹出系统授权框。
   */
  private async ensureNotificationEnabled(): Promise<boolean> {
    try {
      // 直接请求开启通知（已开启时为空操作）
      if (this.appContext) {
        try {
          await notificationManager.requestEnableNotification(this.appContext as common.UIAbilityContext)
          hilog.info(DOMAIN, TAG, 'requestEnableNotification done')
        } catch (reqErr) {
          // 用户拒绝或系统不弹窗时不阻断流程，后续 publish 失败时会再次提示
          hilog.warn(DOMAIN, TAG, 'requestEnableNotification rejected: %{public}s', (reqErr as Error).message)
        }
      }
      // 再做一次检查（仅供日志参考，不作为阻断依据）
      let enabled: boolean = true
      try {
        enabled = await notificationManager.isNotificationEnabled()
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'isNotificationEnabled failed: %{public}s', (e as Error).message)
      }
      hilog.info(DOMAIN, TAG, 'notification check done, isNotificationEnabled=%{public}s', enabled ? 'true' : 'false')
      return enabled
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'ensureNotificationEnabled failed: %{public}s', (e as Error).message)
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

  async startSession(taskName: string, tag: string, plannedSeconds: number, sessionType: SessionType): Promise<boolean> {
    // 系统提醒是熄屏后唯一可靠的响铃通道，发布前确保通知权限已开启。
    // 放在会话计时开始之前，避免授权弹窗耗时被计入专注时长。
    await this.ensureNotificationEnabled()
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
    this.accumulatedSeconds = 0
    this.focusState = FocusState.RUNNING
    this.startTimer()
    // 等待系统提醒注册结果，决定是否提示用户开启通知
    const reminderRegistered: boolean = await this.preRegisterEndReminder(plannedSeconds)
    this.analytics.trackFocusStart(tag)
    return reminderRegistered
  }

  pauseSession(): void {
    if (!this.currentSession || this.focusState !== FocusState.RUNNING) return
    this.currentSession.state = FocusState.PAUSED
    this.focusState = FocusState.PAUSED
    this.interruptionStartTime = Date.now()
    this.accumulatedSeconds = this.elapsedSeconds
    this.stopTimer()
    this.cancelEndReminder()
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
    this.accumulatedSeconds = this.elapsedSeconds
    this.startTimer()
    this.preRegisterEndReminder(this.currentSession.plannedDuration - this.elapsedSeconds).catch(() => {})
    this.analytics.trackFocusResume()
  }

  async stopSession(): Promise<void> {
    this.stopTimer()
    this.cancelEndReminder()
    if (!this.currentSession) {
      this.focusState = FocusState.IDLE
      return
    }
    // 若处于暂停状态结束，补录当前暂停为中断，确保心流得分正确扣减
    if (this.focusState === FocusState.PAUSED && this.interruptionStartTime > 0) {
      const pauseDuration = Math.floor((Date.now() - this.interruptionStartTime) / 1000)
      if (pauseDuration > 0) {
        this.currentSession.interruptions.push({
          id: this.generateId(),
          timestamp: this.interruptionStartTime,
          duration: pauseDuration,
          reason: '用户暂停'
        })
      }
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
    this.runningStartMs = Date.now()
    this.timerId = setInterval(() => {
      if (this.focusState === FocusState.RUNNING) {
        this.recalcElapsed()
      }
    }, 250)
  }

  private recalcElapsed(): void {
    if (this.focusState !== FocusState.RUNNING) return
    const now = Date.now()
    const newElapsed = this.accumulatedSeconds + Math.floor((now - this.runningStartMs) / 1000)
    if (newElapsed !== this.elapsedSeconds) {
      this.elapsedSeconds = newElapsed
      if (this.currentSession) {
        this.currentSession.actualDuration = this.elapsedSeconds
        if (this.elapsedSeconds >= this.currentSession.plannedDuration) {
          this.completeSession()
          return
        }
      }
    }
  }

  recalculateElapsed(): void {
    this.recalcElapsed()
  }

  private async completeSession(): Promise<void> {
    this.stopTimer()
    // 页面可见时应用自己播放自定义铃声，先取消系统闹钟（闹钟留了 1 秒余量）。
    // 页面不可见（熄屏/后台）时不能取消：进程随时可能被冻结，系统闹钟才是唯一可靠通道。
    const visible: boolean = this.isPageVisible
    if (visible) {
      this.cancelEndReminder()
    }
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

    if (visible) {
      // 前台到点：应用内铃声 + 震动
      this.startReminder()
    } else {
      // 后台/熄屏到点：保留系统闹钟，由其独立响铃与震动；应用侧仅结束计时
      hilog.info(DOMAIN, TAG, 'session completed while hidden, keep system reminder')
      this.currentSession = null
      this.elapsedSeconds = 0
      this.focusState = FocusState.IDLE
    }
  }

  private stopTimer(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
  }

  /** 页面可见性变化（熄屏/切后台时页面不可见） */
  setPageVisible(visible: boolean): void {
    this.isPageVisible = visible
    hilog.info(DOMAIN, TAG, 'page visible=%{public}s', visible ? 'true' : 'false')
  }


  /**
   * 预注册"计划结束时刻"的系统闹钟。
   * 熄屏/后台时应用内 setInterval 会被系统挂起，无法主动触发到点提醒，
   * 因此改由系统闹钟在到点时刻独立响铃(ALARM 通道)，不依赖应用存活。
   * @param remainingSeconds 距离本次专注结束还需的秒数
   */
  private preRegisterEndReminder(remainingSeconds: number): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      this.cancelEndReminder()
      if (remainingSeconds <= 0) {
        resolve(false)
        return
      }
      const seq: number = ++this.endReminderSeq
      const endTimeMs: number = Date.now() + (remainingSeconds + END_REMINDER_DELAY_SECONDS) * 1000
      const endTime: Date = new Date(endTimeMs)
      let retryCount: number = 0
      const tryPublish = (): void => {
        try {
          reminderAgentManager.publishReminder({
            reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
            dateTime: {
              year: endTime.getFullYear(),
              month: endTime.getMonth() + 1,
              day: endTime.getDate(),
              hour: endTime.getHours(),
              minute: endTime.getMinutes(),
              second: endTime.getSeconds()
            },
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
          } as reminderAgentManager.ReminderRequestCalendar).then((id: number) => {
            if (seq !== this.endReminderSeq) {
              reminderAgentManager.cancelReminder(id).catch(() => {})
              resolve(false)
              return
            }
            this.endReminderAgentId = id
            hilog.info(DOMAIN, TAG, 'end reminder pre-registered id=%{public}d atMs=%{public}d time=%{public}s',
              id, endTimeMs, endTime.toLocaleTimeString())
            resolve(true)
          }).catch((err: BusinessError) => {
            const errCode = err.code
            hilog.error(DOMAIN, TAG, 'pre-register end reminder failed (code=%{public}d): %{public}s', errCode, err.message)
            if (this.appContext) {
              notificationManager.requestEnableNotification(this.appContext as common.UIAbilityContext).catch(() => {})
            }
            if (errCode === 1700002 && retryCount === 0) {
              retryCount++
              hilog.warn(DOMAIN, TAG, 'reminder count exceeded or notification blocked, cancelAllReminders and retry once')
              reminderAgentManager.cancelAllReminders().then(() => {
                if (seq === this.endReminderSeq) {
                  tryPublish()
                } else {
                  resolve(false)
                }
              }).catch(() => {
                resolve(false)
              })
              return
            }
            resolve(false)
          })
        } catch (err) {
          hilog.error(DOMAIN, TAG, 'pre-register end reminder error: %{public}s', (err as Error).message)
          resolve(false)
        }
      }
      tryPublish()
    })
  }

  /** 取消已预注册的到点系统闹钟(幂等) */
  private cancelEndReminder(): void {
    this.endReminderSeq++
    if (this.endReminderAgentId < 0) return
    const id: number = this.endReminderAgentId
    this.endReminderAgentId = -1
    try {
      reminderAgentManager.cancelReminder(id).then(() => {
        hilog.info(DOMAIN, TAG, 'end reminder cancelled id=%{public}d', id)
      }).catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'cancel end reminder failed: %{public}s', err.message)
      })
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'cancel end reminder error: %{public}s', (err as Error).message)
    }
  }

  private async startReminder(): Promise<void> {
    // 到点瞬间系统通知（1分钟可手动停止）与应用内铃声同时启动
    this.isReminding = true
    this.reminderStartTime = Date.now()
    this.focusState = FocusState.REMINDING

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
      hilog.error(DOMAIN, TAG, 'publish immediate reminder failed: %{public}s', (autoErr as Error).message)
    }

    // 设置1分钟自动停止的定时器
    this.reminderTimerId = setTimeout(() => {
      this.stopReminder()
    }, 60000)

    // 启动提醒循环（应用内铃声+震动，不依赖通知权限）
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
    this.cancelEndReminder()

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
    // 完成率：实际时长/计划时长，最高1.0，权重40%
    const completionRate = Math.min(actual / Math.max(planned, 1), 1)
    // 专注深度：以90分钟（5400秒）为满分基准，体现心流沉浸深度，权重60%
    const depthScore = Math.min(actual / 5400, 1)
    const baseScore = completionRate * 40 + depthScore * 60
    // 中断惩罚：每次中断扣10分，中断会打断心流状态
    const interruptionCount = this.currentSession.interruptions.length
    return Math.max(0, Math.min(100, Math.floor(baseScore - interruptionCount * 10)))
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
    this.cancelEndReminder()
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
