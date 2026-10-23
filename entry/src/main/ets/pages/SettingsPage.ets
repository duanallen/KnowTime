import { AppColors } from '../common/Theme'
import { DatabaseHelper, InterruptionRow } from '../database/DatabaseHelper'
import { FocusSession } from '../models/FocusSession'
import { common, Want } from '@kit.AbilityKit'
import { picker, fileIo as fs } from '@kit.CoreFileKit'
import { preferences } from '@kit.ArkData'
import { router, promptAction } from '@kit.ArkUI'
import { hilog } from '@kit.PerformanceAnalysisKit'
import notificationManager from '@ohos.notificationManager'
import { AppInfoService } from '../services/AppInfoService'

const DOMAIN = 0x0005
const TAG = 'SettingsPage'

interface SettingRow {
  label: string
  value: string
  isToggle: boolean
}

interface RingtoneOption {
  name: string
  label: string
  rawfileName: string
}

/** 导出用的结构化 JSON 模型（ArkTS 严格模式要求显式类型） */
interface ExportInterruption {
  id: string
  timestamp: string
  durationSec: number
  reason: string
}

interface ExportSession {
  id: string
  taskName: string
  tag: string
  startTime: string
  endTime: string
  plannedDurationSec: number
  actualDurationSec: number
  state: string
  sessionType: string
  flowScore: number
  notes: string
  interruptions: ExportInterruption[]
}

interface ExportPayload {
  app: string
  version: string
  exportedAt: string
  sessionCount: number
  sessions: ExportSession[]
}

@Entry
@Component
export struct SettingsPage {
  @Prop @Watch('onRefresh') refreshKey: number = 0
  @State notificationOn: boolean = true
  @State defaultDuration: number = 25
  @State totalMinutes: number = 0
  @State ringtoneLabel: string = '系统默认'
  @State showRingtonePicker: boolean = false
  @State showDurationPicker: boolean = false
  @State exporting: boolean = false
  @State aboutVersionValue: string = 'v1.0.0'
  private db: DatabaseHelper = DatabaseHelper.getInstance()
  private hasInit: boolean = false
  // 第一组：专注相关。环境白噪音为占位功能，待实现后再加回
  private group1: SettingRow[] = [
    { label: '专注提醒', value: '', isToggle: true },
    { label: '完成铃声', value: '', isToggle: false },
    { label: '默认时长', value: '', isToggle: false },
  ]
  // 第二组：数据。跨设备同步/深色模式为占位功能，待实现后再加回
  private group2: SettingRow[] = [
    { label: '数据导出', value: 'CSV + JSON', isToggle: false },
  ]
  private group3: SettingRow[] = [
    { label: '关于知时', value: '', isToggle: false },
    { label: '隐私政策', value: '', isToggle: false },
    { label: '意见反馈', value: '', isToggle: false },
  ]
  private ringtoneOptions: RingtoneOption[] = [
    { name: 'default', label: '默认提示音', rawfileName: '' },
    { name: 'bell', label: '经典铃声', rawfileName: 'ringtone_bell.mp3' },
    { name: 'chime', label: '清脆和弦', rawfileName: 'ringtone_chime.mp3' },
    { name: 'gentle', label: '轻柔提示', rawfileName: 'ringtone_gentle.mp3' },
    { name: 'custom', label: '从文件选择...', rawfileName: '' },
  ]
  private durationOptions: number[] = [15, 25, 45, 60, 90]

  async aboutToAppear(): Promise<void> {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext
    await this.db.init(ctx)
    await this.refreshData()
    await this.loadRingtoneName(ctx)
    await this.loadDefaultDuration(ctx)
    await this.loadAboutVersion(ctx)
    await this.refreshNotificationState()
    this.hasInit = true
  }

  private async loadAboutVersion(ctx: common.UIAbilityContext): Promise<void> {
    try {
      const version = await AppInfoService.getVersionName(ctx)
      if (version && version.length > 0) {
        this.aboutVersionValue = version
      }
    } catch (e) {
      this.aboutVersionValue = 'v1.0.0'
    }
  }

  private async loadRingtoneName(ctx: common.UIAbilityContext): Promise<void> {
    try {
      const prefs: preferences.Preferences = await preferences.getPreferences(ctx, 'settings_prefs')
      const selectedRingtone: string = await prefs.get('ringtone_selected', 'default') as string
      const customUri: string = await prefs.get('ringtone_uri', '') as string

      if (selectedRingtone === 'custom' && customUri.length > 0) {
        const lastSlash: number = customUri.lastIndexOf('/')
        const fileName: string = lastSlash >= 0 ? customUri.substring(lastSlash + 1) : customUri
        this.ringtoneLabel = fileName.length > 0 ? fileName : '自定义铃声'
      } else {
        const option: RingtoneOption | undefined = this.ringtoneOptions.find((o: RingtoneOption) => o.name === selectedRingtone)
        this.ringtoneLabel = option ? option.label : '默认提示音'
      }
    } catch (e) {
      this.ringtoneLabel = '默认提示音'
    }
  }

  private async loadDefaultDuration(ctx: common.UIAbilityContext): Promise<void> {
    try {
      const prefs: preferences.Preferences = await preferences.getPreferences(ctx, 'settings_prefs')
      const val: number = await prefs.get('default_duration_minutes', 25) as number
      if (val >= 1 && val <= 180) {
        this.defaultDuration = val
      }
    } catch (e) {
      this.defaultDuration = 25
    }
  }

  /**
   * 刷新"专注提醒"开关显示。
   * 注意：isNotificationEnabled() 在部分设备上返回值不可靠（实测通知关闭仍返回 true），
   * 此处仅用于展示；开关的"开启"动作仍走 requestEnableNotification，不依赖该返回值。
   */
  private async refreshNotificationState(): Promise<void> {
    try {
      this.notificationOn = await notificationManager.isNotificationEnabled()
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'isNotificationEnabled failed: %{public}s', (e as Error).message)
    }
  }

  /** 专注提醒开关：开启走系统授权请求；关闭无法程序化完成，引导用户去系统设置 */
  private onNotificationToggle(val: boolean): void {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext
    if (val) {
      notificationManager.requestEnableNotification(ctx)
        .then(() => {
          // 授权弹窗关闭后回读真实状态刷新显示
          setTimeout(() => { this.refreshNotificationState() }, 800)
        })
        .catch((e: Error) => {
          hilog.warn(DOMAIN, TAG, 'requestEnableNotification rejected: %{public}s', e.message)
          setTimeout(() => { this.refreshNotificationState() }, 300)
        })
    } else {
      // 应用无法程序化关闭自身通知权限，拉起本应用的系统设置页引导用户手动关闭
      try {
        const want: Want = {
          bundleName: 'com.huawei.hmos.settings',
          abilityName: 'com.huawei.hmos.settings.MainAbility',
          uri: 'application_info_entry',
          parameters: { pushParams: ctx.applicationInfo.name }
        }
        ctx.startAbility(want).catch((e: Error) => {
          hilog.warn(DOMAIN, TAG, 'open settings page failed: %{public}s', e.message)
          promptAction.showToast({ message: '请在 设置→应用和元服务→知时→通知 中关闭' })
        })
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'startAbility error: %{public}s', (err as Error).message)
        promptAction.showToast({ message: '请在 设置→应用和元服务→知时→通知 中关闭' })
      }
      // 开关回弹到真实状态（通知实际仍处于开启）
      setTimeout(() => { this.refreshNotificationState() }, 500)
    }
  }

  private onSelectDuration(d: number): void {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext
    this.defaultDuration = d
    this.showDurationPicker = false
    preferences.getPreferences(ctx, 'settings_prefs').then((prefs: preferences.Preferences) => {
      prefs.put('default_duration_minutes', d).then(() => prefs.flush())
    })
  }

  onRefresh(): void {
    if (this.hasInit && this.refreshKey > 0) {
      this.refreshData()
    }
  }

  private async refreshData(): Promise<void> {
    const now: Date = new Date()
    now.setHours(0, 0, 0, 0)
    const todayEnd: number = now.getTime() + 24 * 60 * 60 * 1000
    const yearStart: Date = new Date()
    yearStart.setMonth(0, 1)
    yearStart.setHours(0, 0, 0, 0)
    this.totalMinutes = await this.db.getTotalMinutes(yearStart.getTime(), todayEnd)
  }

  private onSelectRingtone(option: RingtoneOption): void {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext
    if (option.name === 'custom') {
      this.showRingtonePicker = false
      this.pickCustomRingtone()
      return
    }
    // 保存选择
    preferences.getPreferences(ctx, 'settings_prefs').then((prefs: preferences.Preferences) => {
      prefs.put('ringtone_selected', option.name).then(() => {
        prefs.flush()
        if (option.name === 'default') {
          prefs.put('ringtone_uri', '').then(() => prefs.flush())
        }
        this.ringtoneLabel = option.label
        this.showRingtonePicker = false
      })
    })
  }

  private pickCustomRingtone(): void {
    try {
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext
      const documentSelectOptions: picker.DocumentSelectOptions = new picker.DocumentSelectOptions()
      documentSelectOptions.maxSelectNumber = 1
      documentSelectOptions.fileSuffixFilters = ['.mp3', '.wav', '.ogg', '.m4a', '.aac']
      const documentViewPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx)
      documentViewPicker.select(documentSelectOptions).then((uris: string[]) => {
        if (uris && uris.length > 0) {
          const uri: string = uris[0]
          preferences.getPreferences(ctx, 'settings_prefs').then((prefs: preferences.Preferences) => {
            prefs.put('ringtone_uri', uri)
            prefs.put('ringtone_selected', 'custom')
            prefs.flush().then(() => {
              const lastSlash: number = uri.lastIndexOf('/')
              const fileName: string = lastSlash >= 0 ? uri.substring(lastSlash + 1) : uri
              this.ringtoneLabel = fileName.length > 0 ? fileName : '自定义铃声'
            })
          })
        }
      })
    } catch (err) {
      // 用户取消
    }
  }

  // ---------------- 数据导出 ----------------

  /** 依次导出：会话CSV、中断CSV、完整JSON。用户取消某一步则中止后续 */
  private async exportData(): Promise<void> {
    if (this.exporting) return
    this.exporting = true
    try {
      const sessions: FocusSession[] = await this.db.queryAllSessions()
      const interruptions: InterruptionRow[] = await this.db.queryAllInterruptionRows()
      if (sessions.length === 0) {
        promptAction.showToast({ message: '暂无专注数据可导出' })
        return
      }
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext
      const tag: string = this.dateTag()
      promptAction.showToast({ message: `共 ${sessions.length} 条会话，将依次保存 3 个文件` })

      const ok1: boolean = await this.saveFileWithPicker(ctx,
        `knowtime_sessions_${tag}.csv`, this.buildSessionsCsv(sessions, interruptions))
      if (!ok1) return
      const ok2: boolean = await this.saveFileWithPicker(ctx,
        `knowtime_interruptions_${tag}.csv`, this.buildInterruptionsCsv(interruptions))
      if (!ok2) return
      const ok3: boolean = await this.saveFileWithPicker(ctx,
        `knowtime_backup_${tag}.json`, this.buildJson(sessions, interruptions))
      if (ok3) {
        promptAction.showToast({ message: '导出完成' })
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'exportData failed: %{public}s', (e as Error).message)
      promptAction.showToast({ message: '导出失败，请稍后重试' })
    } finally {
      this.exporting = false
    }
  }

  /** 通过系统保存选择器把内容写入用户选定的位置；返回 false 表示用户取消或写入失败 */
  private async saveFileWithPicker(ctx: common.UIAbilityContext, fileName: string, content: string): Promise<boolean> {
    try {
      const saveOptions: picker.DocumentSaveOptions = new picker.DocumentSaveOptions()
      saveOptions.newFileNames = [fileName]
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx)
      const uris: string[] = await docPicker.save(saveOptions)
      if (!uris || uris.length === 0) {
        return false
      }
      const file: fs.File = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      fs.writeSync(file.fd, content)
      fs.closeSync(file)
      hilog.info(DOMAIN, TAG, 'exported %{public}s', fileName)
      return true
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'save %{public}s failed: %{public}s', fileName, (e as Error).message)
      return false
    }
  }

  /** CSV 转义：含逗号/引号/换行的字段用双引号包裹 */
  private csvEscape(s: string): string {
    if (s.indexOf(',') >= 0 || s.indexOf('"') >= 0 || s.indexOf('\n') >= 0) {
      return '"' + s.replace(/"/g, '""') + '"'
    }
    return s
  }

  /** 会话 CSV，带 UTF-8 BOM 保证 Excel 打开中文不乱码 */
  private buildSessionsCsv(sessions: FocusSession[], interruptions: InterruptionRow[]): string {
    const countMap: Record<string, number> = {}
    interruptions.forEach((ir: InterruptionRow) => {
      countMap[ir.sessionId] = (countMap[ir.sessionId] || 0) + 1
    })
    const lines: string[] = ['会话ID,任务,标签,开始时间,结束时间,计划时长(分钟),实际时长(分钟),状态,类型,心流分数,中断次数,备注']
    sessions.forEach((s: FocusSession) => {
      const cols: string[] = [
        s.id,
        this.csvEscape(s.taskName),
        this.csvEscape(s.tag),
        this.formatDateTime(s.startTime),
        s.endTime > 0 ? this.formatDateTime(s.endTime) : '',
        Math.floor(s.plannedDuration / 60).toString(),
        Math.floor(s.actualDuration / 60).toString(),
        s.state,
        s.sessionType,
        s.flowScore.toString(),
        (countMap[s.id] || 0).toString(),
        this.csvEscape(s.notes)
      ]
      lines.push(cols.join(','))
    })
    return '﻿' + lines.join('\n')
  }

  /** 中断明细 CSV，带 UTF-8 BOM */
  private buildInterruptionsCsv(interruptions: InterruptionRow[]): string {
    const lines: string[] = ['中断ID,会话ID,发生时间,时长(秒),原因']
    interruptions.forEach((ir: InterruptionRow) => {
      const cols: string[] = [
        ir.id,
        ir.sessionId,
        this.formatDateTime(ir.timestamp),
        ir.duration.toString(),
        this.csvEscape(ir.reason)
      ]
      lines.push(cols.join(','))
    })
    return '﻿' + lines.join('\n')
  }

  /** 完整 JSON 备份（中断记录嵌套在所属会话内） */
  private buildJson(sessions: FocusSession[], interruptions: InterruptionRow[]): string {
    const exportSessions: ExportSession[] = sessions.map((s: FocusSession) => {
      const sessionInterruptions: ExportInterruption[] = interruptions
        .filter((ir: InterruptionRow) => ir.sessionId === s.id)
        .map((ir: InterruptionRow) => ({
          id: ir.id,
          timestamp: this.formatDateTime(ir.timestamp),
          durationSec: ir.duration,
          reason: ir.reason
        } as ExportInterruption))
      return {
        id: s.id,
        taskName: s.taskName,
        tag: s.tag,
        startTime: this.formatDateTime(s.startTime),
        endTime: s.endTime > 0 ? this.formatDateTime(s.endTime) : '',
        plannedDurationSec: s.plannedDuration,
        actualDurationSec: s.actualDuration,
        state: s.state,
        sessionType: s.sessionType,
        flowScore: s.flowScore,
        notes: s.notes,
        interruptions: sessionInterruptions
      } as ExportSession
    })
    const payload: ExportPayload = {
      app: 'KnowTime',
      version: this.aboutVersionValue,
      exportedAt: this.formatDateTime(Date.now()),
      sessionCount: sessions.length,
      sessions: exportSessions
    }
    return JSON.stringify(payload, null, 2)
  }

  private formatDateTime(ms: number): string {
    const d: Date = new Date(ms)
    const p = (n: number): string => n.toString().padStart(2, '0')
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`
  }

  private dateTag(): string {
    const d: Date = new Date()
    const p = (n: number): string => n.toString().padStart(2, '0')
    return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}`
  }

  private formatTime(minutes: number): string {
    if (minutes < 60) return `累计专注 ${minutes} 分钟`
    const h: number = Math.floor(minutes / 60)
    const m: number = minutes % 60
    return `累计专注 ${h} 小时 ${m} 分钟`
  }

  build() {
    Stack() {
      Column() {
        Scroll() {
          Column({ space: 20 }) {
            Row({ space: 14 }) {
              Column() {
                Text('知').fontSize(26).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
              }
              .width(56).height(56).borderRadius(28)
              .backgroundColor('#1A73E8').justifyContent(FlexAlign.Center)

              Column({ space: 2 }) {
                Text('知时用户').fontSize(16).fontWeight(FontWeight.Medium).fontColor('#1E293B')
                Text(this.formatTime(this.totalMinutes)).fontSize(12).fontColor('#94A3B8')
              }
              .alignItems(HorizontalAlign.Start).layoutWeight(1)
            }
            .width('100%').padding(20).backgroundColor('#FFFFFF').borderRadius(16)

            Column() {
              ForEach(this.group1, (item: SettingRow, idx: number) => {
                Row() {
                  Text(item.label).fontSize(15).fontColor('#1E293B').layoutWeight(1)
                  if (item.isToggle) {
                    Toggle({ type: ToggleType.Switch, isOn: this.notificationOn })
                      .onChange((val: boolean) => { this.onNotificationToggle(val) })
                  } else {
                    Row({ space: 4 }) {
                      if (item.label === '完成铃声') {
                        Text(this.ringtoneLabel).fontSize(13).fontColor('#94A3B8')
                      } else if (item.label === '默认时长') {
                        Text(`${this.defaultDuration}分钟`).fontSize(13).fontColor('#94A3B8')
                      }
                      Text('>').fontSize(16).fontColor('#CBD5E1')
                    }
                  }
                }
                .width('100%').height(52).padding({ left: 16, right: 12 })
                .onClick(() => {
                  if (!item.isToggle && item.label === '完成铃声') {
                    this.showRingtonePicker = true
                  } else if (!item.isToggle && item.label === '默认时长') {
                    this.showDurationPicker = true
                  }
                })
                .border({ width: { bottom: idx < this.group1.length - 1 ? 0.5 : 0 }, color: '#F1F5F9' })
              })
            }
            .width('100%').backgroundColor('#FFFFFF').borderRadius(16)

            Column() {
              ForEach(this.group2, (item: SettingRow, idx: number) => {
                Row() {
                  Text(item.label).fontSize(15).fontColor('#1E293B').layoutWeight(1)
                  Row({ space: 4 }) {
                    if (item.value.length > 0) {
                      Text(item.value).fontSize(13).fontColor('#94A3B8')
                    }
                    Text('>').fontSize(16).fontColor('#CBD5E1')
                  }
                }
                .width('100%').height(52).padding({ left: 16, right: 12 })
                .opacity(this.exporting ? 0.5 : 1)
                .onClick(() => {
                  if (item.label === '数据导出') {
                    this.exportData()
                  }
                })
                .border({ width: { bottom: idx < this.group2.length - 1 ? 0.5 : 0 }, color: '#F1F5F9' })
              })
            }
            .width('100%').backgroundColor('#FFFFFF').borderRadius(16)

            Column() {
              ForEach(this.group3, (item: SettingRow, idx: number) => {
                Row() {
                  Text(item.label).fontSize(15).fontColor('#1E293B').layoutWeight(1)
                  Row({ space: 4 }) {
                    if (item.label === '关于知时') {
                      Text(this.aboutVersionValue).fontSize(13).fontColor('#94A3B8')
                    } else if (item.value.length > 0) {
                      Text(item.value).fontSize(13).fontColor('#94A3B8')
                    }
                    Text('>').fontSize(16).fontColor('#CBD5E1')
                  }
                }
                .width('100%').height(52).padding({ left: 16, right: 12 })
                .onClick(() => {
                  if (item.label === '关于知时') {
                    router.pushUrl({ url: 'pages/AboutPage' }).catch((e: Error) => {
                      promptAction.showToast({ message: '页面打开失败，请稍后重试' })
                    })
                  } else if (item.label === '隐私政策') {
                    const routeParams: Record<string, string> = {}
                    routeParams['displayMode'] = 'view'
                    router.pushUrl({ url: 'pages/PrivacyPolicyPage', params: routeParams })
                  } else if (item.label === '意见反馈') {
                    promptAction.showToast({ message: '功能暂不可用，请稍后重试' })
                  }
                })
                .border({ width: { bottom: idx < this.group3.length - 1 ? 0.5 : 0 }, color: '#F1F5F9' })
              })
            }
            .width('100%').backgroundColor('#FFFFFF').borderRadius(16)

            Blank().height(20)
          }
          .padding({ left: 20, right: 20, bottom: 40 })
        }
        .layoutWeight(1).scrollBar(BarState.Off)
      }
      .width('100%').height('100%').backgroundColor('#F8FAFC')

      // 铃声选择弹出层
      if (this.showRingtonePicker) {
        Column() {
          Column() {
            Column({ space: 0 }) {
              Text('选择铃声').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#1E293B')
                .width('100%').padding({ left: 20, right: 20, top: 20, bottom: 12 })

              ForEach(this.ringtoneOptions, (option: RingtoneOption) => {
                Row() {
                  Text(option.label).fontSize(16).fontColor('#1E293B').layoutWeight(1)
                  if (option.name === 'default' && this.ringtoneLabel === '默认提示音') {
                    Text('✓').fontSize(18).fontColor(AppColors.PRIMARY)
                  }
                }
                .width('100%').height(48).padding({ left: 20, right: 20 })
                .onClick(() => { this.onSelectRingtone(option) })
              })

              Blank().height(8)
            }
            .width('100%')
            .backgroundColor('#FFFFFF').borderRadius({ topLeft: 16, topRight: 16 })

            Row() {
              Text('取消').fontSize(16).fontColor('#64748B')
            }
            .width('100%').height(52)
            .backgroundColor('#FFFFFF').borderRadius({ bottomLeft: 16, bottomRight: 16 })
            .margin({ top: 1 })
            .justifyContent(FlexAlign.Center)
            .onClick(() => { this.showRingtonePicker = false })
          }
          .width('100%')
        }
        .width('100%').height('100%')
        .backgroundColor('#00000050')
        .justifyContent(FlexAlign.End)
        .onClick(() => { this.showRingtonePicker = false })
      }

      // 默认时长选择弹出层
      if (this.showDurationPicker) {
        Column() {
          Column() {
            Column({ space: 0 }) {
              Text('默认时长').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#1E293B')
                .width('100%').padding({ left: 20, right: 20, top: 20, bottom: 12 })

              ForEach(this.durationOptions, (d: number) => {
                Row() {
                  Text(`${d} 分钟`).fontSize(16).fontColor('#1E293B').layoutWeight(1)
                  if (d === this.defaultDuration) {
                    Text('✓').fontSize(18).fontColor(AppColors.PRIMARY)
                  }
                }
                .width('100%').height(48).padding({ left: 20, right: 20 })
                .onClick(() => { this.onSelectDuration(d) })
              })

              Blank().height(8)
            }
            .width('100%')
            .backgroundColor('#FFFFFF').borderRadius({ topLeft: 16, topRight: 16 })

            Row() {
              Text('取消').fontSize(16).fontColor('#64748B')
            }
            .width('100%').height(52)
            .backgroundColor('#FFFFFF').borderRadius({ bottomLeft: 16, bottomRight: 16 })
            .margin({ top: 1 })
            .justifyContent(FlexAlign.Center)
            .onClick(() => { this.showDurationPicker = false })
          }
          .width('100%')
        }
        .width('100%').height('100%')
        .backgroundColor('#00000050')
        .justifyContent(FlexAlign.End)
        .onClick(() => { this.showDurationPicker = false })
      }
    }
    .width('100%').height('100%')
  }
}
