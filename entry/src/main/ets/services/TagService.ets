/*
 * TagService - 自定义标签管理服务（单例）
 * 标签列表持久化于 preferences 'settings_prefs' 的 key 'tag_list'（JSON 字符串数组）。
 * 删除为归档语义：仅从可选列表移除，不改动历史会话数据。
 */
import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0007
const TAG = 'TagService'

const PREFS_NAME: string = 'settings_prefs'
const KEY_TAG_LIST: string = 'tag_list'

/** 内置默认标签 */
export const DEFAULT_TAGS: string[] = ['学习', '工作', '阅读', '写作', '编程', '设计', '运动']
/** 单个标签最大字符数 */
export const TAG_MAX_LENGTH: number = 8
/** 标签总数上限 */
export const TAG_MAX_COUNT: number = 20

export class TagService {
  private static instance: TagService | null = null

  private constructor() {}

  static getInstance(): TagService {
    if (!TagService.instance) {
      TagService.instance = new TagService()
    }
    return TagService.instance
  }

  /** 读取标签列表；未持久化、解析失败或持久化列表为空时回退内置默认 */
  async getTags(context: common.UIAbilityContext): Promise<string[]> {
    try {
      const prefs: preferences.Preferences = await preferences.getPreferences(context, PREFS_NAME)
      const raw: string = await prefs.get(KEY_TAG_LIST, '') as string
      if (raw.length > 0) {
        const parsed: string[] = JSON.parse(raw) as string[]
        if (parsed.length > 0) {
          return parsed
        }
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'getTags failed: %{public}s', (e as Error).message)
    }
    return DEFAULT_TAGS.slice()
  }

  /**
   * 添加标签。校验：去空白后非空、不超过 8 字符、不重复、总数不超过 20。
   * @returns true 表示添加成功，false 表示校验失败
   */
  async addTag(context: common.UIAbilityContext, tag: string): Promise<boolean> {
    const trimmed: string = tag.trim()
    if (trimmed.length === 0 || trimmed.length > TAG_MAX_LENGTH) {
      return false
    }
    const tags: string[] = await this.getTags(context)
    if (tags.indexOf(trimmed) >= 0 || tags.length >= TAG_MAX_COUNT) {
      return false
    }
    tags.push(trimmed)
    await this.saveTags(context, tags)
    return true
  }

  /** 删除标签（归档语义：只从可选列表移除，历史会话数据保持不变） */
  async removeTag(context: common.UIAbilityContext, tag: string): Promise<void> {
    const tags: string[] = await this.getTags(context)
    const idx: number = tags.indexOf(tag)
    if (idx >= 0) {
      tags.splice(idx, 1)
      await this.saveTags(context, tags)
    }
  }

  private async saveTags(context: common.UIAbilityContext, tags: string[]): Promise<void> {
    try {
      const prefs: preferences.Preferences = await preferences.getPreferences(context, PREFS_NAME)
      await prefs.put(KEY_TAG_LIST, JSON.stringify(tags))
      await prefs.flush()
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'saveTags failed: %{public}s', (e as Error).message)
    }
  }
}
