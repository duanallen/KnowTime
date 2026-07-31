/*
 * WidgetCard2x4 - 2x4 今日时间分布预览
 */
@Entry
@Component
struct WidgetCard2x4 {
  @LocalStorageProp('todayMinutes') todayMinutes: number = 0
  @LocalStorageProp('sessionCount') sessionCount: number = 0
  @LocalStorageProp('flowScore') flowScore: number = 0

  build() {
    Stack() {
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text(`${this.todayMinutes}`)
            .fontSize(32).fontWeight(FontWeight.Bold).fontColor('#1A73E8')
          Text('今日分钟')
            .fontSize(10).fontColor('#94A3B8')
        }
        .layoutWeight(1)

        Column({ space: 4 }) {
          Row({ space: 6 }) {
            Text('*').fontSize(14)
            Text(`${this.sessionCount}次专注`).fontSize(11).fontColor('#64748B')
          }
          Row({ space: 6 }) {
            Text('*').fontSize(14)
            Text(`心流 ${this.flowScore}`).fontSize(11).fontColor('#64748B')
          }
        }
        .layoutWeight(1.2).alignItems(HorizontalAlign.Start)

        Button('开始')
          .fontSize(12).fontColor('#FFFFFF')
          .backgroundColor('#1A73E8').borderRadius(16).height(32).width(60)
          .onClick(() => {
            postCardAction(this, {
              action: 'router',
              abilityName: 'EntryAbility',
              params: { targetPage: 'FocusPage' }
            })
          })
      }
      .width('100%').height('100%').padding(12)
      .alignItems(VerticalAlign.Center)
    }
  }
}
