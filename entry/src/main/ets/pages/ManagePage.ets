// 管理页面（B同学负责）
// 包含：部门管理、注册口令、招募链接、危险操作（会长移交/重置密码）
// 权限规则：
//   - 部门 CRUD / 会长移交 / 重置密码 只对会长可见（副会长及以下不可见）
//   - 部门非空拦截：memberCount > 0 时禁止删除
// 工程化：Theme token 化、bindContentCover 化、注册口令"复制"对接 pasteboard
// 已接真接口：DeptApi / MemberApi（注册口令、招募链接、会长移交、重置密码），权限读 PermissionStore

import type { MemberBrief } from '../api/AuthApi';
import { MemberApi } from '../api/MemberApi';
import { DeptApi, DeptView, InviteLinkView } from '../api/DeptApi';
import { PermissionStore } from '../store/PermissionStore';
import { Color, StatusColor, Space, Radius, FontSize } from '../core/Theme';
import { pasteboard } from '@kit.BasicServicesKit';

interface Dept {
  id: number;
  name: string;
  sort: number;
  memberCount: number;   // UI 衍生数据，来自 DeptView.member_count
}

interface InviteLink {
  id: string;            // 即后端 token
  deptName: string;
  url: string;
  enabled: boolean;
  createdAt: string;
}

interface MemberOption {
  id: number;
  name: string;
  deptName: string;
}

// ─── 类型映射（后端视图 → 页面本地 UI 类型）───

function deptViewToDept(d: DeptView): Dept {
  return { id: d.id, name: d.name, sort: d.sort, memberCount: d.member_count };
}

function linkViewToInviteLink(l: InviteLinkView): InviteLink {
  const created: string = l.created_at ?? '';
  return {
    id: l.token,
    deptName: l.dept.name,
    url: l.url,
    enabled: l.enabled,
    createdAt: created.length >= 10 ? created.slice(0, 10) : created,
  };
}

function memberToMemberOption(m: MemberBrief): MemberOption {
  return { id: m.id, name: m.name, deptName: m.dept !== null ? m.dept.name : '未分配' };
}

// 复制文本到剪贴板
function copyText(text: string): void {
  const pasteData: pasteboard.PasteData = pasteboard.createData(
    pasteboard.MIMETYPE_TEXT_PLAIN,
    text
  );
  pasteboard.getSystemPasteboard().setData(pasteData)
    .then((): void => {
      console.info('copied to clipboard');
    })
    .catch((e: Error): void => {
      console.error(`copy to clipboard failed: ${e.message}`);
    });
}

// 当前登录用户 id（未登录时为 -1，仅用于过滤"自己"）
function currentUserId(): number {
  const u = PermissionStore.getInstance().userInfo;
  return u !== null ? u.id : -1;
}

// 权限判断：读 PermissionStore 里 /auth/me 下发的 permissions 布尔（D-1，2026-09-16）。
// 仅用于画界面显隐，绝不能用它替代服务端校验。
function canManageDepts(): boolean {
  return PermissionStore.getInstance().permissions?.manage_depts ?? false;
}

function canViewRegisterCode(): boolean {
  return PermissionStore.getInstance().permissions?.view_register_code ?? false;
}

function canChangeRegisterCode(): boolean {
  return PermissionStore.getInstance().permissions?.change_register_code ?? false;
}

function canManageInviteLinks(): boolean {
  return PermissionStore.getInstance().permissions?.manage_invite_links ?? false;
}

function canTransferPresidency(): boolean {
  return PermissionStore.getInstance().permissions?.transfer_presidency ?? false;
}

// 重置密码：会长 / 副会长可用（manage_members）；部长 / 副部长限本部门，走成员详情页，不在本页展示
function canResetMemberPassword(): boolean {
  return PermissionStore.getInstance().permissions?.manage_members ?? false;
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
  @State depts: Dept[] = [];
  @State loading: boolean = true;
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
  @State showSortDialog: boolean = false;
  @State sortingDeptId: number = 0;
  @State sortingDeptName: string = '';
  @State sortValue: string = '';
  private deptApi: DeptApi = new DeptApi();

  aboutToAppear(): void {
    this.loadDepts();
  }

  async loadDepts(): Promise<void> {
    this.loading = true;
    const resp = await this.deptApi.list();
    if (resp.ok && resp.data) {
      this.depts = resp.data.items.map((d: DeptView): Dept => deptViewToDept(d));
    }
    this.loading = false;
  }

  async submitCreate(): Promise<void> {
    if (this.newDeptName.length === 0) return;
    const resp = await this.deptApi.create({ name: this.newDeptName });
    if (resp.ok && resp.data) {
      this.depts = [...this.depts, deptViewToDept(resp.data)];
      this.newDeptName = '';
      this.showCreateDialog = false;
    } else {
      AlertDialog.show({
        title: '创建失败',
        message: resp.error?.message ?? '请重试',
        primaryButton: { value: '知道了', action: () => {} }
      });
    }
  }

  async submitEdit(): Promise<void> {
    if (this.editDeptName.length === 0) return;
    const resp = await this.deptApi.update(this.editingDeptId, { name: this.editDeptName });
    if (resp.ok && resp.data) {
      const updated: DeptView = resp.data;
      const next: Dept[] = [];
      for (let i = 0; i < this.depts.length; i++) {
        if (this.depts[i].id === updated.id) {
          next.push(deptViewToDept(updated));
        } else {
          next.push(this.depts[i]);
        }
      }
      this.depts = next;
      this.editDeptName = '';
      this.showEditDialog = false;
    } else {
      AlertDialog.show({
        title: '保存失败',
        message: resp.error?.message ?? '请重试',
        primaryButton: { value: '知道了', action: () => {} }
      });
    }
  }

  async submitDelete(): Promise<void> {
    const resp = await this.deptApi.delete_(this.deletingDeptId);
    if (resp.ok) {
      this.depts = this.depts.filter((d: Dept): boolean => d.id !== this.deletingDeptId);
      this.showDeleteConfirm = false;
    } else {
      this.showDeleteConfirm = false;
      AlertDialog.show({
        title: '删除失败',
        message: resp.error?.message ?? '请重试',
        primaryButton: { value: '知道了', action: () => {} }
      });
    }
  }


  private openSortDialog(dept: Dept): void {
    this.sortingDeptId = dept.id;
    this.sortingDeptName = dept.name;
    this.sortValue = dept.sort.toString();
    this.showSortDialog = true;
  }

  async submitSort(): Promise<void> {
    const value: number = Number(this.sortValue.trim());
    if (this.sortValue.trim().length === 0 || Number.isNaN(value)) {
      AlertDialog.show({
        title: '排序值无效',
        message: '请输入整数排序值。',
        primaryButton: { value: '知道了', action: () => {} }
      });
      return;
    }
    const resp = await this.deptApi.update(this.sortingDeptId, { sort: value });
    if (resp.ok && resp.data) {
      const updated: DeptView = resp.data;
      const next: Dept[] = [];
      for (let i = 0; i < this.depts.length; i++) {
        if (this.depts[i].id === updated.id) {
          next.push(deptViewToDept(updated));
        } else {
          next.push(this.depts[i]);
        }
      }
      next.sort((a: Dept, b: Dept): number => a.sort - b.sort);
      this.depts = next;
      this.showSortDialog = false;
    } else {
      AlertDialog.show({
        title: '排序失败',
        message: resp.error?.message ?? '请重试',
        primaryButton: { value: '知道了', action: () => {} }
      });
    }
  }

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
            .onClick(() => { this.submitCreate(); })
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
            .onClick(() => { this.submitEdit(); })
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
  sortDialogBuilder() {
    Column() {
      Column() {
        Text('调整部门排序')
          .fontSize(FontSize.title)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.textPrimary)
          .margin({ bottom: Space.xs })

        Text(`部门：${this.sortingDeptName}`)
          .width('100%')
          .fontSize(FontSize.caption)
          .fontColor(Color.textTertiary)
          .margin({ bottom: Space.lg })

        TextInput({ text: this.sortValue, placeholder: '输入排序值' })
          .fontSize(FontSize.body)
          .fontColor(Color.textPrimary)
          .backgroundColor(Color.canvas)
          .borderRadius(Radius.input)
          .padding({ left: Space.md, right: Space.md })
          .height(40)
          .width('100%')
          .margin({ bottom: Space.lg })
          .onChange((v: string) => { this.sortValue = v; })

        Row() {
          Button('取消')
            .type(ButtonType.Normal)
            .backgroundColor(StatusColor.todo.bg)
            .fontColor(Color.textSecondary)
            .layoutWeight(1)
            .borderRadius(Radius.button)
            .onClick(() => {
              this.showSortDialog = false;
            })

          Button('保存排序')
            .type(ButtonType.Capsule)
            .backgroundColor(Color.primary)
            .fontColor(Color.onPrimary)
            .layoutWeight(1)
            .margin({ left: Space.md })
            .borderRadius(Radius.button)
            .onClick(() => { this.submitSort(); })
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
            .onClick(() => { this.submitDelete(); })
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
  deptDialogBuilder() {
    if (this.showCreateDialog) {
      this.createDialogBuilder()
    } else if (this.showEditDialog) {
      this.editDialogBuilder()
    } else if (this.showSortDialog) {
      this.sortDialogBuilder()
    } else if (this.showDeleteBlocked) {
      this.deleteBlockedBuilder()
    } else if (this.showDeleteConfirm) {
      this.deleteConfirmBuilder()
    }
  }

  build() {
    Column() {
      Row() {
        Column({ space: 2 }) {
          Text('部门与组织')
            .fontSize(FontSize.body)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.textPrimary)

          Text('增删改仅会长；删除非空部门会被拒绝（DEPT_NOT_EMPTY）')
            .fontSize(FontSize.micro)
            .fontColor(Color.textTertiary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (canManageDepts()) {
          Text('+ 新建')
            .fontSize(FontSize.caption)
            .fontColor(Color.primary)
            .onClick(() => {
              this.newDeptName = '';
              this.showCreateDialog = true;
            })
        }
      }
      .width('100%')

      if (this.loading) {
        Row() {
          LoadingProgress().width(24).height(24).color(Color.primary)
        }
        .width('100%')
        .height(64)
        .justifyContent(FlexAlign.Center)
      } else if (this.depts.length === 0) {
        Text('暂无部门')
          .width('100%')
          .fontSize(FontSize.caption)
          .fontColor(Color.textTertiary)
          .textAlign(TextAlign.Center)
          .padding({ top: 24, bottom: 16 })
      } else {
        ForEach(this.depts, (dept: Dept, index: number) => {
          Column() {
            Row() {
              Text(dept.name)
                .layoutWeight(1)
                .fontSize(FontSize.body)
                .fontColor(Color.textPrimary)

              if (canManageDepts()) {
                Row({ space: 12 }) {
                  Text('改名')
                    .fontSize(FontSize.caption)
                    .fontColor(Color.primary)
                    .onClick(() => {
                      this.editingDeptId = dept.id;
                      this.editDeptName = dept.name;
                      this.showEditDialog = true;
                    })

                  Text('排序')
                    .fontSize(FontSize.caption)
                    .fontColor(Color.primary)
                    .onClick(() => { this.openSortDialog(dept); })

                  Text('删除')
                    .fontSize(FontSize.caption)
                    .fontColor(Color.primary)
                    .onClick(() => {
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
            }
            .width('100%')
            .height(38)

            if (index < this.depts.length - 1) {
              Divider()
                .strokeWidth(1)
                .color(Color.divider)
            }
          }
          .width('100%')
        }, (dept: Dept) => dept.id.toString())
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Color.surface)
    .border({ width: 1, color: Color.divider })
    .borderRadius(Radius.card)
    .bindContentCover(
      this.showCreateDialog || this.showEditDialog || this.showSortDialog ||
        this.showDeleteBlocked || this.showDeleteConfirm,
      this.deptDialogBuilder
    )
  }
}

// ====== 注册口令 ======
@Component
struct RegisterConfigSection {
  @State code: string = '';
  @State loading: boolean = true;
  @State showRotateConfirm: boolean = false;
  @State showChangeDialog: boolean = false;
  @State newCode: string = '';
  private memberApi: MemberApi = new MemberApi();

  aboutToAppear(): void {
    this.loadCode();
  }

  async loadCode(): Promise<void> {
    this.loading = true;
    const resp = await this.memberApi.getRegisterCode();
    if (resp.ok && resp.data) {
      this.code = resp.data.code;
    }
    this.loading = false;
  }

  async submitChange(): Promise<void> {
    if (this.newCode.length === 0) return;
    const resp = await this.memberApi.setRegisterCode({ code: this.newCode });
    if (resp.ok && resp.data) {
      this.code = resp.data.code;
      this.newCode = '';
      this.showChangeDialog = false;
    } else {
      AlertDialog.show({
        title: '更换失败',
        message: resp.error?.message ?? '请重试',
        primaryButton: { value: '知道了', action: () => {} }
      });
    }
  }

  async submitRotate(): Promise<void> {
    const resp = await this.memberApi.rotateRegisterCode();
    if (resp.ok && resp.data) {
      this.code = resp.data.code;
      this.showRotateConfirm = false;
    } else {
      this.showRotateConfirm = false;
      AlertDialog.show({
        title: '轮换失败',
        message: resp.error?.message ?? '请重试',
        primaryButton: { value: '知道了', action: () => {} }
      });
    }
  }

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
            .onClick(() => { this.submitChange(); })
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
            .onClick(() => { this.submitRotate(); })
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
      Text('注册口令')
        .width('100%')
        .fontSize(FontSize.body)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.textPrimary)

      Row({ space: 8 }) {
        Text(this.loading ? '加载中…' : this.code)
          .layoutWeight(1)
          .fontSize(FontSize.title)
          .fontWeight(FontWeight.Bold)
          .fontFamily('Inter')
          .fontFeature('"tnum" 1')
          .fontColor(Color.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .onClick(() => {
            if (!this.loading && this.code.length > 0) {
              copyText(this.code);
            }
          })

        if (canChangeRegisterCode()) {
          Button('更换')
            .type(ButtonType.Normal)
            .height(34)
            .fontSize(FontSize.caption)
            .fontColor(Color.textSecondary)
            .backgroundColor(Color.surface)
            .border({ width: 1, color: Color.divider })
            .borderRadius(Radius.input)
            .padding({ left: 12, right: 12 })
            .enabled(!this.loading)
            .onClick(() => {
              this.newCode = '';
              this.showChangeDialog = true;
            })

          Button('随机轮换')
            .type(ButtonType.Normal)
            .height(34)
            .fontSize(FontSize.caption)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.onPrimary)
            .backgroundColor(Color.primary)
            .borderRadius(Radius.input)
            .padding({ left: 12, right: 12 })
            .enabled(!this.loading)
            .onClick(() => {
              this.showRotateConfirm = true;
            })
        }
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Color.surface)
    .border({ width: 1, color: Color.divider })
    .borderRadius(Radius.card)
    .bindContentCover(this.showChangeDialog, this.changeDialogBuilder)
    .bindContentCover(this.showRotateConfirm, this.rotateDialogBuilder)
  }
}

// ====== 招募链接 ======
@Component
struct CreateLinkDialog {
  depts: Dept[] = [];
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

        Select(this.depts.map((d: Dept): SelectOption => ({ value: d.name })))
          .selected(this.selectedDeptIndex)
          .value(this.depts.length > 0 ? this.depts[this.selectedDeptIndex].name : '')
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
  @State links: InviteLink[] = [];
  @State depts: Dept[] = [];
  @State loading: boolean = true;
  @State showCreateDialog: boolean = false;
  private deptApi: DeptApi = new DeptApi();

  aboutToAppear(): void {
    this.loadLinks();
    this.loadDepts();
  }

  async loadLinks(): Promise<void> {
    this.loading = true;
    const resp = await this.deptApi.listLinks();
    if (resp.ok && resp.data) {
      this.links = resp.data.items.map((l: InviteLinkView): InviteLink => linkViewToInviteLink(l));
    }
    this.loading = false;
  }

  async loadDepts(): Promise<void> {
    const resp = await this.deptApi.list();
    if (resp.ok && resp.data) {
      this.depts = resp.data.items.map((d: DeptView): Dept => deptViewToDept(d));
    }
  }

  // 停用链接（后端 DELETE 语义：enabled 置 false，不做重新启用）
  async disableLink(id: string): Promise<void> {
    const resp = await this.deptApi.toggleLink(id);
    if (resp.ok && resp.data) {
      const updated: InviteLinkView = resp.data;
      const next: InviteLink[] = [];
      for (let i = 0; i < this.links.length; i++) {
        if (this.links[i].id === id) {
          next.push(linkViewToInviteLink(updated));
        } else {
          next.push(this.links[i]);
        }
      }
      this.links = next;
    } else {
      AlertDialog.show({
        title: '操作失败',
        message: resp.error?.message ?? '请重试',
        primaryButton: { value: '知道了', action: () => {} }
      });
    }
  }

  async createLink(deptIndex: number): Promise<void> {
    const dept: Dept = this.depts[deptIndex];
    if (dept === undefined) return;
    const resp = await this.deptApi.createLink(dept.id);
    if (resp.ok && resp.data) {
      this.links = [...this.links, linkViewToInviteLink(resp.data.link)];
      this.showCreateDialog = false;
    } else {
      AlertDialog.show({
        title: '生成失败',
        message: resp.error?.message ?? '请重试',
        primaryButton: { value: '知道了', action: () => {} }
      });
    }
  }

  @Builder
  createDialogBuilder() {
    CreateLinkDialog({
      depts: this.depts,
      onConfirm: (deptIndex: number): void => {
        this.createLink(deptIndex);
      },
      onCancel: (): void => {
        this.showCreateDialog = false;
      }
    })
  }

  build() {
    Column() {
      Row() {
        Text('招募链接')
          .layoutWeight(1)
          .fontSize(FontSize.body)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.textPrimary)

        if (canManageInviteLinks()) {
          Text('+ 生成链接')
            .fontSize(FontSize.caption)
            .fontColor(Color.primary)
            .onClick(() => {
              this.showCreateDialog = true;
            })
        }
      }
      .width('100%')

      if (this.loading) {
        Row() {
          LoadingProgress().width(24).height(24).color(Color.primary)
        }
        .width('100%')
        .height(64)
        .justifyContent(FlexAlign.Center)
      } else if (this.links.length === 0) {
        Text('暂无招募链接')
          .width('100%')
          .fontSize(FontSize.caption)
          .fontColor(Color.textTertiary)
          .textAlign(TextAlign.Center)
          .padding({ top: 24, bottom: 16 })
      } else {
        ForEach(this.links, (link: InviteLink, index: number) => {
          Column() {
            Row({ space: 8 }) {
              Column({ space: 2 }) {
                Text(`/join/${link.id}`)
                  .width('100%')
                  .fontSize(FontSize.body)
                  .fontFamily('Inter')
                  .fontColor(Color.textSecondary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                Text(`${link.deptName} 预填`)
                  .width('100%')
                  .fontSize(FontSize.micro)
                  .fontColor(Color.textTertiary)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Text(link.enabled ? '启用中' : '已停用')
                .fontSize(FontSize.caption)
                .fontColor(link.enabled ? Color.primary : Color.textTertiary)
                .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                .backgroundColor(link.enabled ? Color.primarySoft : StatusColor.todo.bg)
                .border({ width: 1, color: link.enabled ? Color.primaryBorder : Color.divider })
                .borderRadius(Radius.input)

              if (canManageInviteLinks() && link.enabled) {
                Text('停用')
                  .fontSize(FontSize.caption)
                  .fontColor(Color.textSecondary)
                  .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                  .border({ width: 1, color: Color.divider })
                  .borderRadius(Radius.input)
                  .onClick(() => { this.disableLink(link.id); })
              }
            }
            .width('100%')

            if (index < this.links.length - 1) {
              Divider()
                .strokeWidth(1)
                .color(Color.divider)
                .margin({ top: 12, bottom: 12 })
            }
          }
          .width('100%')
          .padding({ top: index === 0 ? 14 : 0 })
        }, (link: InviteLink) => link.id)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 14 })
    .backgroundColor(Color.surface)
    .border({ width: 1, color: Color.divider })
    .borderRadius(Radius.card)
    .bindContentCover(this.showCreateDialog, this.createDialogBuilder)
  }
}

// ====== 危险操作区（按权限显隐）======
@Component
struct DangerZoneSection {
  @State members: MemberOption[] = [];
  @State showTransferDialog: boolean = false;
  @State showResetDialog: boolean = false;
  @State showTransferResult: boolean = false;
  @State transferResultMsg: string = '';
  @State showResetResult: boolean = false;
  @State resetResultMsg: string = '';
  @State resetResultPassword: string = '';
  @State selectedTransferIndex: number = 0;
  @State selectedResetIndex: number = 0;
  private memberApi: MemberApi = new MemberApi();

  aboutToAppear(): void {
    this.loadMembers();
  }

  async loadMembers(): Promise<void> {
    const resp = await this.memberApi.list();
    if (resp.ok && resp.data) {
      this.members = resp.data.items
        .filter((m: MemberBrief): boolean => m.status === 'active')
        .map((m: MemberBrief): MemberOption => memberToMemberOption(m));
    }
  }

  private transferCandidateLabel(): string {
    const candidates: MemberOption[] = this.transferCandidates();
    if (candidates.length === 0) {
      return '暂无可移交成员';
    }
    return candidates[0].name;
  }

  // 移交给的候选（排除自己）
  transferCandidates(): MemberOption[] {
    return this.members.filter((m: MemberOption): boolean => m.id !== currentUserId());
  }

  // 重置密码的候选（排除自己）
  resetCandidates(): MemberOption[] {
    return this.members.filter((m: MemberOption): boolean => m.id !== currentUserId());
  }

  async submitTransfer(): Promise<void> {
    const candidates: MemberOption[] = this.transferCandidates();
    const target: MemberOption = candidates[this.selectedTransferIndex];
    if (target === undefined) return;
    const resp = await this.memberApi.transferPresidency(target.id);
    if (resp.ok && resp.data) {
      this.transferResultMsg = `已将会长权限移交至 ${target.name}（${target.deptName}）`;
      this.showTransferDialog = false;
      this.showTransferResult = true;
    } else {
      AlertDialog.show({
        title: '移交失败',
        message: resp.error?.message ?? '请重试',
        primaryButton: { value: '知道了', action: () => {} }
      });
    }
  }

  async submitReset(): Promise<void> {
    const candidates: MemberOption[] = this.resetCandidates();
    const target: MemberOption = candidates[this.selectedResetIndex];
    if (target === undefined) return;
    const resp = await this.memberApi.resetPassword(target.id);
    if (resp.ok && resp.data) {
      this.resetResultMsg = `已为 ${target.name} 重置密码`;
      this.resetResultPassword = resp.data.temporary_password;
      this.showResetDialog = false;
      this.showResetResult = true;
    } else {
      AlertDialog.show({
        title: '重置失败',
        message: resp.error?.message ?? '请重试',
        primaryButton: { value: '知道了', action: () => {} }
      });
    }
  }

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

        Select(this.transferCandidates().map((m: MemberOption): SelectOption => ({ value: `${m.name}（${m.deptName}）` })))
          .selected(this.selectedTransferIndex)
          .value(this.transferCandidates().length > 0 ? this.transferCandidates()[this.selectedTransferIndex].name : '请选择')
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
            .onClick(() => { this.submitTransfer(); })
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

        Select(this.resetCandidates().map((m: MemberOption): SelectOption => ({ value: `${m.name}（${m.deptName}）` })))
          .selected(this.selectedResetIndex)
          .value(this.resetCandidates().length > 0 ? this.resetCandidates()[this.selectedResetIndex].name : '请选择')
          .onSelect((index: number) => { this.selectedResetIndex = index; })
          .width('100%')
          .margin({ bottom: Space.xl })

        Button('生成临时密码')
          .type(ButtonType.Capsule)
          .backgroundColor(StatusColor.blocked.bg)
          .fontColor(StatusColor.blocked.fg)
          .width('100%')
          .borderRadius(Radius.button)
          .onClick(() => { this.submitReset(); })
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
  resetResultBuilder() {
    Column() {
      Column() {
        Text('重置成功')
          .fontSize(FontSize.title)
          .fontWeight(FontWeight.Bold)
          .fontColor(StatusColor.done.fg)
          .margin({ bottom: Space.sm })

        Text(this.resetResultMsg)
          .fontSize(FontSize.caption)
          .fontColor(Color.textSecondary)
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ bottom: Space.md })

        Text('一次性临时密码')
          .fontSize(FontSize.caption)
          .fontColor(Color.textTertiary)
          .margin({ bottom: Space.xs })

        Text(this.resetResultPassword)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.primary)
          .margin({ bottom: Space.lg })

        Row() {
          Button('复制密码')
            .type(ButtonType.Capsule)
            .backgroundColor(Color.primarySoft)
            .fontColor(Color.primary)
            .layoutWeight(1)
            .onClick(() => { copyText(this.resetResultPassword); })

          Button('知道了')
            .type(ButtonType.Capsule)
            .backgroundColor(StatusColor.done.bg)
            .fontColor(StatusColor.done.fg)
            .layoutWeight(1)
            .margin({ left: Space.md })
            .onClick(() => {
              this.resetResultMsg = '';
              this.resetResultPassword = '';
              this.showResetResult = false;
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
    if (canTransferPresidency()) {
      Column() {
        Text('会长移交')
          .width('100%')
          .fontSize(FontSize.body)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.danger)

        Text('原子操作：目标变成会长，自己降为你选的档位，两步同时生效。社团必须始终保留至少一位会长，因此这一项需要二次确认。')
          .width('100%')
          .fontSize(FontSize.micro)
          .fontColor(Color.textSecondary)
          .lineHeight(17)
          .margin({ top: 4, bottom: 12 })

        Button(`移交给 ${this.transferCandidateLabel()}`)
          .width('100%')
          .height(40)
          .type(ButtonType.Normal)
          .fontSize(FontSize.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.danger)
          .backgroundColor(Color.surface)
          .border({ width: 1, color: Color.dangerBorder })
          .borderRadius(Radius.button)
          .onClick(() => {
            this.showTransferDialog = true;
          })
      }
      .width('100%')
      .padding(16)
      .backgroundColor(Color.surface)
      .border({ width: 1, color: Color.dangerBorder })
      .borderRadius(Radius.card)
      .bindContentCover(this.showTransferDialog, this.transferDialogBuilder)
      .bindContentCover(this.showTransferResult, this.transferResultBuilder)
    }
  }
}


@Component
export default struct ManagePage {
  build() {
    Scroll() {
      Column({ space: 12 }) {
        if (canManageDepts()) {
          DeptManageSection()
        }
        if (canViewRegisterCode()) {
          RegisterConfigSection()
        }
        if (canManageInviteLinks()) {
          InviteLinkSection()
        }
        DangerZoneSection()

        Text('口令与链接都是敏感信息：轮换后旧口令立即失效；客户端不得落盘长存，也不得打印到设备日志。')
          .width('100%')
          .fontSize(FontSize.micro)
          .fontColor(Color.textTertiary)
          .lineHeight(17)
      }
      .width('100%')
      .padding({ left: Space.page, right: Space.page, top: 12, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.canvas)
    .scrollBar(BarState.Off)
  }
}
