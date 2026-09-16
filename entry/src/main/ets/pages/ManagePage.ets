// 管理页面（B同学负责）
// 包含：部门管理、注册口令、招募链接、危险操作（会长移交/重置密码）
// 权限规则：
//   - 部门 CRUD / 会长移交 / 重置密码 只对会长可见（副会长及以下不可见）
//   - 部门非空拦截：memberCount > 0 时禁止删除
// 工程化：Theme token 化、bindContentCover 化、注册口令"复制"对接 pasteboard

import type { MemberBrief, MemberSelf, UserPermissions } from '../api/AuthApi';
import { Color, StatusColor, Space, Radius, FontSize, Shadow } from '../core/Theme';
import { pasteboard } from '@kit.BasicServicesKit';

interface Dept {
  id: number;
  name: string;
  memberCount: number;   // UI 衍生数据（接 API 后由成员列表计算）
}

interface InviteLink {
  id: string;
  deptName: string;
  url: string;
  enabled: boolean;
  createdAt: string;
}

// 批量分配结果条目（用于重置密码后的展示，复用 PendingApprovalPage 的同名 interface）
interface MemberOption {
  id: number;
  name: string;
  deptName: string;
}

// ─── 假数据 ───
const DEPTS: Dept[] = [
  { id: 0, name: '主席团', memberCount: 3 },
  { id: 1, name: '课题部', memberCount: 4 },
  { id: 2, name: '运营部', memberCount: 3 },
  { id: 3, name: '宣传部', memberCount: 3 },
];

const INVITE_LINKS: InviteLink[] = [
  { id: 'link001', deptName: '课题部', url: 'club.example.com/join/abc123', enabled: true, createdAt: '2026-09-10' },
  { id: 'link002', deptName: '运营部', url: 'club.example.com/join/def456', enabled: true, createdAt: '2026-09-12' },
  { id: 'link003', deptName: '宣传部', url: 'club.example.com/join/ghi789', enabled: false, createdAt: '2026-09-08' },
];

const MEMBERS: MemberOption[] = [
  { id: 1, name: '王会长', deptName: '主席团' },
  { id: 2, name: '李副会长', deptName: '主席团' },
  { id: 4, name: '赵部长', deptName: '课题部' },
  { id: 5, name: '孙副部长', deptName: '课题部' },
];

// 当前登录用户的 mock（接 API 后改为 PermissionStore.getInstance().userInfo）
const MOCK_CURRENT_USER: MemberSelf = {
  id: 1,
  name: '王会长',
  role: 'president',
  dept: { id: 0, name: '主席团' },
  status: 'active',
  joined_at: '2026-09-01',
  phone: '138****0000',
};

const MOCK_CURRENT_PERMISSIONS: UserPermissions = {
  view_scope: 'all',
  manage_members: true,
  set_role: true,
  create_plan: true,
  create_task: true,
  update_any_task: true,
};

// 权限判断（按 project_memory：副会长不可见部门 CRUD/密码重置/会长移交）
function canManageDepts(): boolean {
  return MOCK_CURRENT_USER.role === 'president';
}

function canTransferPresidency(): boolean {
  return MOCK_CURRENT_USER.role === 'president';
}

function canResetMemberPassword(): boolean {
  if (!MOCK_CURRENT_PERMISSIONS.manage_members) return false;
  if (MOCK_CURRENT_USER.role === 'vice_president') return false;
  // 部长/副部长/普通成员没有 manage_members 权限，已被上一条拦掉
  return true;
}

@Component
struct SectionHeader {
  title: string = '';
  actionText: string = '';
  onAction: () => void = () => {};

  build() {
    Row() {
      Text(this.title)
        .fontSize(FontSize.subtitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.textPrimary)

      Blank()

      if (this.actionText.length > 0) {
        Text(this.actionText)
          .fontSize(FontSize.body)
          .fontColor(Color.primary)
          .onClick(() => { this.onAction(); })
      }
    }
    .width('100%')
    .padding({ left: Space.page, right: Space.page, top: Space.xl, bottom: Space.sm })
  }
}

// ====== 部门管理 ======
@Component
struct DeptManageSection {
  @State depts: Dept[] = DEPTS;
  // 弹窗状态
  @State showCreateDialog: boolean = false;
  @State showEditDialog: boolean = false;
  @State showDeleteConfirm: boolean = false;
  @State showDeleteBlocked: boolean = false;
  @State editingDeptId: number = 0;
  @State deletingDeptId: number = 0;
  @State deletingDeptName: string = '';
  @State deletingDeptCount: number = 0;
  // 输入值
  @State newDeptName: string = '';
  @State editDeptName: string = '';

  @Builder
  createDialogBuilder() {
    Column() {
      Column() {
        Text('新建部门')
          .fontSize(FontSize.title)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.textPrimary)
          .margin({ bottom: Space.lg })

        TextInput({ text: this.newDeptName, placeholder: '输入部门名称' })
          .fontSize(FontSize.body)
          .fontColor(Color.textPrimary)
          .backgroundColor(Color.canvas)
          .borderRadius(Radius.input)
          .padding({ left: Space.md, right: Space.md })
          .height(40)
          .width('100%')
          .margin({ bottom: Space.lg })
          .onChange((v: string) => { this.newDeptName = v; })

        Row() {
          Button('取消')
            .type(ButtonType.Normal)
            .backgroundColor(StatusColor.todo.bg)
            .fontColor(Color.textSecondary)
            .layoutWeight(1)
            .borderRadius(Radius.button)
            .onClick(() => {
              this.newDeptName = '';
              this.showCreateDialog = false;
            })

          Button('创建')
            .type(ButtonType.Capsule)
            .backgroundColor(Color.primary)
            .fontColor(Color.onPrimary)
            .layoutWeight(1)
            .margin({ left: Space.md })
            .borderRadius(Radius.button)
            .onClick(() => {
              if (this.newDeptName.length === 0) return;
              // TODO: 接入 DeptApi.create({ name: this.newDeptName })
              // mock：本地追加
              let maxId: number = 0;
              for (let i = 0; i < this.depts.length; i++) {
                if (this.depts[i].id > maxId) maxId = this.depts[i].id;
              }
              const nextId: number = maxId + 1;
              const newDept: Dept = { id: nextId, name: this.newDeptName, memberCount: 0 };
              this.depts = [...this.depts, newDept];
              this.newDeptName = '';
              this.showCreateDialog = false;
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
  editDialogBuilder() {
    Column() {
      Column() {
        Text('编辑部门名称')
          .fontSize(FontSize.title)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.textPrimary)
          .margin({ bottom: Space.lg })

        TextInput({ text: this.editDeptName, placeholder: '输入新名称' })
          .fontSize(FontSize.body)
          .fontColor(Color.textPrimary)
          .backgroundColor(Color.canvas)
          .borderRadius(Radius.input)
          .padding({ left: Space.md, right: Space.md })
          .height(40)
          .width('100%')
          .margin({ bottom: Space.lg })
          .onChange((v: string) => { this.editDeptName = v; })

        Row() {
          Button('取消')
            .type(ButtonType.Normal)
            .backgroundColor(StatusColor.todo.bg)
            .fontColor(Color.textSecondary)
            .layoutWeight(1)
            .borderRadius(Radius.button)
            .onClick(() => {
              this.editDeptName = '';
              this.showEditDialog = false;
            })

          Button('保存')
            .type(ButtonType.Capsule)
            .backgroundColor(Color.primary)
            .fontColor(Color.onPrimary)
            .layoutWeight(1)
            .margin({ left: Space.md })
            .borderRadius(Radius.button)
            .onClick(() => {
              if (this.editDeptName.length === 0) return;
              // TODO: 接入 DeptApi.update(this.editingDeptId, { name: this.editDeptName })
              const updated: Dept[] = [];
              for (let i = 0; i < this.depts.length; i++) {
                const d = this.depts[i];
                if (d.id === this.editingDeptId) {
                  updated.push({ id: d.id, name: this.editDeptName, memberCount: d.memberCount });
                } else {
                  updated.push(d);
                }
              }
              this.depts = updated;
              this.editDeptName = '';
              this.showEditDialog = false;
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
  deleteBlockedBuilder() {
    Column() {
      Column() {
        Text('无法删除')
          .fontSize(FontSize.title)
          .fontWeight(FontWeight.Bold)
          .fontColor(StatusColor.overdue.fg)
          .margin({ bottom: Space.md })

        Text(`部门「${this.deletingDeptName}」下还有 ${this.deletingDeptCount} 名成员，需先转移或移出成员后才能删除。`)
          .fontSize(FontSize.body)
          .fontColor(Color.textSecondary)
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ bottom: Space.lg })

        Button('知道了')
          .type(ButtonType.Capsule)
          .backgroundColor(Color.primary)
          .fontColor(Color.onPrimary)
          .width('100%')
          .borderRadius(Radius.button)
          .onClick(() => {
            this.showDeleteBlocked = false;
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
  deleteConfirmBuilder() {
    Column() {
      Column() {
        Text('删除部门')
          .fontSize(FontSize.title)
          .fontWeight(FontWeight.Bold)
          .fontColor(StatusColor.overdue.fg)
          .margin({ bottom: Space.md })

        Text(`确认删除部门「${this.deletingDeptName}」？删除后不可恢复。`)
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
              this.showDeleteConfirm = false;
            })

          Button('删除')
            .type(ButtonType.Capsule)
            .backgroundColor(StatusColor.overdue.bg)
            .fontColor(StatusColor.overdue.fg)
            .layoutWeight(1)
            .margin({ left: Space.md })
            .borderRadius(Radius.button)
            .onClick(() => {
              // TODO: 接入 DeptApi.delete(this.deletingDeptId)
              this.depts = this.depts.filter((d: Dept): boolean => d.id !== this.deletingDeptId);
              this.showDeleteConfirm = false;
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
    Column() {
      SectionHeader({
        title: '部门管理',
        actionText: canManageDepts() ? '+ 新建部门' : '',
        onAction: () => {
          this.newDeptName = '';
          this.showCreateDialog = true;
        }
      })

      Column() {
        ForEach(this.depts, (dept: Dept) => {
          Row() {
            Column() {
              Text(dept.name)
                .fontSize(FontSize.body)
                .fontWeight(FontWeight.Medium)
                .fontColor(Color.textPrimary)
              Text(`${dept.memberCount} 人`)
                .fontSize(FontSize.caption)
                .fontColor(Color.textTertiary)
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            if (canManageDepts()) {
              Text('编辑')
                .fontSize(FontSize.body)
                .fontColor(Color.primary)
                .margin({ right: Space.lg })
                .onClick(() => {
                  this.editingDeptId = dept.id;
                  this.editDeptName = dept.name;
                  this.showEditDialog = true;
                })

              Text('删除')
                .fontSize(FontSize.body)
                .fontColor(StatusColor.overdue.fg)
                .onClick(() => {
                  // 部门非空拦截：memberCount > 0 时弹拦截弹窗，否则弹确认删除
                  if (dept.memberCount > 0) {
                    this.deletingDeptId = dept.id;
                    this.deletingDeptName = dept.name;
                    this.deletingDeptCount = dept.memberCount;
                    this.showDeleteBlocked = true;
                  } else {
                    this.deletingDeptId = dept.id;
                    this.deletingDeptName = dept.name;
                    this.deletingDeptCount = 0;
                    this.showDeleteConfirm = true;
                  }
                })
            }
          }
          .width('100%')
          .padding(Space.card)
          .backgroundColor(Color.surface)
          .margin({ bottom: 1 })
        }, (dept: Dept) => dept.id.toString())
      }
      .backgroundColor(Color.surface)
      .borderRadius(Radius.card)
      .margin({ left: Space.page, right: Space.page })
    }
    .width('100%')
    .bindContentCover(this.showCreateDialog, this.createDialogBuilder)
    .bindContentCover(this.showEditDialog, this.editDialogBuilder)
    .bindContentCover(this.showDeleteBlocked, this.deleteBlockedBuilder)
    .bindContentCover(this.showDeleteConfirm, this.deleteConfirmBuilder)
  }
}

// ====== 注册口令 ======
@Component
struct RegisterConfigSection {
  @State code: string = 'CLUB-2026';
  @State showRotateConfirm: boolean = false;
  @State showChangeDialog: boolean = false;
  @State newCode: string = '';

  @Builder
  changeDialogBuilder() {
    Column() {
      Column() {
        Text('更换注册口令')
          .fontSize(FontSize.title)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.textPrimary)
          .margin({ bottom: Space.lg })

        TextInput({ text: this.newCode, placeholder: '输入新口令' })
          .fontSize(FontSize.body)
          .fontColor(Color.textPrimary)
          .backgroundColor(Color.canvas)
          .borderRadius(Radius.input)
          .padding({ left: Space.md, right: Space.md })
          .height(40)
          .width('100%')
          .margin({ bottom: Space.lg })
          .onChange((v: string) => { this.newCode = v; })

        Row() {
          Button('取消')
            .type(ButtonType.Normal)
            .backgroundColor(StatusColor.todo.bg)
            .fontColor(Color.textSecondary)
            .layoutWeight(1)
            .borderRadius(Radius.button)
            .onClick(() => {
              this.newCode = '';
              this.showChangeDialog = false;
            })

          Button('保存')
            .type(ButtonType.Capsule)
            .backgroundColor(Color.primary)
            .fontColor(Color.onPrimary)
            .layoutWeight(1)
            .margin({ left: Space.md })
            .borderRadius(Radius.button)
            .onClick(() => {
              if (this.newCode.length === 0) return;
              // TODO: 接入 MemberApi.setRegisterCode({ code: this.newCode })
              this.code = this.newCode;
              this.newCode = '';
              this.showChangeDialog = false;
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
  rotateDialogBuilder() {
    Column() {
      Column() {
        Text('随机轮换口令')
          .fontSize(FontSize.title)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.textPrimary)
          .margin({ bottom: Space.md })

        Text('将生成新的随机口令，旧口令立即失效。确认？')
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
              this.showRotateConfirm = false;
            })

          Button('确认轮换')
            .type(ButtonType.Capsule)
            .backgroundColor(Color.primary)
            .fontColor(Color.onPrimary)
            .layoutWeight(1)
            .margin({ left: Space.md })
            .borderRadius(Radius.button)
            .onClick(() => {
              // TODO: 接入 MemberApi.rotateRegisterCode()
              const chars: string = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
              let s: string = '';
              for (let i = 0; i < 6; i++) {
                s += chars.charAt(Math.floor(Math.random() * chars.length));
              }
              this.code = `CLUB-${s}`;
              this.showRotateConfirm = false;
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
    Column() {
      SectionHeader({ title: '注册口令', actionText: '' })

      Column() {
        Row() {
          Column() {
            Text('当前口令')
              .fontSize(FontSize.caption)
              .fontColor(Color.textTertiary)
            Text(this.code)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.primary)
              .margin({ top: Space.xs })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button('复制')
            .type(ButtonType.Capsule)
            .fontSize(FontSize.caption)
            .height(32)
            .backgroundColor(Color.primarySoft)
            .fontColor(Color.primary)
            .onClick(() => {
              // 对接剪贴板（@kit.BasicServicesKit pasteboard）
              // 官方 API：createData(MIMETYPE_TEXT_PLAIN, text) → setData(PasteData)
              const pasteData: pasteboard.PasteData = pasteboard.createData(
                pasteboard.MIMETYPE_TEXT_PLAIN,
                this.code
              );
              pasteboard.getSystemPasteboard().setData(pasteData)
                .then((): void => {
                  console.info('register code copied to clipboard');
                })
                .catch((e: Error): void => {
                  console.error(`copy to clipboard failed: ${e.message}`);
                });
            })
        }
        .width('100%')
        .padding(Space.lg)

        Divider()
          .color(Color.divider)

        if (canManageDepts()) {
          Row() {
            Button('更换口令')
              .layoutWeight(1)
              .backgroundColor(StatusColor.todo.bg)
              .fontColor(Color.textSecondary)
              .margin({ right: Space.sm })
              .borderRadius(Radius.button)
              .onClick(() => {
                this.newCode = '';
                this.showChangeDialog = true;
              })

            Button('随机轮换')
              .layoutWeight(1)
              .backgroundColor(Color.primary)
              .fontColor(Color.onPrimary)
              .borderRadius(Radius.button)
              .onClick(() => {
                this.showRotateConfirm = true;
              })
          }
          .width('100%')
          .padding({ left: Space.lg, right: Space.lg, top: Space.md, bottom: Space.lg })
        }
      }
      .backgroundColor(Color.surface)
      .borderRadius(Radius.card)
      .margin({ left: Space.page, right: Space.page })
    }
    .width('100%')
    .bindContentCover(this.showChangeDialog, this.changeDialogBuilder)
    .bindContentCover(this.showRotateConfirm, this.rotateDialogBuilder)
  }
}

// ====== 招募链接 ======
@Component
struct CreateLinkDialog {
  onConfirm: (deptIndex: number) => void = (_d: number) => {};
  onCancel: () => void = () => {};
  @State selectedDeptIndex: number = 0;

  build() {
    Column() {
      Column() {
        Text('生成招募链接')
          .fontSize(FontSize.title)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.textPrimary)
          .margin({ bottom: Space.lg })

        Text('选择部门')
          .fontSize(FontSize.body)
          .fontColor(Color.textSecondary)
          .width('100%')
          .margin({ bottom: Space.xs })

        Select(DEPTS.map((d: Dept): SelectOption => ({ value: d.name })))
          .selected(this.selectedDeptIndex)
          .value(DEPTS[this.selectedDeptIndex]?.name || DEPTS[0].name)
          .onSelect((index: number) => { this.selectedDeptIndex = index; })
          .width('100%')
          .margin({ bottom: Space.xl })

        Row() {
          Button('取消')
            .type(ButtonType.Normal)
            .backgroundColor(StatusColor.todo.bg)
            .fontColor(Color.textSecondary)
            .layoutWeight(1)
            .borderRadius(Radius.button)
            .onClick(() => { this.onCancel(); })

          Button('生成')
            .type(ButtonType.Normal)
            .backgroundColor(Color.primary)
            .fontColor(Color.onPrimary)
            .layoutWeight(1)
            .borderRadius(Radius.button)
            .margin({ left: Space.md })
            .onClick(() => { this.onConfirm(this.selectedDeptIndex); })
        }
        .width('100%')
      }
      .width('80%')
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
}

@Component
struct InviteLinkSection {
  @State links: InviteLink[] = INVITE_LINKS;
  @State showCreateDialog: boolean = false;

  toggleEnabled(id: string): void {
    const idx = this.links.findIndex((l: InviteLink): boolean => l.id === id);
    if (idx >= 0) {
      this.links[idx].enabled = !this.links[idx].enabled;
      this.links = [...this.links];
    }
  }

  @Builder
  createDialogBuilder() {
    CreateLinkDialog({
      onConfirm: (deptIndex: number): void => {
        const dept: Dept = DEPTS[deptIndex];
        // TODO: 接入 LinkApi.create({ dept_id: dept.id }) 后用后端返回的 url
        const chars: string = 'abcdefghijklmnopqrstuvwxyz0123456789';
        let token: string = '';
        for (let i = 0; i < 6; i++) {
          token += chars.charAt(Math.floor(Math.random() * chars.length));
        }
        const newLink: InviteLink = {
          id: `link${Date.now()}`,
          deptName: dept.name,
          url: `club.example.com/join/${token}`,
          enabled: true,
          createdAt: new Date().toISOString().slice(0, 10),
        };
        this.links = [...this.links, newLink];
        this.showCreateDialog = false;
      },
      onCancel: (): void => {
        this.showCreateDialog = false;
      }
    })
  }

  build() {
    Column() {
      SectionHeader({
        title: '招募链接',
        actionText: canManageDepts() ? '+ 生成链接' : '',
        onAction: () => {
          this.showCreateDialog = true;
        }
      })

      Column() {
        ForEach(this.links, (link: InviteLink) => {
          Column() {
            Row() {
              Text(link.deptName)
                .fontSize(FontSize.body)
                .fontWeight(FontWeight.Medium)
                .fontColor(Color.textPrimary)

              Blank()

              Text(link.enabled ? '启用中' : '已停用')
                .fontSize(FontSize.caption)
                .fontColor(link.enabled ? StatusColor.done.fg : Color.textTertiary)
                .padding({ left: Space.xs * 2, right: Space.xs * 2, top: 2, bottom: 2 })
                .backgroundColor(link.enabled ? StatusColor.done.bg : StatusColor.todo.bg)
                .borderRadius(Radius.pill)
            }
            .width('100%')

            Text(link.url)
              .fontSize(FontSize.caption)
              .fontColor(Color.primary)
              .margin({ top: Space.xs })

            Row() {
              Text(`创建于 ${link.createdAt}`)
                .fontSize(FontSize.caption)
                .fontColor(Color.textTertiary)

              Blank()

              if (canManageDepts()) {
                Text(link.enabled ? '停用' : '启用')
                  .fontSize(FontSize.caption)
                  .fontColor(link.enabled ? StatusColor.overdue.fg : StatusColor.done.fg)
                  .onClick(() => { this.toggleEnabled(link.id); })
              }
            }
            .width('100%')
            .margin({ top: Space.sm })
          }
          .width('100%')
          .padding(Space.card)
          .margin({ bottom: 1 })
        }, (link: InviteLink) => link.id)
      }
      .backgroundColor(Color.surface)
      .borderRadius(Radius.card)
      .margin({ left: Space.page, right: Space.page })
    }
    .width('100%')
    .bindContentCover(this.showCreateDialog, this.createDialogBuilder)
  }
}

// ====== 危险操作区（按权限显隐：副会长不可见部门 CRUD/密码重置/会长移交）======
@Component
struct DangerZoneSection {
  @State showTransferDialog: boolean = false;
  @State showResetDialog: boolean = false;
  @State showTransferResult: boolean = false;
  @State transferResultMsg: string = '';
  @State selectedTransferIndex: number = 0;

  @Builder
  transferDialogBuilder() {
    Column() {
      Column() {
        Text('移交会长')
          .fontSize(FontSize.title)
          .fontWeight(FontWeight.Bold)
          .fontColor(StatusColor.overdue.fg)
          .margin({ bottom: Space.sm })

        Text('将会长权限转让给以下成员，此操作不可撤销。')
          .fontSize(FontSize.caption)
          .fontColor(Color.textSecondary)
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ bottom: Space.lg })

        Text('选择新会长')
          .fontSize(FontSize.body)
          .fontColor(Color.textSecondary)
          .width('100%')
          .margin({ bottom: Space.xs })

        Select(MEMBERS.filter((m: MemberOption): boolean => m.id !== MOCK_CURRENT_USER.id)
          .map((m: MemberOption): SelectOption => ({ value: `${m.name}（${m.deptName}）` })))
          .selected(this.selectedTransferIndex)
          .value(MEMBERS.filter((m: MemberOption): boolean => m.id !== MOCK_CURRENT_USER.id)[this.selectedTransferIndex]?.name || '请选择')
          .onSelect((index: number) => { this.selectedTransferIndex = index; })
          .width('100%')
          .margin({ bottom: Space.xl })

        Row() {
          Button('取消')
            .type(ButtonType.Normal)
            .backgroundColor(StatusColor.todo.bg)
            .fontColor(Color.textSecondary)
            .layoutWeight(1)
            .borderRadius(Radius.button)
            .onClick(() => {
              this.showTransferDialog = false;
            })

          Button('确认移交')
            .type(ButtonType.Normal)
            .backgroundColor(StatusColor.overdue.bg)
            .fontColor(StatusColor.overdue.fg)
            .layoutWeight(1)
            .borderRadius(Radius.button)
            .margin({ left: Space.md })
            .onClick(() => {
              // TODO: 接入 MemberApi.transferPresidency(targetId)
              const candidates: MemberOption[] = MEMBERS.filter((m: MemberOption): boolean => m.id !== MOCK_CURRENT_USER.id);
              const target: MemberOption = candidates[this.selectedTransferIndex];
              if (target) {
                this.transferResultMsg = `已将会长权限移交至 ${target.name}（${target.deptName}）`;
                this.showTransferDialog = false;
                this.showTransferResult = true;
              }
            })
        }
        .width('100%')
      }
      .width('80%')
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
  transferResultBuilder() {
    Column() {
      Column() {
        Text('移交成功')
          .fontSize(FontSize.title)
          .fontWeight(FontWeight.Bold)
          .fontColor(StatusColor.done.fg)
          .margin({ bottom: Space.md })

        Text(this.transferResultMsg)
          .fontSize(FontSize.body)
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
            this.transferResultMsg = '';
            this.showTransferResult = false;
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
  resetDialogBuilder() {
    Column() {
      Column() {
        Text('重置成员密码')
          .fontSize(FontSize.title)
          .fontWeight(FontWeight.Bold)
          .fontColor(StatusColor.blocked.fg)
          .margin({ bottom: Space.sm })

        Text('为成员生成一次性临时密码，原密码立即失效。')
          .fontSize(FontSize.caption)
          .fontColor(Color.textSecondary)
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ bottom: Space.lg })

        Text('选择成员')
          .fontSize(FontSize.body)
          .fontColor(Color.textSecondary)
          .width('100%')
          .margin({ bottom: Space.xs })

        Select(MEMBERS.map((m: MemberOption): SelectOption => ({ value: `${m.name}（${m.deptName}）` })))
          .selected(0)
          .value(MEMBERS[0]?.name || '请选择')
          .width('100%')
          .margin({ bottom: Space.xl })

        Button('生成临时密码')
          .type(ButtonType.Capsule)
          .backgroundColor(StatusColor.blocked.bg)
          .fontColor(StatusColor.blocked.fg)
          .width('100%')
          .borderRadius(Radius.button)
          .onClick(() => {
            // mock：生成 8 位临时密码
            // TODO: 接入 POST /members/{id}/reset-password 后用后端返回的密码
            const chars: string = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
            let p: string = '';
            for (let i = 0; i < 8; i++) {
              p += chars.charAt(Math.floor(Math.random() * chars.length));
            }
            console.info(`mock temp password: ${p}`);
            this.showResetDialog = false;
          })
      }
      .width('80%')
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
    // 危险操作区只对有相应权限的角色可见
    // 会长移交：只会长可见
    // 重置密码：会长可见，副会长不可见（project_memory 约束）
    if (canTransferPresidency() || canResetMemberPassword()) {
      Column() {
        SectionHeader({ title: '危险操作', actionText: '' })

        Column() {
          if (canTransferPresidency()) {
            Row() {
              Column() {
                Text('移交会长')
                  .fontSize(FontSize.body)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Color.textPrimary)
                Text('将会长权限转让给另一位成员')
                  .fontSize(FontSize.caption)
                  .fontColor(Color.textTertiary)
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text('>')
                .fontSize(FontSize.title)
                .fontColor(Color.textTertiary)
            }
            .width('100%')
            .padding(Space.card)
            .onClick(() => {
              this.showTransferDialog = true;
            })

            Divider().color(Color.divider).margin({ left: Space.lg })
          }

          if (canResetMemberPassword()) {
            Row() {
              Column() {
                Text('重置成员密码')
                  .fontSize(FontSize.body)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Color.textPrimary)
                Text('为成员生成一次性临时密码')
                  .fontSize(FontSize.caption)
                  .fontColor(Color.textTertiary)
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text('>')
                .fontSize(FontSize.title)
                .fontColor(Color.textTertiary)
            }
            .width('100%')
            .padding(Space.card)
            .onClick(() => {
              this.showResetDialog = true;
            })
          }
        }
        .backgroundColor(Color.surface)
        .borderRadius(Radius.card)
        .margin({ left: Space.page, right: Space.page })
      }
      .width('100%')
      .bindContentCover(this.showTransferDialog, this.transferDialogBuilder)
      .bindContentCover(this.showTransferResult, this.transferResultBuilder)
      .bindContentCover(this.showResetDialog, this.resetDialogBuilder)
    }
  }
}

@Entry
@Component
export default struct ManagePage {
  @State currentTab: number = 0;

  build() {
    Column() {
      Tabs({ barPosition: BarPosition.Start }) {
        TabContent() {
          Scroll() {
            Column() {
              DeptManageSection()
              RegisterConfigSection()
              InviteLinkSection()
              DangerZoneSection()
            }
          }
          .scrollBar(BarState.Off)
        }
        .tabBar('综合管理')

        TabContent() {
          Column() {
            Text('部门管理（独立页）')
              .fontSize(FontSize.subtitle)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.textPrimary)
              .margin({ top: Space.xl })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }
        .tabBar('部门')

        TabContent() {
          Column() {
            Text('成员管理（独立页）')
              .fontSize(FontSize.subtitle)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.textPrimary)
              .margin({ top: Space.xl })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }
        .tabBar('成员')
      }
      .onChange((index: number) => {
        this.currentTab = index;
      })
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.canvas)
  }
}
