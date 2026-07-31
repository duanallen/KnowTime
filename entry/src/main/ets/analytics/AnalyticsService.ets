import { hilog } from '@kit.PerformanceAnalysisKit'
import { http } from '@kit.NetworkKit'
import { preferences } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'

const TAG = 'Analytics'
const DOMAIN = 0x0004

const ANALYTICS_ENDPOINT = ''

export enum AnalyticsEvent {
  APP_LAUNCH = 'app_launch',
  APP_ENTER_FOREGROUND = 'app_enter_foreground',
  APP_ENTER_BACKGROUND = 'app_enter_background',
  FOCUS_START = 'focus_start',
  FOCUS_COMPLETE = 'focus_complete',
  FOCUS_PAUSE = 'focus_pause',
  FOCUS_RESUME = 'focus_resume',
  PAGE_VIEW = 'page_view',
  SESSION_DURATION = 'session_duration',
}

interface AnalyticsPayload {
  device_id: string
  app_version: string
  event: string
  properties: Record<string, string | number>
  timestamp: number
  session_id: string
}

class PageTimer {
  name: string = ''
  enterTime: number = 0
}

export class AnalyticsService {
  private static instance: AnalyticsService
  private deviceId: string = ''
  private sessionId: string = ''
  private initialized: boolean = false
  private context: common.UIAbilityContext | null = null
  private pageTimers: Map<string, PageTimer> = new Map()
  private queue: AnalyticsPayload[] = []
  private flushing: boolean = false

  static getInstance(): AnalyticsService {
    if (!AnalyticsService.instance) {
      AnalyticsService.instance = new AnalyticsService()
    }
    return AnalyticsService.instance
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.initialized) return
    this.context = context
    this.sessionId = this.generateId()
    this.deviceId = await this.getDeviceId()
    this.initialized = true
    hilog.info(DOMAIN, TAG, 'Analytics init done')
    this.track(AnalyticsEvent.APP_LAUNCH)
  }

  onForeground(): void {
    this.sessionId = this.generateId()
    this.track(AnalyticsEvent.APP_ENTER_FOREGROUND)
  }

  onBackground(): void {
    this.flushPageTimers()
    this.track(AnalyticsEvent.APP_ENTER_BACKGROUND)
  }

  startPageView(pageName: string): void {
    if (!this.initialized) return
    const timer = new PageTimer()
    timer.name = pageName
    timer.enterTime = Date.now()
    this.pageTimers.set(pageName, timer)
  }

  endPageView(pageName: string): void {
    if (!this.initialized) return
    const timer = this.pageTimers.get(pageName)
    if (timer) {
      const duration = Math.floor((Date.now() - timer.enterTime) / 1000)
      if (duration > 0) {
        const props: Record<string, string | number> = {}
        props['page'] = pageName
        props['duration_seconds'] = duration
        this.track(AnalyticsEvent.PAGE_VIEW, props)
      }
      this.pageTimers.delete(pageName)
    }
  }

  trackFocusStart(tag: string): void {
    const props: Record<string, string | number> = {}
    props['tag'] = tag
    this.track(AnalyticsEvent.FOCUS_START, props)
  }

  trackFocusComplete(durationSeconds: number, flowScore: number, tag: string, taskName: string): void {
    const props: Record<string, string | number> = {}
    props['duration_seconds'] = durationSeconds
    props['duration_minutes'] = Math.floor(durationSeconds / 60)
    props['flow_score'] = flowScore
    props['tag'] = tag
    props['task_length'] = taskName.length
    this.track(AnalyticsEvent.FOCUS_COMPLETE, props)
  }

  trackFocusPause(elapsedSeconds: number): void {
    const props: Record<string, string | number> = {}
    props['elapsed_seconds'] = elapsedSeconds
    this.track(AnalyticsEvent.FOCUS_PAUSE, props)
  }

  trackFocusResume(): void {
    this.track(AnalyticsEvent.FOCUS_RESUME)
  }

  track(event: string, properties?: Record<string, string | number>): void {
    if (!this.initialized) {
      hilog.warn(DOMAIN, TAG, 'Not initialized, skip: %{public}s', event)
      return
    }
    const props: Record<string, string | number> = properties ? properties : {}
    const payload: AnalyticsPayload = {
      device_id: this.deviceId,
      app_version: '1.0.0',
      event: event,
      properties: props,
      timestamp: Date.now(),
      session_id: this.sessionId
    }
    hilog.info(DOMAIN, TAG, '[EVENT] %{public}s', event)

    if (ANALYTICS_ENDPOINT.length > 0) {
      this.enqueue(payload)
    }
  }

  private enqueue(payload: AnalyticsPayload): void {
    this.queue.push(payload)
    if (!this.flushing) {
      this.flush()
    }
  }

  private async flush(): Promise<void> {
    if (this.flushing || this.queue.length === 0) return
    this.flushing = true
    const batch = this.queue.splice(0, this.queue.length)
    try {
      const httpRequest = http.createHttp()
      const body = JSON.stringify({ events: batch })
      const response = await httpRequest.request(
        ANALYTICS_ENDPOINT,
        {
          method: http.RequestMethod.POST,
          header: { 'Content-Type': 'application/json' },
          connectTimeout: 5000,
          readTimeout: 5000,
          extraData: body
        }
      )
      if (response.responseCode !== 200) {
        hilog.warn(DOMAIN, TAG, 'Flush code=%{public}d', response.responseCode)
      }
      httpRequest.destroy()
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Flush error (non-critical)')
    } finally {
      this.flushing = false
    }
  }

  private flushPageTimers(): void {
    this.pageTimers.forEach((timer: PageTimer) => {
      const dur = Math.floor((Date.now() - timer.enterTime) / 1000)
      if (dur > 0) {
        const props: Record<string, string | number> = {}
        props['page'] = timer.name
        props['duration_seconds'] = dur
        this.track(AnalyticsEvent.PAGE_VIEW, props)
      }
    })
    this.pageTimers.clear()
  }

  private async getDeviceId(): Promise<string> {
    try {
      if (this.context) {
        const prefs = await preferences.getPreferences(this.context, 'analytics_prefs')
        const stored = await prefs.get('device_id', '') as string
        if (stored.length > 0) return stored
        const newId = this.generateId()
        await prefs.put('device_id', newId)
        await prefs.flush()
        return newId
      }
    } catch (e) {
      // 降级
    }
    return this.generateId()
  }

  private generateId(): string {
    const ts = Date.now().toString(36)
    const rand = Math.random().toString(36).substring(2, 10)
    return `${ts}-${rand}`
  }

  destroy(): void {
    this.flushPageTimers()
    this.initialized = false
    this.context = null
  }
}
