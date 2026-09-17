/**
 * 认证相关 API
 * POST /auth/login · POST /auth/register · POST /auth/logout
 * GET /auth/me · PUT /auth/password
 *
 * 后端来源：backend-src/h_auth.cj · views.cj
 */
import { HttpClient, ApiResponse } from './HttpClient';

// ─── 后端返回的通用成员类型 ───

/** 部门简要（在 MemberBrief 中嵌套） */
export interface DeptBrief {
  id: number;
  name: string;
}

/** 成员简要 — backend-src/views.cj:memberBrief */
export interface MemberBrief {
  id: number;
  name: string;
  role: string | null;
  dept: DeptBrief | null;
  status: 'active' | 'pending' | 'disabled';
  joined_at: string | null;
}

/** 成员完整（本人可见手机号）— views.cj:memberSelf */
export interface MemberSelf extends MemberBrief {
  phone: string;
}

/** 权限信息 — views.cj:permissionView */
export interface UserPermissions {
  view_scope: 'none' | 'self' | 'dept' | 'all';
  manage_members: boolean;
  set_role: boolean;
  create_plan: boolean;
  create_task: boolean;
  update_any_task: boolean;
  // 管理页四张分区卡的显示开关（2026-09-16，D-1；仅用于画界面，不能替代服务端校验）
  manage_depts: boolean;         // 部门增删改 —— 仅会长
  view_register_code: boolean;   // 注册口令明文 —— 会长 / 副会长
  change_register_code: boolean; // 更换 / 轮换口令 —— 仅会长
  manage_invite_links: boolean;  // 招募链接增删启停 —— 会长 / 副会长
  transfer_presidency: boolean;  // 会长移交 —— 仅会长
}

// ─── 请求/响应类型 ───

export interface LoginRequest {
  phone: string;
  password: string;
}

export interface LoginResponse {
  token: string;
  member: MemberSelf;
  permissions: UserPermissions;
}

export interface RegisterRequest {
  register_code: string;
  phone: string;
  name: string;
  password: string;
  dept_id?: number;
}

export type RegisterResponse = LoginResponse;

export interface MeResponse {
  member: MemberSelf;
  permissions: UserPermissions;
}

export interface ChangePasswordRequest {
  old_password: string;
  new_password: string;
}

// ─── API 类 ───

export class AuthApi {
  private client: HttpClient;

  constructor() {
    this.client = HttpClient.getInstance();
  }

  /** POST /api/v1/auth/login */
  async login(data: LoginRequest): Promise<ApiResponse<LoginResponse>> {
    return this.client.post<LoginResponse>('/auth/login', data);
  }

  /** POST /api/v1/auth/register */
  async register(data: RegisterRequest): Promise<ApiResponse<RegisterResponse>> {
    return this.client.post<RegisterResponse>('/auth/register', data);
  }

  /** POST /api/v1/auth/logout */
  async logout(): Promise<ApiResponse<Record<string, never>>> {
    return this.client.post<Record<string, never>>('/auth/logout');
  }

  /** GET /api/v1/auth/me */
  async me(): Promise<ApiResponse<MeResponse>> {
    return this.client.get<MeResponse>('/auth/me');
  }

  /** PUT /api/v1/auth/password */
  async changePassword(data: ChangePasswordRequest): Promise<ApiResponse<Record<string, never>>> {
    return this.client.put<Record<string, never>>('/auth/password', data);
  }
}
