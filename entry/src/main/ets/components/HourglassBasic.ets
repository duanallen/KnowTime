/*
 * Hourglass - 漏沙计时器（基础版）
 * 使用最简单的组件组合实现漏沙效果
 */
@Component
export struct Hourglass {
  @Prop elapsedSeconds: number = 0
  @Prop totalSeconds: number = 1500
  @Prop sandColor: string = '#F59E0B'
  @Prop hourglassSize: number = 180

  // 计算沙子填充比例 (0-1)
  private getSandRatio(): number {
    return Math.min(this.elapsedSeconds / Math.max(this.totalSeconds, 1), 1)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 漏沙器容器
      Column() {
        // 上部分容器
        Column() {
          // 上部分沙子
          Text('⏳') // 使用emoji作为视觉提示
            .fontSize(this.hourglassSize * 0.3)
            .fontColor(this.sandColor)
            .opacity(0.8)
        }
        .width(this.hourglassSize)
        .height(this.hourglassSize * 0.4)

        // 中间分隔
        Text('|')
          .fontSize(this.hourglassSize * 0.1)
          .fontColor('#1E293B')

        // 下部分容器
        Column() {
          // 下部分沙子
          Text('⏳')
            .fontSize(this.hourglassSize * 0.3)
            .fontColor(this.sandColor)
            .opacity(0.8)
        }
        .width(this.hourglassSize)
        .height(this.hourglassSize * 0.4)
      }
      .width(this.hourglassSize)
      .height(this.hourglassSize * 1.2)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .animation({ duration: 300, curve: Curve.EaseInOut })
  }
}