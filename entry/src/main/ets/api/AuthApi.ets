/**
 * 认证相关 API
 * POST /auth/login · POST /auth/register · POST /auth/logout
 * GET /auth/me · PUT /auth/password
 */
import { HttpClient, ApiResponse } from './HttpClient';

export interface DeptBrief {
  id: number;
  name: string;
}

export interface MemberBrief {
  id: number;
  name: string;
  role: string | null;
  dept: DeptBrief | null;
  status: 'active' | 'pending' | 'disabled';
  joined_at: string | null;
}

export interface MemberSelf extends MemberBrief {
  phone: string;
}

export interface UserPermissions {
  view_scope: 'none' | 'self' | 'dept' | 'all';
  manage_members: boolean;
  set_role: boolean;
  create_plan: boolean;
  create_task: boolean;
  update_any_task: boolean;
  manage_depts?: boolean;
  view_register_code?: boolean;
  change_register_code?: boolean;
  manage_invite_links?: boolean;
  transfer_presidency?: boolean;
}

export interface LoginRequest {
  phone: string;
  password: string;
}

export interface LoginResponse {
  token: string;
  expires_at: string;
  member: MemberSelf;
  permissions: UserPermissions;
  dept_hint: DeptBrief | null;
}

export interface RegisterRequest {
  register_code: string;
  phone: string;
  name: string;
  password: string;
  dept_id?: number;
  invite_token?: string;
  client_token: string;
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

export interface InvitePreview {
  dept: DeptBrief | null;
  enabled: boolean;
}

export class AuthApi {
  private client: HttpClient;

  constructor() {
    this.client = HttpClient.getInstance();
  }

  async login(data: LoginRequest): Promise<ApiResponse<LoginResponse>> {
    return this.client.post<LoginResponse>('/auth/login', data);
  }

  async register(data: RegisterRequest): Promise<ApiResponse<RegisterResponse>> {
    return this.client.post<RegisterResponse>('/auth/register', data);
  }

  async logout(): Promise<ApiResponse<Record<string, never>>> {
    return this.client.post<Record<string, never>>('/auth/logout');
  }

  async me(): Promise<ApiResponse<MeResponse>> {
    return this.client.get<MeResponse>('/auth/me');
  }

  async changePassword(data: ChangePasswordRequest): Promise<ApiResponse<Record<string, never>>> {
    return this.client.put<Record<string, never>>('/auth/password', data);
  }

  async previewInvite(token: string): Promise<ApiResponse<InvitePreview>> {
    return this.client.get<InvitePreview>(`/join/${token}`);
  }
}
