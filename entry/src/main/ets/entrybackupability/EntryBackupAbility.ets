/*
 * EntryBackupAbility - 备份恢复
 * 用户卸载重装 app 后，系统会通过此 Ability 恢复 RDB 数据
 */
import { hilog } from '@kit.PerformanceAnalysisKit'
import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit'

const DOMAIN = 0x0000

export default class EntryBackupAbility extends BackupExtensionAbility {
  async onBackup() {
    hilog.info(DOMAIN, 'Backup', 'onBackup: 数据库即将备份')
    await Promise.resolve()
  }

  async onRestore(bundleVersion: BundleVersion) {
    hilog.info(DOMAIN, 'Backup', 'onRestore: 数据库恢复中, version=%{public}s', JSON.stringify(bundleVersion))
    await Promise.resolve()
  }
}
