/*
 * TimerRing - 环形进度（增强版，支持动画）
 */
@Component
export struct TimerRing {
  @Prop elapsedSeconds: number = 0
  @Prop totalSeconds: number = 1500
  @Prop ringColor: string = '#0D9488'
  @Prop ringWidth: number = 14
  @Prop ringSize: number = 220

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 底层轨道
      Circle()
        .fill(Color.Transparent)
        .stroke('#E2E8F0')
        .strokeWidth(this.ringWidth)
        .width(this.ringSize)
        .height(this.ringSize)

      // 进度弧
      Circle()
        .fill(Color.Transparent)
        .stroke(this.ringColor)
        .strokeWidth(this.ringWidth)
        .strokeLineCap(LineCapStyle.Round)
        .strokeDashArray([Math.PI * 2 * (this.ringSize / 2 - this.ringWidth / 2)])
        .strokeDashOffset(
          Math.PI * 2 * (this.ringSize / 2 - this.ringWidth / 2) *
          (1 - Math.min(this.elapsedSeconds / Math.max(this.totalSeconds, 1), 1))
        )
        .width(this.ringSize)
        .height(this.ringSize)
        .animation({ duration: 300, curve: Curve.Linear })
    }
    .width(this.ringSize)
    .height(this.ringSize)
  }
}
