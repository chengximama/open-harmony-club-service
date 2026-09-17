/**
 * 设计与视觉规范 —— Design Tokens 唯一同源
 * 对应《鸿蒙俱乐部-全场景UI设计规格》Design Tokens · Light Theme
 */

export interface ColorTokens {
  canvas: string;
  surface: string;
  primary: string;
  primarySoft: string;
  primaryBorder: string;
  onPrimary: string;
  onSurface: string;
  overlay: string;
  divider: string;
  textPrimary: string;
  textSecondary: string;
  textTertiary: string;
  textDisabled: string;
  danger: string;
  dangerBg: string;
  dangerBorder: string;
  inputBorder: string;
  sheetBg: string;
  blockedText: string;
}

export const Color: ColorTokens = {
  canvas: '#F5F6FA',
  surface: '#FFFFFF',
  primary: '#1F6FEB',
  primarySoft: '#E8F1FE',
  primaryBorder: '#BFDBFE',
  onPrimary: '#FFFFFF',
  onSurface: '#1B1F24',
  overlay: 'rgba(0,0,0,0.45)',
  divider: '#E6E9EE',
  textPrimary: '#1B1F24',
  textSecondary: '#5A6472',
  textTertiary: '#8A94A6',
  textDisabled: '#B0B7C3',
  danger: '#D93A2B',
  dangerBg: '#FDECEA',
  dangerBorder: '#F0CFC9',
  inputBorder: '#D6DBE3',
  sheetBg: '#FFFFFF',
  blockedText: '#8A5200',
}

export class AppColor {
  static readonly PAGE_BG: string = Color.canvas;
  static readonly CARD_BG: string = Color.surface;
  static readonly TEXT_PRIMARY: string = Color.textPrimary;
  static readonly TEXT_SECONDARY: string = Color.textSecondary;
  static readonly TEXT_TERTIARY: string = Color.textTertiary;
  static readonly TEXT_DISABLED: string = Color.textDisabled;
  static readonly DIVIDER: string = Color.divider;
  static readonly PRIMARY: string = Color.primary;
  static readonly PRIMARY_SOFT: string = Color.primarySoft;
  static readonly PRIMARY_BORDER: string = Color.primaryBorder;
  static readonly ON_PRIMARY: string = Color.onPrimary;
  static readonly DANGER: string = Color.danger;
  static readonly DANGER_BORDER: string = Color.dangerBorder;
  static readonly INPUT_BORDER: string = Color.inputBorder;
  static readonly OVERLAY: string = Color.overlay;
  static readonly SHEET_BG: string = Color.sheetBg;
  static readonly BLOCKED_TEXT: string = Color.blockedText;
}

export interface StatusColorPair {
  fg: string;
  bg: string;
}

export interface StatusColorTokens {
  todo: StatusColorPair;
  overdue: StatusColorPair;
  blocked: StatusColorPair;
  doing: StatusColorPair;
  done: StatusColorPair;
  pending: StatusColorPair;
}

export const StatusColor: StatusColorTokens = {
  todo: { fg: '#6B7785', bg: '#F0F2F5' },
  overdue: { fg: '#D93A2B', bg: '#FDECEA' },
  blocked: { fg: '#C77700', bg: '#FFF4E0' },
  doing: { fg: '#1F6FEB', bg: '#E8F1FE' },
  done: { fg: '#2E7D4F', bg: '#E8F5EC' },
  pending: { fg: '#7A5AF8', bg: '#F1EEFE' },
}

export class Tone {
  static readonly OVERDUE: string = StatusColor.overdue.fg;
  static readonly OVERDUE_BG: string = StatusColor.overdue.bg;
  static readonly BLOCKED: string = StatusColor.blocked.fg;
  static readonly BLOCKED_BG: string = StatusColor.blocked.bg;
  static readonly DOING: string = StatusColor.doing.fg;
  static readonly DOING_BG: string = StatusColor.doing.bg;
  static readonly TODO: string = StatusColor.todo.fg;
  static readonly TODO_BG: string = StatusColor.todo.bg;
  static readonly DONE: string = StatusColor.done.fg;
  static readonly DONE_BG: string = StatusColor.done.bg;
  static readonly PENDING: string = StatusColor.pending.fg;
  static readonly PENDING_BG: string = StatusColor.pending.bg;

  static fg(name: string): string {
    if (name === 'overdue') return StatusColor.overdue.fg;
    if (name === 'blocked') return StatusColor.blocked.fg;
    if (name === 'doing') return StatusColor.doing.fg;
    if (name === 'done') return StatusColor.done.fg;
    if (name === 'pending') return StatusColor.pending.fg;
    return StatusColor.todo.fg;
  }

  static bg(name: string): string {
    if (name === 'overdue') return StatusColor.overdue.bg;
    if (name === 'blocked') return StatusColor.blocked.bg;
    if (name === 'doing') return StatusColor.doing.bg;
    if (name === 'done') return StatusColor.done.bg;
    if (name === 'pending') return StatusColor.pending.bg;
    return StatusColor.todo.bg;
  }
}

export interface FontSizeTokens {
  headline: number;
  title: number;
  subtitle: number;
  body: number;
  caption: number;
  micro: number;
  navLabel: number;
  numL: number;
  numM: number;
}

export const FontSize: FontSizeTokens = {
  headline: 22,
  title: 18,
  subtitle: 16,
  body: 14,
  caption: 12,
  micro: 11,
  navLabel: 10,
  numL: 22,
  numM: 12,
}

export interface FontFamilyTokens {
  sans: string;
  numeric: string;
}

export const FontFamily: FontFamilyTokens = {
  sans: 'Noto Sans SC',
  numeric: 'Inter',
}

export interface SpaceTokens {
  xs: number;
  sm: number;
  md: number;
  lg: number;
  xl: number;
  xxl: number;
  page: number;
  card: number;
  cardGap: number;
  section: number;
  XS: number;
  S: number;
  M: number;
  L: number;
  XL: number;
  XXL: number;
}

export const Space: SpaceTokens = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 24,
  xxl: 32,
  page: 16,
  card: 14,
  cardGap: 12,
  section: 24,
  XS: 4,
  S: 8,
  M: 12,
  L: 16,
  XL: 24,
  XXL: 32,
}

export interface RadiusTokens {
  card: number;
  button: number;
  input: number;
  pill: number;
  bottomNav: number;
  navItem: number;
  sheet: number;
}

export const Radius: RadiusTokens = {
  card: 14,
  button: 12,
  input: 10,
  pill: 999,
  bottomNav: 36,
  navItem: 26,
  sheet: 20,
}

export interface ShadowValue {
  radius: number;
  color: string;
  offsetX: number;
  offsetY: number;
}

export interface ShadowTokens {
  card: ShadowValue;
  L1: ShadowValue;
  L2: ShadowValue;
  L3: ShadowValue;
  primary: ShadowValue;
  pending: ShadowValue;
}

export const Shadow: ShadowTokens = {
  card: { radius: 12, color: '#14000000', offsetX: 0, offsetY: 2 },
  L1: { radius: 2, color: '#0D101828', offsetX: 0, offsetY: 1 },
  L2: { radius: 16, color: '#1A101828', offsetX: 0, offsetY: 4 },
  L3: { radius: 40, color: '#2E101828', offsetX: 0, offsetY: 18 },
  primary: { radius: 20, color: '#3D1F6FEB', offsetX: 0, offsetY: 8 },
  pending: { radius: 24, color: '#3D7A5AF8', offsetX: 0, offsetY: 10 },
}

export function statusLabel(status: string): string {
  if (status === 'todo') return '未开始'
  if (status === 'doing') return '进行中'
  if (status === 'blocked') return '阻塞中'
  if (status === 'done') return '已完成'
  if (status === 'pending') return '待分配'
  return status
}

export function statusFg(status: string): string {
  if (status === 'todo') return StatusColor.todo.fg
  if (status === 'doing') return StatusColor.doing.fg
  if (status === 'blocked') return StatusColor.blocked.fg
  if (status === 'done') return StatusColor.done.fg
  if (status === 'pending') return StatusColor.pending.fg
  return Color.textTertiary
}

export function statusBg(status: string): string {
  if (status === 'todo') return StatusColor.todo.bg
  if (status === 'doing') return StatusColor.doing.bg
  if (status === 'blocked') return StatusColor.blocked.bg
  if (status === 'done') return StatusColor.done.bg
  if (status === 'pending') return StatusColor.pending.bg
  return StatusColor.todo.bg
}
