// 成员详情页面（B同学负责）
// 点击成员名录里的卡片跳转进来，按 memberId 展示对应成员
// 含：编辑姓名（PATCH /members/{id}）、重置密码、移出社团
// 权限规则：同权保护（canActOn）、自己不能重置自己、最后会长禁用移出
// 工程化：Theme token 化、bindContentCover 化、操作按钮按权限显隐

import type { MemberBrief, MemberSelf, UserPermissions } from '../api/AuthApi';
import { can, isLastPresident } from '../store/PermissionStore';
import { Color, StatusColor, Space, Radius, FontSize, statusLabel, statusFg, statusBg } from '../core/Theme';

// ─── 本地 interface（保留 upstream 原始结构，接 API 后改 import）───
interface Task {
  id: number;
  title: string;
  status: string;   // todo / doing / blocked / done
  dueAt: string;
}

interface MemberDetail {
  id: number;
  name: string;
  role: string;
  roleLabel: string;
  deptId: number;
  deptName: string;
  status: 'active' | 'pending' | 'disabled';
  joinedAt: string;
  phone: string;
  tasks: Task[];
}

// ─── 假数据（接 API 后删除）───
const ROLE_LABEL: Record<string, string> = {
  'president': '会长',
  'vice_president': '副会长',
  'lead': '部长',
  'vice_lead': '副部长',
  'member': '成员',
};

const MEMBER_DETAIL: MemberDetail = {
  id: 1,
  name: '王会长',
  role: 'president',
  roleLabel: '会长',
  deptId: 0,
  deptName: '主席团',
  status: 'active',
  joinedAt: '2026-09-01',
  phone: '138****0000',
  tasks: [
    { id: 101, title: '社团招新总体方案', status: 'doing', dueAt: '2026-09-20' },
    { id: 102, title: '与指导老师沟通', status: 'todo', dueAt: '2026-09-18' },
    { id: 103, title: '第一次全体大会', status: 'todo', dueAt: '2026-09-25' },
  ],
};

// 当前登录用户的 mock（接 API 后改为 PermissionStore.getInstance().userInfo）
const MOCK_CURRENT_USER: MemberSelf = {
  id: 2,
  name: '李副会长',
  role: 'vice_president',
  dept: { id: 0, name: '主席团' },
  status: 'active',
  joined_at: '2026-09-01',
  phone: '138****1111',
};

const MOCK_CURRENT_PERMISSIONS: UserPermissions = {
  view_scope: 'all',
  manage_members: true,
  set_role: true,
  create_plan: true,
  create_task: true,
  update_any_task: true,
};

// 全部成员的 mock（用于 isLastPresident 判断；接 API 后改为 MemberApi.list() 加载）
const MOCK_ALL_MEMBERS: MemberBrief[] = [
  { id: 1, name: '王会长', role: 'president', dept: { id: 0, name: '主席团' }, status: 'active', joined_at: '2026-09-01' },
  { id: 2, name: '李副会长', role: 'vice_president', dept: { id: 0, name: '主席团' }, status: 'active', joined_at: '2026-09-01' },
];

@Component
struct TaskRow {
  task: Task = { id: 0, title: '', status: 'todo', dueAt: '' };

  build() {
    Row() {
      Column() {
        Text(this.task.title)
          .fontSize(FontSize.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.textPrimary)

        Text(`截止 ${this.task.dueAt}`)
          .fontSize(FontSize.caption)
          .fontColor(Color.textTertiary)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(statusLabel(this.task.status))
        .fontSize(FontSize.caption)
        .fontColor(statusFg(this.task.status))
        .padding({ left: Space.xs * 2, right: Space.xs * 2, top: 2, bottom: 2 })
        .backgroundColor(statusBg(this.task.status))
        .borderRadius(Radius.pill)
    }
    .width('100%')
    .padding(Space.card)
    .backgroundColor(Color.surface)
    .margin({ bottom: 1 })
  }
}

@Component
export default struct MemberDetailPage {
  memberId: number = 0;
  @State member: MemberDetail = MEMBER_DETAIL;

  // 弹窗显隐状态
  @State showEditNameDialog: boolean = false;
  @State showResetPasswordDialog: boolean = false;
  @State showDisableDialog: boolean = false;
  // 编辑姓名输入值
  @State editingName: string = '';
  // 重置密码生成的临时密码（mock）
  @State tempPassword: string = '';

  // ─── 权限判断方法（用方法不用 getter，ArkTS 兼容）───
  // 把 @State member 转为 MemberBrief 给 canActOn / isLastPresident 用
  toBrief(): MemberBrief {
    return {
      id: this.member.id,
      name: this.member.name,
      role: this.member.role,
      dept: { id: this.member.deptId, name: this.member.deptName },
      status: this.member.status,
      joined_at: this.member.joinedAt,
    };
  }

  // 编辑姓名：需要 set_role 权限 + 同权保护
  canEditName(): boolean {
    if (!MOCK_CURRENT_PERMISSIONS.set_role) return false;
    return can(MOCK_CURRENT_USER, 'EditName', this.toBrief());
  }

  // 重置密码：需要 manage_members + 自己不能重置自己 + 同权保护
  canResetPassword(): boolean {
    if (this.member.id === MOCK_CURRENT_USER.id) return false;
    if (!MOCK_CURRENT_PERMISSIONS.manage_members) return false;
    return can(MOCK_CURRENT_USER, 'ResetPassword', this.toBrief());
  }

  // 移出社团：需要 manage_members + 自己不能移出自己 + 同权保护 + 最后会长保护
  canDisable(): boolean {
    if (this.member.id === MOCK_CURRENT_USER.id) return false;
    if (!MOCK_CURRENT_PERMISSIONS.manage_members) return false;
    if (!can(MOCK_CURRENT_USER, 'DisableMember', this.toBrief())) return false;
    if (isLastPresident(MOCK_ALL_MEMBERS, this.toBrief())) return false;
    return true;
  }

  // 弹窗显隐派生状态（重置密码弹窗有两种态：确认 / 结果）
  shouldShowResetConfirm(): boolean {
    return this.showResetPasswordDialog && this.tempPassword.length === 0;
  }
  shouldShowResetResult(): boolean {
    return this.showResetPasswordDialog && this.tempPassword.length > 0;
  }

  getAvatarColor(): string {
    switch (this.member.role) {
      case 'president': return StatusColor.overdue.fg;
      case 'vice_president': return StatusColor.blocked.fg;
      case 'lead': return Color.primary;
      case 'vice_lead': return StatusColor.done.fg;
      default: return StatusColor.pending.fg;
    }
  }

  // ─── 弹窗 Builder（用 bindContentCover 挂载为整窗模态浮层）───
  @Builder
  editNameDialogBuilder() {
    Column() {
      Column() {
        Text('编辑姓名')
          .fontSize(FontSize.title)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.textPrimary)
          .margin({ bottom: Space.lg })

        TextInput({ text: this.editingName, placeholder: '输入新姓名' })
          .fontSize(FontSize.body)
          .fontColor(Color.textPrimary)
          .backgroundColor(Color.canvas)
          .borderRadius(Radius.input)
          .padding({ left: Space.md, right: Space.md })
          .height(40)
          .width('100%')
          .margin({ bottom: Space.lg })
          .onChange((v: string) => { this.editingName = v; })

        Row() {
          Button('取消')
            .type(ButtonType.Normal)
            .backgroundColor(StatusColor.todo.bg)
            .fontColor(Color.textSecondary)
            .layoutWeight(1)
            .borderRadius(Radius.button)
            .onClick(() => {
              this.editingName = '';
              this.showEditNameDialog = false;
            })

          Button('保存')
            .type(ButtonType.Capsule)
            .backgroundColor(Color.primary)
            .fontColor(Color.onPrimary)
            .layoutWeight(1)
            .margin({ left: Space.md })
            .borderRadius(Radius.button)
            .onClick(() => {
              if (this.editingName.length === 0) return;
              // TODO: 接入 PATCH /members/{id} — MemberApi.update(this.memberId, { name: this.editingName })
              // mock：直接修改本地 state
              this.member = {
                id: this.member.id,
                name: this.editingName,
                role: this.member.role,
                roleLabel: this.member.roleLabel,
                deptId: this.member.deptId,
                deptName: this.member.deptName,
                status: this.member.status,
                joinedAt: this.member.joinedAt,
                phone: this.member.phone,
                tasks: this.member.tasks,
              };
              this.editingName = '';
              this.showEditNameDialog = false;
            })
        }
        .width('100%')
      }
      .width('85%')
      .padding(Space.xl)
      .backgroundColor(Color.surface)
      .borderRadius(Radius.card)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.overlay)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  resetPasswordConfirmBuilder() {
    Column() {
      Column() {
        Text('重置密码')
          .fontSize(FontSize.title)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.textPrimary)
          .margin({ bottom: Space.md })

        Text(`将为 ${this.member.name} 生成一次性临时密码，原密码立即失效。确认？`)
          .fontSize(FontSize.body)
          .fontColor(Color.textSecondary)
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ bottom: Space.lg })

        Row() {
          Button('取消')
            .type(ButtonType.Normal)
            .backgroundColor(StatusColor.todo.bg)
            .fontColor(Color.textSecondary)
            .layoutWeight(1)
            .borderRadius(Radius.button)
            .onClick(() => {
              this.showResetPasswordDialog = false;
            })

          Button('确认重置')
            .type(ButtonType.Capsule)
            .backgroundColor(StatusColor.blocked.bg)
            .fontColor(StatusColor.blocked.fg)
            .layoutWeight(1)
            .margin({ left: Space.md })
            .borderRadius(Radius.button)
            .onClick(() => {
              // mock：生成 8 位临时密码
              // TODO: 接入 POST /members/{id}/reset-password 后用后端返回的密码
              const chars: string = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
              let p: string = '';
              for (let i = 0; i < 8; i++) {
                p += chars.charAt(Math.floor(Math.random() * chars.length));
              }
              this.tempPassword = p;
            })
        }
        .width('100%')
      }
      .width('85%')
      .padding(Space.xl)
      .backgroundColor(Color.surface)
      .borderRadius(Radius.card)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.overlay)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  resetPasswordResultBuilder() {
    Column() {
      Column() {
        Text('重置成功')
          .fontSize(FontSize.title)
          .fontWeight(FontWeight.Bold)
          .fontColor(StatusColor.done.fg)
          .margin({ bottom: Space.md })

        Text(`${this.member.name} 的临时密码：`)
          .fontSize(FontSize.caption)
          .fontColor(Color.textTertiary)
          .margin({ bottom: Space.xs })

        Text(this.tempPassword)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(StatusColor.blocked.fg)
          .textAlign(TextAlign.Center)
          .width('100%')
          .padding({ top: Space.md, bottom: Space.md })
          .backgroundColor(Color.canvas)
          .borderRadius(Radius.input)
          .margin({ bottom: Space.md })

        Text('请立即告知成员，首次登录后会强制改密。')
          .fontSize(FontSize.caption)
          .fontColor(Color.textSecondary)
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ bottom: Space.lg })

        Button('知道了')
          .type(ButtonType.Capsule)
          .backgroundColor(StatusColor.done.bg)
          .fontColor(StatusColor.done.fg)
          .width('100%')
          .borderRadius(Radius.button)
          .onClick(() => {
            this.tempPassword = '';
            this.showResetPasswordDialog = false;
          })
      }
      .width('85%')
      .padding(Space.xl)
      .backgroundColor(Color.surface)
      .borderRadius(Radius.card)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.overlay)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  disableConfirmBuilder() {
    Column() {
      Column() {
        Text('移出社团')
          .fontSize(FontSize.title)
          .fontWeight(FontWeight.Bold)
          .fontColor(StatusColor.overdue.fg)
          .margin({ bottom: Space.md })

        Text(`将 ${this.member.name} 移出社团。若该成员仍有未完成任务，后端会拒绝。确认移出？`)
          .fontSize(FontSize.body)
          .fontColor(Color.textSecondary)
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ bottom: Space.lg })

        Row() {
          Button('取消')
            .type(ButtonType.Normal)
            .backgroundColor(StatusColor.todo.bg)
            .fontColor(Color.textSecondary)
            .layoutWeight(1)
            .borderRadius(Radius.button)
            .onClick(() => {
              this.showDisableDialog = false;
            })

          Button('确认移出')
            .type(ButtonType.Capsule)
            .backgroundColor(StatusColor.overdue.bg)
            .fontColor(StatusColor.overdue.fg)
            .layoutWeight(1)
            .margin({ left: Space.md })
            .borderRadius(Radius.button)
            .onClick(() => {
              // TODO: 接入 POST /members/{id}/disable
              // mock：关闭弹窗
              this.showDisableDialog = false;
            })
        }
        .width('100%')
      }
      .width('85%')
      .padding(Space.xl)
      .backgroundColor(Color.surface)
      .borderRadius(Radius.card)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.overlay)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Scroll() {
      Column() {
        // 顶部个人信息卡
        Column() {
          Text(this.member.name.substring(0, 1))
            .fontSize(36)
            .fontColor(Color.onPrimary)
            .width(72)
            .height(72)
            .borderRadius(36)
            .backgroundColor(this.getAvatarColor())
            .textAlign(TextAlign.Center)
            .margin({ bottom: Space.md })

          Text(this.member.name)
            .fontSize(FontSize.headline)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.textPrimary)

          Text(`${this.member.deptName} · ${this.member.roleLabel}`)
            .fontSize(FontSize.body)
            .fontColor(Color.textSecondary)
            .margin({ top: Space.xs })
        }
        .width('100%')
        .padding(Space.xl)
        .backgroundColor(Color.surface)
        .borderRadius(Radius.card)
        .margin({ left: Space.page, right: Space.page, top: Space.page })

        // 基本信息
        Column() {
          Text('基本信息')
            .fontSize(FontSize.caption)
            .fontColor(Color.textTertiary)
            .width('100%')
            .padding({ left: Space.lg, top: Space.md, bottom: Space.sm })

          Row() {
            Text('手机号')
              .fontSize(FontSize.body)
              .fontColor(Color.textSecondary)
              .width(80)
            Text(this.member.phone)
              .fontSize(FontSize.body)
              .fontColor(Color.textPrimary)
          }
          .width('100%')
          .padding({ left: Space.lg, right: Space.lg, top: Space.sm, bottom: Space.sm })

          Divider().color(Color.divider).margin({ left: Space.lg })

          Row() {
            Text('加入时间')
              .fontSize(FontSize.body)
              .fontColor(Color.textSecondary)
              .width(80)
            Text(this.member.joinedAt)
              .fontSize(FontSize.body)
              .fontColor(Color.textPrimary)
          }
          .width('100%')
          .padding({ left: Space.lg, right: Space.lg, top: Space.sm, bottom: Space.sm })

          Divider().color(Color.divider).margin({ left: Space.lg })

          Row() {
            Text('状态')
              .fontSize(FontSize.body)
              .fontColor(Color.textSecondary)
              .width(80)
            Text(this.member.status === 'active' ? '正常' : this.member.status)
              .fontSize(FontSize.body)
              .fontColor(this.member.status === 'active' ? StatusColor.done.fg : StatusColor.overdue.fg)
          }
          .width('100%')
          .padding({ left: Space.lg, right: Space.lg, top: Space.sm, bottom: Space.md })
        }
        .width('100%')
        .backgroundColor(Color.surface)
        .borderRadius(Radius.card)
        .margin({ left: Space.page, right: Space.page, top: Space.md })

        // 负责的任务
        Column() {
          Row() {
            Text('负责的任务')
              .fontSize(FontSize.caption)
              .fontColor(Color.textTertiary)

            Blank()

            Text(`${this.member.tasks.length} 项`)
              .fontSize(FontSize.caption)
              .fontColor(Color.textTertiary)
          }
          .width('100%')
          .padding({ left: Space.lg, right: Space.lg, top: Space.lg, bottom: Space.sm })

          Column() {
            ForEach(this.member.tasks, (task: Task) => {
              TaskRow({ task: task })
            }, (task: Task) => task.id.toString())

            if (this.member.tasks.length === 0) {
              Text('暂无任务')
                .fontSize(FontSize.body)
                .fontColor(Color.textTertiary)
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding(Space.xl)
            }
          }
        }
        .width('100%')
        .backgroundColor(Color.surface)
        .borderRadius(Radius.card)
        .margin({ left: Space.page, right: Space.page, top: Space.md })

        // 操作按钮区（权限驱动显隐）
        Column() {
          if (this.canEditName()) {
            Button('编辑姓名')
              .type(ButtonType.Normal)
              .backgroundColor(StatusColor.todo.bg)
              .fontColor(Color.textPrimary)
              .width('100%')
              .borderRadius(Radius.button)
              .margin({ bottom: Space.md })
              .onClick(() => {
                this.editingName = this.member.name;
                this.showEditNameDialog = true;
              })
          }

          if (this.canResetPassword()) {
            Button('重置密码')
              .type(ButtonType.Normal)
              .backgroundColor(StatusColor.blocked.bg)
              .fontColor(StatusColor.blocked.fg)
              .width('100%')
              .borderRadius(Radius.button)
              .margin({ bottom: Space.md })
              .onClick(() => {
                this.tempPassword = '';
                this.showResetPasswordDialog = true;
              })
          }

          if (this.canDisable()) {
            Button('移出社团')
              .type(ButtonType.Normal)
              .backgroundColor(StatusColor.overdue.bg)
              .fontColor(StatusColor.overdue.fg)
              .width('100%')
              .borderRadius(Radius.button)
              .onClick(() => {
                this.showDisableDialog = true;
              })
          }
        }
        .width('100%')
        .padding(Space.lg)
        .margin({ left: Space.page, right: Space.page, top: Space.xl, bottom: Space.page })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.canvas)
    .scrollBar(BarState.Off)
    .bindContentCover(this.showEditNameDialog, this.editNameDialogBuilder)
    .bindContentCover(this.shouldShowResetConfirm(), this.resetPasswordConfirmBuilder)
    .bindContentCover(this.shouldShowResetResult(), this.resetPasswordResultBuilder)
    .bindContentCover(this.showDisableDialog, this.disableConfirmBuilder)
  }
}
