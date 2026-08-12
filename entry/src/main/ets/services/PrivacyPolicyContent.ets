import { common } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { util } from '@kit.ArkTS'

const TAG = 'PrivacyContent'
const DOMAIN = 0x0005

const DEFAULT_CHAPTER_TITLES: string[] = [
  '引言',
  '信息收集与使用',
  '信息存储',
  '信息共享与披露',
  '用户权利',
  '信息安全',
  '未成年人保护',
  '政策更新',
  '联系方式',
]

export interface PolicyMeta {
  version: string
  updateDate: string
  applicableAppVersion: string
  chapterTitles: string[]
}

export class PrivacyPolicyContent {
  static async loadPolicyText(context: common.UIAbilityContext): Promise<string> {
    try {
      const buffer = await context.resourceManager.getRawFileContent('privacy_policy.txt')
      const textDecoder = util.TextDecoder.create('utf-8')
      const text = textDecoder.decodeToString(buffer)
      return text
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'loadPolicyText failed: %{public}s', JSON.stringify(e))
      try {
        const fallback = await context.resourceManager.getStringByName('privacy_policy_load_failed')
        return fallback
      } catch (e2) {
        hilog.error(DOMAIN, TAG, 'load fallback failed: %{public}s', JSON.stringify(e2))
        return '隐私政策内容加载失败，请稍后重试或联系开发者'
      }
    }
  }

  static async getPolicyMeta(context: common.UIAbilityContext): Promise<PolicyMeta> {
    const defaultMeta: PolicyMeta = {
      version: '1.0',
      updateDate: '1970-01-01',
      applicableAppVersion: 'v1.0.0 起',
      chapterTitles: DEFAULT_CHAPTER_TITLES,
    }
    try {
      const version = await context.resourceManager.getStringByName('privacy_policy_version')
      const updateDate = await context.resourceManager.getStringByName('privacy_policy_update_date')
      const applicableAppVersion = await context.resourceManager.getStringByName('privacy_policy_applicable_version')
      return {
        version,
        updateDate,
        applicableAppVersion,
        chapterTitles: DEFAULT_CHAPTER_TITLES,
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'getPolicyMeta failed: %{public}s', JSON.stringify(e))
      return defaultMeta
    }
  }
}