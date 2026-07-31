/*
 * WidgetCard4x4 - 4x4 本周时间线热力图
 */
@Entry
@Component
struct WidgetCard4x4 {
  @LocalStorageProp('todayMinutes') todayMinutes: number = 0
  private weekData: number[] = [45, 90, 30, 120, 60, 15, 0]
  private dayLabels: string[] = ['一', '二', '三', '四', '五', '六', '日']

  build() {
    Stack() {
      Column({ space: 6 }) {
        Text('本周专注热力图')
          .fontSize(13).fontColor('#1E293B').fontWeight(FontWeight.Medium)
          .alignSelf(ItemAlign.Start)

        Row({ space: 4 }) {
          ForEach(this.weekData, (minutes: number, index: number) => {
            Column({ space: 2 }) {
              Column() {}
                .width(12).height(minutes * 0.5)
                .backgroundColor('#1A73E8').borderRadius(3)
              Text(this.dayLabels[index])
                .fontSize(9).fontColor('#94A3B8')
            }
            .alignItems(HorizontalAlign.Center)
          })
        }
        .layoutWeight(1).alignItems(VerticalAlign.Bottom).width('100%')

        Text('点击打开知时 >')
          .fontSize(10).fontColor('#64748B')
      }
      .width('100%').height('100%').padding(12)
      .onClick(() => {
        postCardAction(this, {
          action: 'router',
          abilityName: 'EntryAbility',
          params: { targetPage: 'StatsPage' }
        })
      })
    }
  }
}
