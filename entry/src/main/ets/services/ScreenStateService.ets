import { hilog } from '@kit.PerformanceAnalysisKit'
import { commonEventManager, screenLock } from '@kit.BasicServicesKit'

export const LOCK_SAFE_DOMAIN = 0x0040
export const LOCK_SAFE_TAG = 'LockSafeStartup'

type LockScreenChangeListener = (isLocked: boolean) => void

/**
 * 屏幕锁状态服务。
 * - 查询锁屏状态：screenLock.isScreenLocked()
 * - 订阅解锁事件：commonEventManager 的 COMMON_EVENT_USER_UNLOCKED（@ohos.screenLock 无 on/off 事件能力）
 * 所有 API 调用均做错误兜底，不向调用方抛出非 Error 类型。
 */

// 定义错误类型
interface ServiceError {
  code: number;
  message: string;
}
type ErrorType = ServiceError | Error
export class ScreenStateService {
  private static instance: ScreenStateService | null = null
  private available: boolean = false
  private subscriber: commonEventManager.CommonEventSubscriber | null = null

  private constructor() {}

  static getInstance(): ScreenStateService {
    if (ScreenStateService.instance === null) {
      ScreenStateService.instance = new ScreenStateService()
    }
    return ScreenStateService.instance
  }

  async isLocked(): Promise<boolean> {
    try {
      const locked = await screenLock.isScreenLocked()
      this.available = true
      return locked
    } catch (e) {
      this.available = false
      hilog.warn(LOCK_SAFE_DOMAIN, LOCK_SAFE_TAG, 'isLocked failed: %{public}s', JSON.stringify(e))
      throw new Error(JSON.stringify(e))
    }
  }

  async subscribeUnlock(listener: LockScreenChangeListener): Promise<boolean> {
    try {
      const subscribeInfo: commonEventManager.CommonEventSubscribeInfo = {
        events: [commonEventManager.Support.COMMON_EVENT_USER_UNLOCKED]
      }
      const subscriber: commonEventManager.CommonEventSubscriber = await commonEventManager.createSubscriber(subscribeInfo)
      commonEventManager.subscribe(subscriber, (err) => {
        if (err) {
          hilog.warn(LOCK_SAFE_DOMAIN, LOCK_SAFE_TAG, 'lockScreenChange event error: %{public}s', JSON.stringify(err))
          return
        }
        // 用户解锁事件：回调 isLocked=false，由协调器触发补偿
        listener(false)
      })
      this.subscriber = subscriber
      this.available = true
      return true
    } catch (e) {
      this.available = false
      hilog.warn(LOCK_SAFE_DOMAIN, LOCK_SAFE_TAG, 'subscribeUnlock failed: %{public}s', JSON.stringify(e))
      return false
    }
  }

  async unsubscribeUnlock(): Promise<void> {
    try {
      if (this.subscriber !== null) {
        commonEventManager.unsubscribe(this.subscriber)
      }
    } catch (e) {
      hilog.warn(LOCK_SAFE_DOMAIN, LOCK_SAFE_TAG, 'unsubscribeUnlock failed: %{public}s', JSON.stringify(e))
    } finally {
      this.subscriber = null
    }
  }

  isAvailable(): boolean {
    return this.available
  }
}
