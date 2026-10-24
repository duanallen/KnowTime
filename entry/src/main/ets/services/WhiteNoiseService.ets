/*
 * WhiteNoiseService - 环境白噪音播放服务（单例）
 *
 * 硬约束：仅承诺"前台专注中"播放。应用退后台、页面不可见、专注暂停/停止/完成时
 * 必须由调用方触发 stop()/pause()，本服务自身不做任何后台保活手段。
 * 播放源：rawfile 内 24s 无缝循环 wav（white_noise.wav / rain.wav），AVPlayer loop=true。
 */
import { media } from '@kit.MediaKit'
import { common } from '@kit.AbilityKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { resourceManager } from '@kit.LocalizationKit'

const DOMAIN = 0x0006
const TAG = 'WhiteNoiseService'

export const WHITE_NOISE_OFF: string = 'off'
export const WHITE_NOISE_WHITE: string = 'white'
export const WHITE_NOISE_RAIN: string = 'rain'

const NOISE_FILE_MAP: Record<string, string> = {
  'white': 'white_noise.wav',
  'rain': 'rain.wav'
}
const PLAY_VOLUME: number = 0.6

export class WhiteNoiseService {
  private static instance: WhiteNoiseService | null = null

  private player: media.AVPlayer | null = null
  private playingType: string = WHITE_NOISE_OFF
  private isPaused: boolean = false
  // 当前播放使用的 raw fd，播放期间必须保持打开，release 后由本服务关闭
  private currentFd: number = -1

  private constructor() {
  }

  static getInstance(): WhiteNoiseService {
    if (WhiteNoiseService.instance === null) {
      WhiteNoiseService.instance = new WhiteNoiseService()
    }
    return WhiteNoiseService.instance
  }

  /** 当前噪音类型；'off' 表示未播放 */
  getPlayingType(): string {
    return this.playingType
  }

  /**
   * 播放指定类型白噪音（'white' | 'rain'）。
   * 幂等：同类型已在播放时直接返回；同类型已暂停时恢复播放。
   * 任何失败仅 hilog 记录并安全释放，不向调用方抛错。
   */
  async play(context: common.UIAbilityContext, type: string): Promise<void> {
    if (type === WHITE_NOISE_OFF) {
      this.stop()
      return
    }
    const fileName: string | undefined = NOISE_FILE_MAP[type]
    if (fileName === undefined) {
      hilog.warn(DOMAIN, TAG, 'unknown noise type: %{public}s', type)
      return
    }

    // 幂等：同类型实例仍在（播放中或已暂停）
    if (this.playingType === type && this.player !== null) {
      if (this.isPaused) {
        try {
          await this.player.play()
          this.isPaused = false
          hilog.info(DOMAIN, TAG, 'resumed %{public}s', type)
        } catch (e) {
          hilog.error(DOMAIN, TAG, 'resume failed: %{public}s', (e as Error).message)
          this.stop()
        }
      }
      return
    }

    // 切换类型前先释放旧实例
    this.stop()

    let rawFd: resourceManager.RawFileDescriptor
    try {
      rawFd = await context.resourceManager.getRawFd(fileName)
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'getRawFd %{public}s failed: %{public}s', fileName, (e as Error).message)
      return
    }
    this.currentFd = rawFd.fd

    try {
      const avPlayer: media.AVPlayer = await media.createAVPlayer()
      this.player = avPlayer

      avPlayer.on('stateChange', (state: media.AVPlayerState) => {
        if (this.player !== avPlayer) {
          return
        }
        if (state === 'prepared') {
          avPlayer.setVolume(PLAY_VOLUME)
          avPlayer.loop = true
          avPlayer.play()
          this.playingType = type
          hilog.info(DOMAIN, TAG, 'playing %{public}s', type)
        } else if (state === 'error') {
          hilog.error(DOMAIN, TAG, 'AVPlayer entered error state')
          this.stop()
        }
      })
      avPlayer.on('error', (err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'AVPlayer error: %{public}s', err.message)
        if (this.player === avPlayer) {
          this.stop()
        }
      })

      avPlayer.fdSrc = { fd: rawFd.fd, offset: rawFd.offset, length: rawFd.length }
      await avPlayer.prepare()
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'start %{public}s failed: %{public}s', fileName, (e as Error).message)
      this.stop()
    }
  }

  /** 暂停播放（保留实例，play() 同类型可恢复） */
  pause(): void {
    const p: media.AVPlayer | null = this.player
    if (p === null || this.isPaused) {
      return
    }
    try {
      p.pause().then(() => {
        this.isPaused = true
        hilog.info(DOMAIN, TAG, 'paused')
      }).catch((e: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'pause failed: %{public}s', e.message)
      })
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'pause error: %{public}s', (e as Error).message)
    }
  }

  /** 停止并释放实例，关闭 raw fd（幂等） */
  stop(): void {
    const p: media.AVPlayer | null = this.player
    this.player = null
    this.playingType = WHITE_NOISE_OFF
    this.isPaused = false
    const fd: number = this.currentFd
    this.currentFd = -1

    const closeFd = (): void => {
      if (fd >= 0) {
        try {
          fs.closeSync(fd)
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'close raw fd failed: %{public}s', (e as Error).message)
        }
      }
    }

    if (p === null) {
      closeFd()
      return
    }
    try {
      p.stop().then(() => {
        p.release().then(() => {
          hilog.info(DOMAIN, TAG, 'stopped and released')
          closeFd()
        }).catch((e: BusinessError) => {
          hilog.warn(DOMAIN, TAG, 'release failed: %{public}s', e.message)
          closeFd()
        })
      }).catch((e: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'stop failed: %{public}s', e.message)
        p.release().catch(() => {})
        closeFd()
      })
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'stop error: %{public}s', (e as Error).message)
      try {
        p.release().catch(() => {})
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'release error: %{public}s', (err as Error).message)
      }
      closeFd()
    }
  }
}
