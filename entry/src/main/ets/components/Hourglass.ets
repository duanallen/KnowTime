/*
 * Hourglass - 漏沙计时器
 * 通过上下两个三角形模拟漏沙效果，直观感受时间流逝
 */
@Component
export struct Hourglass {
  @Prop elapsedSeconds: number = 0
  @Prop totalSeconds: number = 1500
  @Prop sandColor: string = '#F59E0B'
  @Prop hourglassSize: number = 180
  @Prop hourglassColor: string = '#1E293B'

  // 计算沙子填充比例 (0-1)
  private getSandRatio(): number {
    return Math.min(this.elapsedSeconds / Math.max(this.totalSeconds, 1), 1)
  }

  build() {
    Canvas(this.context)
      .width(this.hourglassSize)
      .height(this.hourglassSize * 1.2)
      .onReady(() => {
        this.drawHourglass()
      })
      .animation({ duration: 300, curve: Curve.EaseInOut })
  }

  @State context: 2DCanvasRenderingContext2D = new 2DCanvasRenderingContext2D()

  // 沙子粒子系统
  @State particles: Array<{x: number, y: number, speed: number}> = []

  drawHourglass() {
    const ctx = this.context
    const width = this.hourglassSize
    const height = this.hourglassSize * 1.2
    const centerX = width / 2
    const centerY = height / 2
    const sandRatio = this.getSandRatio()

    // 清空画布
    ctx.clearRect(0, 0, width, height)

    // 绘制漏沙器轮廓
    this.drawHourglassShape(ctx, centerX, centerY, width, height)

    // 绘制上部分（剩余时间）
    this.drawUpperSand(ctx, centerX, centerY, width, height, sandRatio)

    // 绘制下部分（已流逝时间）
    this.drawLowerSand(ctx, centerX, centerY, width, height, sandRatio)

    // 绘制流动的沙子（粒子效果）
    this.drawFlowingSand(ctx, centerX, centerY, width, height, sandRatio)
  }

  // 绘制漏沙器形状
  private drawHourglassShape(ctx: 2DCanvasRenderingContext2D, centerX: number, centerY: number, width: number, height: number) {
    const halfWidth = width / 2 * 0.8
    const halfHeight = height / 2 * 0.8
    const neckWidth = width * 0.05

    ctx.strokeStyle = this.hourglassColor
    ctx.lineWidth = 2

    ctx.beginPath()
    // 左上角
    ctx.moveTo(centerX - halfWidth, centerY - halfHeight)
    // 左斜边到瓶颈
    ctx.lineTo(centerX - neckWidth, centerY - neckWidth * 2)
    // 瓶颈左侧
    ctx.lineTo(centerX - neckWidth, centerY)
    // 右斜边到瓶颈
    ctx.lineTo(centerX - neckWidth, centerY + neckWidth * 2)
    // 左下角
    ctx.lineTo(centerX - halfWidth, centerY + halfHeight)

    // 下边
    ctx.lineTo(centerX + halfWidth, centerY + halfHeight)

    // 右边
    ctx.lineTo(centerX + neckWidth, centerY + neckWidth * 2)
    ctx.lineTo(centerX + neckWidth, centerY)
    ctx.lineTo(centerX + neckWidth, centerY - neckWidth * 2)
    ctx.lineTo(centerX + halfWidth, centerY - halfHeight)

    // 上边
    ctx.closePath()
    ctx.stroke()
  }

  // 绘制上部分沙子（剩余时间）
  private drawUpperSand(ctx: 2DCanvasRenderingContext2D, centerX: number, centerY: number, width: number, height: number, sandRatio: number) {
    const halfWidth = width / 2 * 0.8
    const halfHeight = height / 2 * 0.8
    const neckWidth = width * 0.05

    // 计算剩余沙子的高度比例
    const remainingRatio = 1 - sandRatio
    const sandHeight = (halfHeight - neckWidth * 2) * remainingRatio

    if (sandHeight > 0) {
      ctx.fillStyle = this.sandColor
      ctx.globalAlpha = 0.8

      ctx.beginPath()
      // 沙子表面线
      const surfaceWidth = halfWidth - (halfWidth - neckWidth) * (sandHeight / (halfHeight - neckWidth * 2))
      ctx.moveTo(centerX - surfaceWidth, centerY - halfHeight + sandHeight)
      ctx.lineTo(centerX + surfaceWidth, centerY - halfHeight + sandHeight)

      // 右斜边
      ctx.lineTo(centerX + neckWidth, centerY - neckWidth * 2)
      // 瓶颈
      ctx.lineTo(centerX - neckWidth, centerY - neckWidth * 2)
      ctx.closePath()
      ctx.fill()
      ctx.globalAlpha = 1.0
    }
  }

  // 绘制下部分沙子（已流逝时间）
  private drawLowerSand(ctx: 2DCanvasRenderingContext2D, centerX: number, centerY: number, width: number, height: number, sandRatio: number) {
    const halfWidth = width / 2 * 0.8
    const halfHeight = height / 2 * 0.8
    const neckWidth = width * 0.05

    // 计算累积沙子的高度比例
    const sandHeight = (halfHeight - neckWidth * 2) * sandRatio

    if (sandHeight > 0) {
      ctx.fillStyle = this.sandColor
      ctx.globalAlpha = 0.8

      ctx.beginPath()
      // 瓶颈
      ctx.moveTo(centerX - neckWidth, centerY)
      ctx.lineTo(centerX + neckWidth, centerY)

      // 右斜边
      ctx.lineTo(centerX + halfWidth, centerY + halfHeight)

      // 底边
      ctx.lineTo(centerX - halfWidth, centerY + halfHeight)

      // 左斜边
      ctx.lineTo(centerX - neckWidth, centerY + neckWidth * 2)

      // 沙子表面线
      const surfaceWidth = neckWidth + (halfWidth - neckWidth) * (sandHeight / (halfHeight - neckWidth * 2))
      ctx.moveTo(centerX - surfaceWidth, centerY + neckWidth * 2 + sandHeight)
      ctx.lineTo(centerX + surfaceWidth, centerY + neckWidth * 2 + sandHeight)

      ctx.closePath()
      ctx.fill()
      ctx.globalAlpha = 1.0
    }
  }

  // 绘制流动的沙子粒子
  private drawFlowingSand(ctx: 2DCanvasRenderingContext2D, centerX: number, centerY: number, width: number, height: number, sandRatio: number) {
    if (sandRatio > 0 && sandRatio < 1) {
      const neckWidth = width * 0.05
      const particleCount = 5

      ctx.fillStyle = this.sandColor
      ctx.globalAlpha = 0.6

      for (let i = 0; i < particleCount; i++) {
        const particleY = (Date.now() / 50 + i * 10) % (height * 0.4) - height * 0.2

        // 在瓶颈附近的粒子
        if (Math.abs(particleY) < 10) {
          const particleX = centerX + (Math.random() - 0.5) * neckWidth * 2
          ctx.beginPath()
          ctx.arc(particleX, centerY + particleY, 1.5, 0, Math.PI * 2)
          ctx.fill()
        }

        // 下落的粒子
        if (particleY > 10 && particleY < 50) {
          const particleX = centerX + (Math.random() - 0.5) * neckWidth * 3
          ctx.beginPath()
          ctx.arc(particleX, centerY + particleY, 1, 0, Math.PI * 2)
          ctx.fill()
        }
      }

      ctx.globalAlpha = 1.0
    }
  }
}