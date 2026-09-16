/**
 * 权限状态管理
 * 存储 /auth/me 返回的用户信息与权限
 * 附：ROLE_WEIGHT / canActOn / isLastPresident 业务规则函数
 *     供 B 同学负责的 MemberDetailPage / ManagePage 等做权限驱动 UI 显隐
 */
import type { MemberBrief, MemberSelf, UserPermissions } from '../api/AuthApi';

// update 方法的参数接口
export interface UpdateData {
  user: MemberSelf;
  permissions: UserPermissions;
}

// ─── 角色权重（数值越大权限越高；空串代表 pending 未分配）───
// 用于 canActOn 同权保护：高权可操作低权；同权互相不可操作。
export const ROLE_WEIGHT: Record<string, number> = {
  '': 0,
  'member': 1,
  'vice_lead': 2,
  'lead': 3,
  'vice_president': 4,
  'president': 5,
};

/**
 * 同权保护：current 是否可对 target 执行管理类操作（编辑姓名/重置密码/移出社团等）
 * 规则（与 frontend-brief.md §3 权限矩阵对齐）：
 *  1) 会长可对所有人操作；
 *  2) 副会长可对部长/副部长/普通成员操作，但不可作用于其他副会长或会长；
 *  3) 部长/副部长只能操作本部门内严格低于自己权重的成员；
 *  4) 同权（含 vice_lead 之间、vice_president 之间）互相不可操作；
 *  5) 普通成员对任何人都无管理权限。
 */
export function canActOn(current: MemberSelf, target: MemberBrief): boolean {
  if (current.role === 'president') return true;
  const myWeight: number = ROLE_WEIGHT[current.role ?? ''] ?? 0;
  const targetWeight: number = ROLE_WEIGHT[target.role ?? ''] ?? 0;
  if (targetWeight >= myWeight) return false;
  if (current.role === 'lead' || current.role === 'vice_lead') {
    if (current.dept === null || target.dept === null) return false;
    return current.dept.id === target.dept.id;
  }
  return true;
}

/**
 * 最后会长保护：若 target 是当前唯一的 active 会长，则禁止移出/禁用
 * 防止误操作把社团的最后一位会长清掉，导致权限体系失锁。
 */
export function isLastPresident(members: MemberBrief[], target: MemberBrief): boolean {
  if (target.role !== 'president') return false;
  if (target.status !== 'active') return false;
  const activePresidents: MemberBrief[] = members.filter((m: MemberBrief): boolean =>
    m.role === 'president' && m.status === 'active'
  );
  return activePresidents.length <= 1;
}

export class PermissionStore {
  private static instance: PermissionStore;

  userInfo: MemberSelf | null = null;
  permissions: UserPermissions | null = null;
  isLoggedIn: boolean = false;

  private constructor() {
    // 单例
  }

  static getInstance(): PermissionStore {
    if (!PermissionStore.instance) {
      PermissionStore.instance = new PermissionStore();
    }
    return PermissionStore.instance;
  }

  /** 保存登录后的用户信息与权限 */
  update(data: UpdateData): void {
    this.userInfo = data.user;
    this.permissions = data.permissions;
    this.isLoggedIn = true;
  }

  /** 清除用户信息（退出登录） */
  clear(): void {
    this.userInfo = null;
    this.permissions = null;
    this.isLoggedIn = false;
  }

  /** 是否为会长 */
  get isPresident(): boolean {
    return this.userInfo?.role === 'president';
  }

  /** 是否为副会长 */
  get isVicePresident(): boolean {
    return this.userInfo?.role === 'vice_president';
  }

  /** 是否为部长 */
  get isLead(): boolean {
    return this.userInfo?.role === 'lead';
  }

  /** 是否为副部长 */
  get isViceLead(): boolean {
    return this.userInfo?.role === 'vice_lead';
  }

  /** 是否为普通成员 */
  get isMember(): boolean {
    return this.userInfo?.role === 'member';
  }

  /** 是否为待分配成员 */
  get isPending(): boolean {
    return this.userInfo?.status === 'pending';
  }

  /** 是否为活跃成员 */
  get isActive(): boolean {
    return this.userInfo?.status === 'active';
  }
}
