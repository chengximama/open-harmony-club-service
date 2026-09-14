// 对齐 frontend-brief.md §5 的数据结构
// 所有页面统一从这里 import，不要再自己写 interface

/** 部门简要信息（嵌套在 MemberBrief 里） */
export interface DeptBrief {
  id: number;
  name: string;
}

/** 成员简要信息 —— 对应后端 GET /members 返回 */
export interface MemberBrief {
  id: number;
  name: string;
  role: string;          // president / vice_president / lead / vice_lead / member（pending 时为 null）
  dept: DeptBrief | null; // pending 时为 null
  status: string;         // pending / active / disabled
  joined_at: string;      // ISO 8601
}

/** 成员详情 —— 对应后端 GET /members/{id} 返回 */
export interface MemberDetail {
  id: number;
  name: string;
  role: string;
  dept: DeptBrief | null;
  status: string;
  joined_at: string;
  // 注意：后端不含手机号（隐私最小化），这里暂不加 phone
}

/** 计划简要信息（TaskBrief.plan 引用） */
export interface PlanBrief {
  id: number;
  title: string;
}

/** 任务简要信息 —— 对应 backend TaskBrief（frontend-brief.md §5） */
export interface TaskBrief {
  id: number;
  title: string;
  status: string;                // todo / doing / blocked / done
  owner: MemberBrief | null;
  dept: DeptBrief | null;
  plan: PlanBrief | null;
  due_at: string | null;
  is_overdue: boolean;           // ⚠️ 服务端算好的，客户端不要自己算
  blocked: boolean;
  updated_at: string;
}

/** 部门 —— 对应后端 GET /depts（只有 id+name，memberCount 是 UI 衍生） */
export interface Dept {
  id: number;
  name: string;
}

// ====== 假数据（临时用，接真接口后删掉） ======

export const MOCK_DEPTS: Dept[] = [
  { id: 1, name: '主席团' },
  { id: 2, name: '课题部' },
  { id: 3, name: '运营部' },
  { id: 4, name: '宣传部' },
];

export const MOCK_MEMBERS: MemberBrief[] = [
  { id: 1, name: '王会长', role: 'president', dept: { id: 1, name: '主席团' }, status: 'active', joined_at: '2026-09-01' },
  { id: 2, name: '李副会长', role: 'vice_president', dept: { id: 1, name: '主席团' }, status: 'active', joined_at: '2026-09-01' },
  { id: 3, name: '张副会长', role: 'vice_president', dept: { id: 1, name: '主席团' }, status: 'active', joined_at: '2026-09-01' },
  { id: 4, name: '赵部长', role: 'lead', dept: { id: 2, name: '课题部' }, status: 'active', joined_at: '2026-09-02' },
  { id: 5, name: '孙副部长', role: 'vice_lead', dept: { id: 2, name: '课题部' }, status: 'active', joined_at: '2026-09-02' },
  { id: 6, name: '周小明', role: 'member', dept: { id: 2, name: '课题部' }, status: 'active', joined_at: '2026-09-03' },
  { id: 7, name: '吴小红', role: 'member', dept: { id: 2, name: '课题部' }, status: 'active', joined_at: '2026-09-03' },
  { id: 8, name: '郑部长', role: 'lead', dept: { id: 3, name: '运营部' }, status: 'active', joined_at: '2026-09-02' },
  { id: 9, name: '钱副部长', role: 'vice_lead', dept: { id: 3, name: '运营部' }, status: 'active', joined_at: '2026-09-02' },
  { id: 10, name: '冯小刚', role: 'member', dept: { id: 3, name: '运营部' }, status: 'active', joined_at: '2026-09-04' },
  { id: 11, name: '陈部长', role: 'lead', dept: { id: 4, name: '宣传部' }, status: 'active', joined_at: '2026-09-02' },
  { id: 12, name: '褚副部长', role: 'vice_lead', dept: { id: 4, name: '宣传部' }, status: 'active', joined_at: '2026-09-02' },
  { id: 13, name: '卫小美', role: 'member', dept: { id: 4, name: '宣传部' }, status: 'active', joined_at: '2026-09-05' },
];

// pending 成员就是 role=null, dept=null 的 MemberBrief（frontend-brief.md §5 明确说的）
export const MOCK_PENDING_MEMBERS: MemberBrief[] = [
  { id: 101, name: '新同学A', role: '', dept: null, status: 'pending', joined_at: '2026-09-14T10:30:00+08:00' },
  { id: 102, name: '新同学B', role: '', dept: null, status: 'pending', joined_at: '2026-09-14T11:00:00+08:00' },
  { id: 103, name: '新同学C', role: '', dept: null, status: 'pending', joined_at: '2026-09-14T14:20:00+08:00' },
  { id: 104, name: '新同学D', role: '', dept: null, status: 'pending', joined_at: '2026-09-14T15:45:00+08:00' },
  { id: 105, name: '新同学E', role: '', dept: null, status: 'pending', joined_at: '2026-09-14T16:10:00+08:00' },
];

export const ROLE_MAP: Record<string, string> = {
  'president': '会长',
  'vice_president': '副会长',
  'lead': '部长',
  'vice_lead': '副部长',
  'member': '成员',
};
