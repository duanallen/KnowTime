/*
 * Theme - 知时设计系统
 * 设计语言：轻量 · 呼吸感
 * 支持深色模式：AppColors 各 token 为 static getter，读取当前调色板（light/dark）
 */

/** 调色板结构：key 与 AppColors token 一一对应 */
interface Palette {
  primary: string
  focusActive: string
  rest: string
  bgPrimary: string
  bgCard: string
  textPrimary: string
  textSecondary: string
  textHint: string
  border: string
  divider: string
  heat0: string
  heat1: string
  heat2: string
  heat3: string
  heat4: string
  success: string
  warning: string
  error: string
  onAccent: string
  muted: string
  textBody: string
  textSubtle: string
  accentBlue: string
  restBg: string
  warningBg: string
  remindRed: string
  mask: string
  maskStrong: string
  cardShadow: string
  primaryShadow: string
  tabShadow: string
}

/** 浅色调色板 */
const LIGHT_COLORS: Palette = {
  primary: '#1A73E8',
  focusActive: '#0D9488',
  rest: '#F59E0B',
  bgPrimary: '#F8FAFC',
  bgCard: '#FFFFFF',
  textPrimary: '#1E293B',
  textSecondary: '#64748B',
  textHint: '#94A3B8',
  border: '#E2E8F0',
  divider: '#F1F5F9',
  heat0: '#EEF2F7',
  heat1: '#DBEAFE',
  heat2: '#93C5FD',
  heat3: '#3B82F6',
  heat4: '#1A73E8',
  success: '#10B981',
  warning: '#F59E0B',
  error: '#EF4444',
  onAccent: '#FFFFFF',
  muted: '#CBD5E1',
  textBody: '#334155',
  textSubtle: '#475569',
  accentBlue: '#3B82F6',
  restBg: '#FFFBEB',
  warningBg: '#FEF3C7',
  remindRed: '#FF5252',
  mask: '#00000050',
  maskStrong: '#00000080',
  cardShadow: '#00000020',
  primaryShadow: '#1A73E830',
  tabShadow: '#0F172A10'
}

/** 深色调色板 */
const DARK_COLORS: Palette = {
  primary: '#1A73E8',
  focusActive: '#0D9488',
  rest: '#F59E0B',
  bgPrimary: '#0F172A',
  bgCard: '#1E293B',
  textPrimary: '#F1F5F9',
  textSecondary: '#94A3B8',
  textHint: '#64748B',
  border: '#334155',
  divider: '#243349',
  heat0: '#243349',
  heat1: '#1E3A5F',
  heat2: '#1D4ED8',
  heat3: '#2563EB',
  heat4: '#60A5FA',
  success: '#10B981',
  warning: '#F59E0B',
  error: '#EF4444',
  onAccent: '#FFFFFF',
  muted: '#475569',
  textBody: '#CBD5E1',
  textSubtle: '#94A3B8',
  accentBlue: '#60A5FA',
  restBg: '#3F3110',
  warningBg: '#3F3110',
  remindRed: '#FF6B6B',
  mask: '#00000099',
  maskStrong: '#000000B3',
  cardShadow: '#00000066',
  primaryShadow: '#1A73E84D',
  tabShadow: '#00000066'
}

export class AppColors {
  private static dark: boolean = false

  private static get palette(): Palette {
    return AppColors.dark ? DARK_COLORS : LIGHT_COLORS
  }

  /** 切换深浅色调色板，并写入 AppStorage 触发 @StorageLink 页面重建 */
  static setDarkMode(dark: boolean): void {
    AppColors.dark = dark
    AppStorage.setOrCreate('isDarkMode', dark)
  }

  static isDark(): boolean {
    return AppColors.dark
  }

  static get PRIMARY(): string { return AppColors.palette.primary }
  static get FOCUS_ACTIVE(): string { return AppColors.palette.focusActive }
  static get REST(): string { return AppColors.palette.rest }
  static get BG_PRIMARY(): string { return AppColors.palette.bgPrimary }
  static get BG_CARD(): string { return AppColors.palette.bgCard }
  static get TEXT_PRIMARY(): string { return AppColors.palette.textPrimary }
  static get TEXT_SECONDARY(): string { return AppColors.palette.textSecondary }
  static get TEXT_HINT(): string { return AppColors.palette.textHint }
  static get BORDER(): string { return AppColors.palette.border }
  static get DIVIDER(): string { return AppColors.palette.divider }
  /** 热力图 0 级（无专注） */
  static get HEAT_0(): string { return AppColors.palette.heat0 }
  /** 热力图 1 级（1-29 分钟） */
  static get HEAT_1(): string { return AppColors.palette.heat1 }
  /** 热力图 2 级（30-59 分钟） */
  static get HEAT_2(): string { return AppColors.palette.heat2 }
  /** 热力图 3 级（60-119 分钟） */
  static get HEAT_3(): string { return AppColors.palette.heat3 }
  /** 热力图 4 级（≥120 分钟） */
  static get HEAT_4(): string { return AppColors.palette.heat4 }
  static get SUCCESS(): string { return AppColors.palette.success }
  static get WARNING(): string { return AppColors.palette.warning }
  static get ERROR(): string { return AppColors.palette.error }
  /** 彩色背景上的文字/图标色（两种模式均为白色） */
  static get ON_ACCENT(): string { return AppColors.palette.onAccent }
  /** 占位符、箭头、未选中图标等弱化色 */
  static get MUTED(): string { return AppColors.palette.muted }
  /** 介于主文本与次文本之间的正文色 */
  static get TEXT_BODY(): string { return AppColors.palette.textBody }
  /** 图表标注、勋章标题等弱正文色 */
  static get TEXT_SUBTLE(): string { return AppColors.palette.textSubtle }
  /** 图表强调蓝、对话框操作蓝 */
  static get ACCENT_BLUE(): string { return AppColors.palette.accentBlue }
  /** 暂停按钮浅琥珀底色 */
  static get REST_BG(): string { return AppColors.palette.restBg }
  /** 连续天数徽章浅黄底色 */
  static get WARNING_BG(): string { return AppColors.palette.warningBg }
  /** 提醒/停止按钮红色 */
  static get REMIND_RED(): string { return AppColors.palette.remindRed }
  /** 弹窗半透明遮罩 */
  static get MASK(): string { return AppColors.palette.mask }
  /** 全屏强遮罩 */
  static get MASK_STRONG(): string { return AppColors.palette.maskStrong }
  /** 卡片/弹窗阴影 */
  static get CARD_SHADOW(): string { return AppColors.palette.cardShadow }
  /** 主按钮阴影 */
  static get PRIMARY_SHADOW(): string { return AppColors.palette.primaryShadow }
  /** 底部 Tab 栏阴影 */
  static get TAB_SHADOW(): string { return AppColors.palette.tabShadow }
}

export class AppFontSizes {
  static readonly TITLE_LARGE: number = 28
  static readonly TITLE_MEDIUM: number = 22
  static readonly TITLE_SMALL: number = 18
  static readonly BODY: number = 16
  static readonly CAPTION: number = 14
  static readonly SMALL: number = 12
}
