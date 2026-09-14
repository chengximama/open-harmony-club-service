// 设计与视觉规范 Token · Light Theme
// 对齐 frontend-brief.md + UI 设计稿
// 一处定义，全页复用，不要硬编码值

/** 品牌与中性色 */
export interface ColorsToken {
  canvas: string;
  surface: string;
  primary: string;
  primarySoft: string;
  divider: string;
  textPrimary: string;
  textSecondary: string;
  textTertiary: string;
}
export const Colors: ColorsToken = {
  canvas: '#F5F7FA',
  surface: '#FFFFFF',
  primary: '#7CB8E8',
  primarySoft: '#EAF3FC',
  divider: '#ECEFF3',
  textPrimary: '#333333',
  textSecondary: '#666666',
  textTertiary: '#999999',
};

/** 状态语义色项（前景色 + 浅底） */
export interface StatusColorPair {
  fg: string;
  bg: string;
}
export interface StatusColorsToken {
  overdue: StatusColorPair;
  blocked: StatusColorPair;
  doing: StatusColorPair;
  todo: StatusColorPair;
  done: StatusColorPair;
  pending: StatusColorPair;
}
export const StatusColors: StatusColorsToken = {
  overdue: { fg: '#E88B9D', bg: '#FDF0F3' },
  blocked: { fg: '#D4B896', bg: '#FBF6EF' },
  doing:   { fg: '#7CB8E8', bg: '#EAF3FC' },
  todo:    { fg: '#B8C0CC', bg: '#F2F4F7' },
  done:    { fg: '#8EC9A0', bg: '#EDF6F0' },
  pending: { fg: '#B8A8D8', bg: '#F5F2FA' },
};

/** 圆角 */
export interface RadiusToken {
  card: number;
  button: number;
  input: number;
  capsule: number;
  bottomNav: number;
}
export const Radius: RadiusToken = {
  card: 14,
  button: 12,
  input: 10,
  capsule: 999,
  bottomNav: 36,
};

/** 间距（基准 4，档位 8/12/16/24/32） */
export interface SpacingToken {
  page: number;
  cardInner: number;
  cardGap: number;
  sectionGap: number;
  xs: number;
  sm: number;
  md: number;
  lg: number;
  xl: number;
  xxl: number;
}
export const Spacing: SpacingToken = {
  page: 16,
  cardInner: 14,
  cardGap: 12,
  sectionGap: 24,
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 24,
  xxl: 32,
};

/** 阴影 */
export interface ShadowToken {
  radius: number;
  color: string;
  offsetY: number;
}
export interface ShadowsToken {
  card: ShadowToken;
}
export const Shadows: ShadowsToken = {
  card: { radius: 8, color: '#1A000000', offsetY: 2 },
};