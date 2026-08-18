import { common, bundleManager } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'

const TAG = 'AppInfoService'
const DOMAIN = 0x0006

const VENDOR = '段力'

export interface AppInfo {
  appName: string
  vendor: string
  versionName: string
  appSlogan: string
  marketStatusText: string
  contactEmail: string
  vendorStatement: string
  feedbackPageUrl: string
}

export class AppInfoService {
  static async getAppInfo(context: common.UIAbilityContext): Promise<AppInfo> {
    let appName: string = '知时'
    let vendor: string = VENDOR
    let versionName: string = ''
    let appSlogan: string = '时间感知型深度专注助手'
    let marketStatusText: string = '本应用已上架华为应用市场'
    let contactEmail: string = 'support@knowtime.com'
    let vendorStatement: string = `应用由 ${VENDOR} 开发`
    let feedbackPageUrl: string = 'pages/FeedbackPage'

    try {
      appName = await context.resourceManager.getStringByName('about_app_name_fallback')
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'read appName failed: %{public}s', JSON.stringify(e))
    }

    try {
      const fallbackVendor = await context.resourceManager.getStringByName('about_vendor_fallback')
      vendor = fallbackVendor.length > 0 ? fallbackVendor : VENDOR
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'read vendor failed: %{public}s', JSON.stringify(e))
    }

    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      if (info && info.versionName && info.versionName.length > 0) {
        versionName = `v${info.versionName}`
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'read versionName failed: %{public}s', JSON.stringify(e))
    }

    try {
      appSlogan = await context.resourceManager.getStringByName('about_app_slogan')
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'read appSlogan failed: %{public}s', JSON.stringify(e))
    }

    try {
      marketStatusText = await context.resourceManager.getStringByName('about_market_status')
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'read marketStatus failed: %{public}s', JSON.stringify(e))
    }

    try {
      contactEmail = await context.resourceManager.getStringByName('about_contact_email')
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'read contactEmail failed: %{public}s', JSON.stringify(e))
    }

    try {
      feedbackPageUrl = await context.resourceManager.getStringByName('about_feedback_page_url')
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'read feedbackPageUrl failed: %{public}s', JSON.stringify(e))
    }

    vendorStatement = AppInfoService.buildVendorStatement(context, vendor)

    return {
      appName,
      vendor,
      versionName,
      appSlogan,
      marketStatusText,
      contactEmail,
      vendorStatement,
      feedbackPageUrl,
    }
  }

  static buildVendorStatement(context: common.UIAbilityContext, vendor: string): string {
    try {
      const template = context.resourceManager.getStringByNameSync('about_vendor_statement_template')
      if (template && template.length > 0) {
        return template.replace('%s', vendor)
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'read vendor template failed: %{public}s', JSON.stringify(e))
    }
    return `应用由 ${vendor} 开发`
  }

  static async getVersionName(context: common.UIAbilityContext): Promise<string> {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      if (info && info.versionName && info.versionName.length > 0) {
        return `v${info.versionName}`
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'getVersionName failed: %{public}s', JSON.stringify(e))
    }
    try {
      return await context.resourceManager.getStringByName('about_version_unknown')
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'read version unknown fallback failed: %{public}s', JSON.stringify(e))
      return '版本未知'
    }
  }
}