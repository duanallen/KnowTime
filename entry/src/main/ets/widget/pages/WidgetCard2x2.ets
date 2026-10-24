/*
 * WidgetCard2x2 - 2x2 快速启动卡片
 */
@Entry
@Component
struct WidgetCard2x2 {
  @LocalStorageProp('todayMinutes') todayMinutes: number = 0
  @LocalStorageProp('currentTask') currentTask: string = '开始专注'

  build() {
    Stack() {
      Column({ space: 4 }) {
        Text(this.currentTask)
          .fontSize(12).fontColor('#64748B').maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${this.todayMinutes}`)
          .fontSize(28).fontWeight(FontWeight.Bold).fontColor('#1A73E8')
        Text('今日已专注(分钟)')
          .fontSize(10).fontColor('#94A3B8')
        Button('一键开始专注')
          .fontSize(12).fontColor('#FFFFFF')
          .backgroundColor('#1A73E8').borderRadius(16).height(28)
          .onClick(() => {
            postCardAction(this, {
              action: 'router',
              abilityName: 'EntryAbility',
              params: { targetPage: 'FocusPage', autoStartFocus: 'true' }
            })
          })
      }
      .width('100%').height('100%').padding(8)
      .justifyContent(FlexAlign.Center)
    }
  }
}
