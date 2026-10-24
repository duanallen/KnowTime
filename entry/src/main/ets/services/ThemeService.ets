/*
 * ThemeService - 深色模式管理服务（单例）
 * 负责读取/持久化 theme_mode 偏好（system|light|dark），
 * 同步 AppColors 调色板与 ApplicationContext.setColorMode
 */
import { common, ConfigurationConstant } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppColors } from '../common/Theme'

const DOMAIN = 0x0006
const TAG = 'ThemeService'

export const THEME_MODE_SYSTEM: string = 'system'
export const THEME_MODE_LIGHT: string = 'light'
export const THEME_MODE_DARK: string = 'dark'

export class ThemeService {
  private static instance: ThemeService | null = null
  private mode: string = THEME_MODE_SYSTEM

  private constructor() {}

  static getInstance(): ThemeService {
    if (!ThemeService.instance) {
      ThemeService.instance = new ThemeService()
    }
    return ThemeService.instance
  }

  getMode(): string {
    return this.mode
  }

  /** 启动时初始化：读取偏好并应用 */
  async init(context: common.UIAbilityContext): Promise<void> {
    try {
      const prefs: preferences.Preferences = await preferences.getPreferences(context, 'settings_prefs')
      this.mode = await prefs.get('theme_mode', THEME_MODE_SYSTEM) as string
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'load theme_mode failed: %{public}s', (e as Error).message)
      this.mode = THEME_MODE_SYSTEM
    }
    this.apply(context)
  }

  /** 持久化并立即应用主题模式 */
  async applyTheme(context: common.UIAbilityContext, mode: string): Promise<void> {
    this.mode = mode
    try {
      const prefs: preferences.Preferences = await preferences.getPreferences(context, 'settings_prefs')
      await prefs.put('theme_mode', mode)
      await prefs.flush()
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'persist theme_mode failed: %{public}s', (e as Error).message)
    }
    this.apply(context)
  }

  /** 系统深浅色变化回调：仅跟随系统模式下重新解析应用 */
  onSystemConfigChange(context: common.UIAbilityContext): void {
    if (this.mode === THEME_MODE_SYSTEM) {
      this.apply(context)
    }
  }

  private apply(context: common.UIAbilityContext): void {
    const systemDark: boolean =
      context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
    let dark: boolean
    let colorMode: ConfigurationConstant.ColorMode
    if (this.mode === THEME_MODE_LIGHT) {
      dark = false
      colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
    } else if (this.mode === THEME_MODE_DARK) {
      dark = true
      colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK
    } else {
      dark = systemDark
      colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
    }
    AppColors.setDarkMode(dark)
    try {
      context.getApplicationContext().setColorMode(colorMode)
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'setColorMode failed: %{public}s', JSON.stringify(err))
    }
    hilog.info(DOMAIN, TAG, 'theme applied: mode=%{public}s dark=%{public}s', this.mode, String(dark))
  }
}
