import { hilog } from '@kit.PerformanceAnalysisKit'
import { ScreenStateService, LOCK_SAFE_DOMAIN, LOCK_SAFE_TAG } from './ScreenStateService'

export type ReminderAction = () => Promise<void>
export type CompensationSource = 'SCREEN_UNLOCK' | 'FOREGROUND'

export class LockSafeStartupCoordinator {
  private static instance: LockSafeStartupCoordinator | null = null
  private preRegistered: boolean = false
  private needCompensation: boolean = false
  private compensated: boolean = false
  private isCompensating: boolean = false
  private action: ReminderAction | null = null

  private constructor() {}

  static getInstance(): LockSafeStartupCoordinator {
    if (LockSafeStartupCoordinator.instance === null) {
      LockSafeStartupCoordinator.instance = new LockSafeStartupCoordinator()
    }
    return LockSafeStartupCoordinator.instance
  }

  async orchestrateOnCreate(action: ReminderAction): Promise<void> {
    this.action = action
    try {
      let isLocked = true
      try {
        isLocked = await ScreenStateService.getInstance().isLocked()
      } catch (e) {
        const errObj = e as Record<string, number | string>
        hilog.warn(LOCK_SAFE_DOMAIN, LOCK_SAFE_TAG,
          'orchestrateOnCreate: isLocked query failed, degrade to compensation. code=%{public}d',
          typeof errObj.code === 'number' ? errObj.code : -1)
        this.needCompensation = true
        return
      }

      if (isLocked) {
        hilog.info(LOCK_SAFE_DOMAIN, LOCK_SAFE_TAG,
          'orchestrateOnCreate: screen locked, skip pre-register, mark needCompensation=true')
        this.needCompensation = true
      } else {
        try {
          await action()
          this.preRegistered = true
          hilog.info(LOCK_SAFE_DOMAIN, LOCK_SAFE_TAG,
            'orchestrateOnCreate: screen unlocked, pre-register done')
        } catch (e) {
          const errObj = e as Record<string, number | string>
          hilog.error(LOCK_SAFE_DOMAIN, LOCK_SAFE_TAG,
            'orchestrateOnCreate: action failed, mark needCompensation=true. code=%{public}d, msg=%{public}s',
            typeof errObj.code === 'number' ? errObj.code : -1,
            typeof errObj.message === 'string' ? errObj.message : JSON.stringify(e))
          this.needCompensation = true
        }
      }
    } catch (e) {
      hilog.error(LOCK_SAFE_DOMAIN, LOCK_SAFE_TAG,
        'orchestrateOnCreate: unexpected error (never throw). %{public}s', JSON.stringify(e))
    }
  }

  async triggerCompensation(source: CompensationSource): Promise<boolean> {
    if (!this.needCompensation || this.compensated) {
      return false
    }
    if (this.isCompensating) {
      hilog.info(LOCK_SAFE_DOMAIN, LOCK_SAFE_TAG,
        'triggerCompensation[%{public}s]: already compensating, skip', source)
      return false
    }
    if (this.action === null) {
      hilog.warn(LOCK_SAFE_DOMAIN, LOCK_SAFE_TAG,
        'triggerCompensation[%{public}s]: action is null, skip', source)
      return false
    }

    this.isCompensating = true
    try {
      await this.action()
      this.compensated = true
      hilog.info(LOCK_SAFE_DOMAIN, LOCK_SAFE_TAG,
        'triggerCompensation[%{public}s]: compensation succeeded, compensated=true', source)
      return true
    } catch (e) {
      const errObj = e as Record<string, number | string>
      hilog.error(LOCK_SAFE_DOMAIN, LOCK_SAFE_TAG,
        'triggerCompensation[%{public}s]: action failed, keep compensated=false for retry. code=%{public}d, msg=%{public}s',
        source,
        typeof errObj.code === 'number' ? errObj.code : -1,
        typeof errObj.message === 'string' ? errObj.message : JSON.stringify(e))
      return false
    } finally {
      this.isCompensating = false
    }
  }

  isSlotReady(): boolean {
    return this.preRegistered || this.compensated
  }
}