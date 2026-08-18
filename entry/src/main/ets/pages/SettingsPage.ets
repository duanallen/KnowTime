import { AppColors } from '../common/Theme'
import { DatabaseHelper } from '../database/DatabaseHelper'
import { common } from '@kit.AbilityKit'
import { picker } from '@kit.CoreFileKit'
import { preferences } from '@kit.ArkData'
import { resourceManager } from '@kit.LocalizationKit'
import { router, promptAction } from '@kit.ArkUI'
import { AppInfoService } from '../services/AppInfoService'

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

@Entry
@Component
export struct SettingsPage {
  @Prop @Watch('onRefresh') refreshKey: number = 0
  @State notificationOn: boolean = true
  @State syncOn: boolean = true
  @State totalMinutes: number = 0
  @State ringtoneLabel: string = '系统默认'
  @State showRingtonePicker: boolean = false
  @State aboutVersionValue: string = 'v1.0.0'
  private db: DatabaseHelper = DatabaseHelper.getInstance()
  private hasInit: boolean = false
  private group1: SettingRow[] = [
    { label: '专注提醒', value: '', isToggle: true },
    { label: '完成铃声', value: '', isToggle: false },
    { label: '环境白噪音', value: '雨声', isToggle: false },
    { label: '默认时长', value: '25分钟', isToggle: false },
  ]
  private group2: SettingRow[] = [
    { label: '数据导出', value: '', isToggle: false },
    { label: '跨设备同步', value: '已开启', isToggle: true },
    { label: '深色模式', value: '跟随系统', isToggle: false },
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

  async aboutToAppear(): Promise<void> {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext
    await this.db.init(ctx)
    await this.refreshData()
    await this.loadRingtoneName(ctx)
    await this.loadAboutVersion(ctx)
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
                      .onChange((val: boolean) => { this.notificationOn = val })
                  } else {
                    Row({ space: 4 }) {
                      if (item.label === '完成铃声') {
                        Text(this.ringtoneLabel).fontSize(13).fontColor('#94A3B8')
                      } else if (item.value.length > 0) {
                        Text(item.value).fontSize(13).fontColor('#94A3B8')
                      }
                      Text('>').fontSize(16).fontColor('#CBD5E1')
                    }
                  }
                }
                .width('100%').height(52).padding({ left: 16, right: 12 })
                .onClick(() => {
                  if (!item.isToggle && item.label === '完成铃声') {
                    this.showRingtonePicker = true
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
                  if (item.isToggle) {
                    Toggle({ type: ToggleType.Switch, isOn: this.syncOn })
                      .onChange((val: boolean) => { this.syncOn = val })
                  } else {
                    Row({ space: 4 }) {
                      if (item.value.length > 0) {
                        Text(item.value).fontSize(13).fontColor('#94A3B8')
                      }
                      Text('>').fontSize(16).fontColor('#CBD5E1')
                    }
                  }
                }
                .width('100%').height(52).padding({ left: 16, right: 12 })
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
    }
    .width('100%').height('100%')
  }
}
