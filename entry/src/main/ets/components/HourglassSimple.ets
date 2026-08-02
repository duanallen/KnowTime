/*
 * Hourglass - 漏沙计时器（简化版）
 * 使用更基础的实现方式，避免Canvas复杂度
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
      // 漏沙器背景
      Image($r('app.media.hourglass_bg'))
        .width(this.hourglassSize)
        .height(this.hourglassSize * 1.2)
        .interpolation(ImageInterpolation.High)

      // 上部分沙子（剩余时间）
      Column() {
        // 沙子填充区域
        Rectangle()
          .fill(this.sandColor)
          .width(this.hourglassSize * 0.8)
          .height(this.hourglassSize * 0.4 * (1 - this.getSandRatio()))
          .opacity(0.8)
          .borderRadius({
            topLeft: this.hourglassSize * 0.1,
            topRight: this.hourglassSize * 0.1
          })
        
        // 沙子表面
        Rectangle()
          .fill(this.sandColor)
          .width(this.hourglassSize * 0.8 * (1 - this.getSandRatio() * 0.3))
          .height(2)
          .opacity(0.9)
      }
      .width(this.hourglassSize * 0.8)
      .height(this.hourglassSize * 0.4)
      .position({ x: this.hourglassSize * 0.1, y: this.hourglassSize * 0.1 })

      // 下部分沙子（已流逝时间）
      Column() {
        // 沙子表面
        Rectangle()
          .fill(this.sandColor)
          .width(this.hourglassSize * 0.8 * (1 - (1 - this.getSandRatio()) * 0.3))
          .height(2)
          .opacity(0.9)
        
        // 沙子填充区域
        Rectangle()
          .fill(this.sandColor)
          .width(this.hourglassSize * 0.8)
          .height(this.hourglassSize * 0.4 * this.getSandRatio())
          .opacity(0.8)
          .borderRadius({
            bottomLeft: this.hourglassSize * 0.1,
            bottomRight: this.hourglassSize * 0.1
          })
      }
      .width(this.hourglassSize * 0.8)
      .height(this.hourglassSize * 0.4)
      .position({ x: this.hourglassSize * 0.1, y: this.hourglassSize * 0.6 })

      // 流动的沙子粒子效果
      ForEach(Array.from({ length: 5 }, (_, i) => i), (i) => {
        Circle()
          .fill(this.sandColor)
          .width(3)
          .height(3)
          .opacity(0.6)
          .position({
            x: this.hourglassSize * 0.4 + (Math.random() - 0.5) * this.hourglassSize * 0.2,
            y: this.hourglassSize * 0.5 + Math.sin(Date.now() / 1000 + i) * this.hourglassSize * 0.05
          })
      })
    }
    .width(this.hourglassSize)
    .height(this.hourglassSize * 1.2)
    .animation({ duration: 300, curve: Curve.EaseInOut })
  }
}