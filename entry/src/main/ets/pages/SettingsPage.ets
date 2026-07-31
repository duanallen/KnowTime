import { AppColors } from '../common/Theme'
import { DatabaseHelper } from '../database/DatabaseHelper'
import { common } from '@kit.AbilityKit'

interface SettingRow {
  label: string
  value: string
  isToggle: boolean
}

@Entry
@Component
export struct SettingsPage {
  @Prop @Watch('onRefresh') refreshKey: number = 0
  @State notificationOn: boolean = true
  @State syncOn: boolean = true
  @State totalMinutes: number = 0
  private db: DatabaseHelper = DatabaseHelper.getInstance()
  private hasInit: boolean = false
  private group1: SettingRow[] = [
    { label: '专注提醒', value: '', isToggle: true },
    { label: '环境白噪音', value: '雨声', isToggle: false },
    { label: '默认时长', value: '25分钟', isToggle: false },
  ]
  private group2: SettingRow[] = [
    { label: '数据导出', value: '', isToggle: false },
    { label: '跨设备同步', value: '已开启', isToggle: true },
    { label: '深色模式', value: '跟随系统', isToggle: false },
  ]
  private group3: SettingRow[] = [
    { label: '关于知时', value: 'v1.0.0', isToggle: false },
    { label: '意见反馈', value: '', isToggle: false },
  ]

  async aboutToAppear(): Promise<void> {
    const ctx = getContext(this) as common.UIAbilityContext
    await this.db.init(ctx)
    await this.refreshData()
    this.hasInit = true
  }

  onRefresh(): void {
    if (this.hasInit && this.refreshKey > 0) {
      this.refreshData()
    }
  }

  private async refreshData(): Promise<void> {
    const now = new Date()
    now.setHours(0, 0, 0, 0)
    const todayEnd = now.getTime() + 24 * 60 * 60 * 1000
    const yearStart = new Date()
    yearStart.setMonth(0, 1)
    yearStart.setHours(0, 0, 0, 0)
    this.totalMinutes = await this.db.getTotalMinutes(yearStart.getTime(), todayEnd)
  }

  private formatTime(minutes: number): string {
    if (minutes < 60) return `累计专注 ${minutes} 分钟`
    const h = Math.floor(minutes / 60)
    const m = minutes % 60
    return `累计专注 ${h} 小时 ${m} 分钟`
  }

  build() {
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
                    if (item.value) { Text(item.value).fontSize(13).fontColor('#94A3B8') }
                    Text('>').fontSize(16).fontColor('#CBD5E1')
                  }
                }
              }
              .width('100%').height(52).padding({ left: 16, right: 12 })
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
                    if (item.value) { Text(item.value).fontSize(13).fontColor('#94A3B8') }
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
                  if (item.value) { Text(item.value).fontSize(13).fontColor('#94A3B8') }
                  Text('>').fontSize(16).fontColor('#CBD5E1')
                }
              }
              .width('100%').height(52).padding({ left: 16, right: 12 })
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
  }
}
