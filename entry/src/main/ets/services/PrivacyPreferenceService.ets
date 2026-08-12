import { preferences } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'

const TAG = 'PrivacyPref'
const DOMAIN = 0x0005

const PREFS_NAME = 'privacy_prefs'
const KEY_IS_AGREED = 'is_agreed'
const KEY_AGREED_VERSION = 'agreed_version'
const KEY_AGREED_TS = 'agreed_ts'
const KEY_DISAGREED_TS = 'disagreed_ts'

export interface PrivacyConsentState {
  isAgreed: boolean
  agreedVersion: string
  agreedTimestamp: number
  disagreedTimestamp: number
}

export enum DisplayMode {
  FIRST_LAUNCH = 'first_launch',
  VIEW = 'view',
}

export class PrivacyPreferenceService {
  private static instance: PrivacyPreferenceService | null = null

  private constructor() {}

  static getInstance(): PrivacyPreferenceService {
    if (PrivacyPreferenceService.instance === null) {
      PrivacyPreferenceService.instance = new PrivacyPreferenceService()
    }
    return PrivacyPreferenceService.instance
  }

  async getConsentState(context: common.UIAbilityContext): Promise<PrivacyConsentState> {
    const defaultState: PrivacyConsentState = {
      isAgreed: false,
      agreedVersion: '',
      agreedTimestamp: 0,
      disagreedTimestamp: 0,
    }
    try {
      const prefs = await preferences.getPreferences(context, PREFS_NAME)
      const isAgreed = await prefs.get(KEY_IS_AGREED, false) as boolean
      const agreedVersion = await prefs.get(KEY_AGREED_VERSION, '') as string
      const agreedTs = await prefs.get(KEY_AGREED_TS, 0) as number
      const disagreedTs = await prefs.get(KEY_DISAGREED_TS, 0) as number
      return {
        isAgreed,
        agreedVersion,
        agreedTimestamp: agreedTs,
        disagreedTimestamp: disagreedTs,
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'getConsentState failed: %{public}s', JSON.stringify(e))
      return defaultState
    }
  }

  async needsReconsent(context: common.UIAbilityContext, currentVersion: string): Promise<boolean> {
    try {
      const state = await this.getConsentState(context)
      if (!state.isAgreed) {
        return true
      }
      if (state.agreedVersion === '' || state.agreedVersion.length === 0) {
        return true
      }
      if (state.agreedVersion !== currentVersion) {
        return true
      }
      return false
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'needsReconsent failed: %{public}s', JSON.stringify(e))
      return true
    }
  }

  async saveConsent(context: common.UIAbilityContext, policyVersion: string): Promise<boolean> {
    try {
      const prefs = await preferences.getPreferences(context, PREFS_NAME)
      await prefs.put(KEY_IS_AGREED, true)
      await prefs.put(KEY_AGREED_VERSION, policyVersion)
      await prefs.put(KEY_AGREED_TS, Date.now())
      await prefs.flush()
      return true
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'saveConsent failed: %{public}s', JSON.stringify(e))
      return false
    }
  }

  async saveDisconsent(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const prefs = await preferences.getPreferences(context, PREFS_NAME)
      await prefs.put(KEY_DISAGREED_TS, Date.now())
      await prefs.flush()
      return true
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'saveDisconsent failed: %{public}s', JSON.stringify(e))
      return false
    }
  }
}