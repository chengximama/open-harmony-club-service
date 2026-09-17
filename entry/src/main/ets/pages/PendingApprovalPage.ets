// 待分配审批页面（B同学负责）
// 展示 pending 状态的成员，支持多选批量分配部门+角色
// 含：dept_hint 招募来源展示、批量分配结果逐条展示（succeeded/failed）
// 工程化：Theme token 化、bindContentCover 化
// 已接真接口：MemberApi.pending() / MemberApi.assignBatch() / DeptApi.list()

import type { DeptBrief } from '../api/AuthApi';
import { MemberApi, PendingMemberView, AssignBatchResponse, BatchFailItem } from '../api/MemberApi';
import { DeptApi, DeptView } from '../api/DeptApi';
import { Color, StatusColor, Space, Radius, FontSize, Shadow } from '../core/Theme';

// 带 UI 选择状态的待分配成员（独立 interface，不用 extends，ArkTS 兼容）
// deptHint 对齐为 DeptBrief | null（来自后端 PendingMemberView.dept_hint）
interface PendingMemberUI {
  id: number;
  name: string;
  deptHint: DeptBrief | null;    // 招募来源部门提示
  registeredAt: string;
  selected: boolean;
}

interface Dept {
  id: number;
  name: string;
}

interface RoleOption {
  key: string;
  label: string;
}

// 批量分配结果条目（逐条展示）
interface AssignResultItem {
  id: number;
  name: string;
  ok: boolean;
  roleName: string;     // 成功时显示分配的角色
  deptName: string;     // 成功时显示分配的部门
  errorMsg: string;     // 失败时显示错误信息
}

// ─── 角色选项（静态 UI 数据）───
const ROLE_OPTIONS: RoleOption[] = [
  { key: 'member', label: '成员' },
  { key: 'vice_lead', label: '副部长' },
  { key: 'lead', label: '部长' },
  { key: 'vice_president', label: '副会长' },
  { key: 'president', label: '会长' },
];

// 批量分配失败的错误码 → 文案（与后端 errors.cj 对齐）
function batchFailMsg(code: string): string {
  if (code === 'FORBIDDEN_ROLE') return '当前角色无权执行此操作';
  if (code === 'FORBIDDEN_LAST_PRESIDENT') return '系统必须始终保留至少一位会长';
  if (code === 'FORBIDDEN_NOT_IN_DEPT') return '不能操作其他部门';
  if (code === 'MEMBER_NOT_FOUND') return '成员不存在';
  if (code === 'MEMBER_DISABLED') return '该成员已退出社团';
  return '分配失败';
}

// 在失败列表里按 id 找错误码
function findFailCode(failed: BatchFailItem[], id: number): string {
  for (let i = 0; i < failed.length; i++) {
    if (failed[i].id === id) return failed[i].code;
  }
  return '';
}

@Component
struct PendingMemberCard {
  member: PendingMemberUI = { id: 0, name: '', deptHint: null, registeredAt: '', selected: false };
  onToggle: (id: number) => void = (_id: number) => {};

  build() {
    Row() {
      Checkbox()
        .select(this.member.selected)
        .onChange((_checked: boolean) => { this.onToggle(this.member.id); })
        .width(24)
        .height(24)

      Column() {
        Row() {
          Text(this.member.name)
            .fontSize(FontSize.subtitle)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.textPrimary)

          if (this.member.deptHint !== null) {
            Text(`· 意向: ${this.member.deptHint.name}`)
              .fontSize(FontSize.caption)
              .fontColor(StatusColor.blocked.fg)
              .margin({ left: Space.sm })
          }
        }

        Text(`注册于 ${this.member.registeredAt}`)
          .fontSize(FontSize.caption)
          .fontColor(Color.textTertiary)
          .margin({ top: Space.xs })
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: Space.md })
      .layoutWeight(1)
    }
    .width('100%')
    .padding(Space.card)
    .backgroundColor(Color.surface)
    .borderRadius(Radius.card)
    .margin({ bottom: Space.cardGap })
  }
}

@Component
struct AssignBottomBar {
  selectedCount: number = 0;
  onAssign: () => void = () => {};

  build() {
    Row() {
      Text(`已选 ${this.selectedCount} 人`)
        .fontSize(FontSize.body)
        .fontColor(Color.textSecondary)

      Button('批量分配')
        .type(ButtonType.Capsule)
        .backgroundColor(Color.primary)
        .fontColor(Color.onPrimary)
        .enabled(this.selectedCount > 0)
        .onClick(() => { this.onAssign(); })
    }
    .width('100%')
    .padding({ left: Space.page, right: Space.page, top: Space.md, bottom: Space.md })
    .backgroundColor(Color.surface)
    .justifyContent(FlexAlign.SpaceBetween)
    .shadow(Shadow.card)
  }
}

// 批量分配弹窗：由 bindContentCover 挂载，每次打开都是新实例，选择态自动重置为默认值
@Component
struct AssignDialog {
  depts: Dept[] = [];
  onConfirm: (deptIndex: number, roleIndex: number) => void = (_d: number, _r: number) => {};
  onCancel: () => void = () => {};
  @State selectedDeptIndex: number = 0;
  @State selectedRoleIndex: number = 0;

  build() {
    Column() {
      Column() {
        Text('批量分配')
          .fontSize(FontSize.title)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.textPrimary)
          .margin({ bottom: Space.lg })

        Text('分配到部门')
          .fontSize(FontSize.body)
          .fontColor(Color.textSecondary)
          .width('100%')
          .margin({ bottom: Space.xs })

        Select(this.depts.map((d: Dept): SelectOption => ({ value: d.name })))
          .selected(this.selectedDeptIndex)
          .value(this.depts.length > 0 ? this.depts[this.selectedDeptIndex].name : '')
          .onSelect((index: number) => { this.selectedDeptIndex = index; })
          .width('100%')
          .margin({ bottom: Space.lg })

        Text('角色')
          .fontSize(FontSize.body)
          .fontColor(Color.textSecondary)
          .width('100%')
          .margin({ bottom: Space.xs })

        Select(ROLE_OPTIONS.map((r: RoleOption): SelectOption => ({ value: r.label })))
          .selected(this.selectedRoleIndex)
          .value(ROLE_OPTIONS[this.selectedRoleIndex].label)
          .onSelect((index: number) => { this.selectedRoleIndex = index; })
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

          Button('确认分配')
            .type(ButtonType.Capsule)
            .backgroundColor(Color.primary)
            .fontColor(Color.onPrimary)
            .layoutWeight(1)
            .margin({ left: Space.md })
            .onClick(() => { this.onConfirm(this.selectedDeptIndex, this.selectedRoleIndex); })
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
}

// 批量分配结果弹窗：逐条展示 succeeded / failed（满足"显示 3 succeeded, 2 failed"的口径）
@Component
struct AssignResultDialog {
  results: AssignResultItem[] = [];
  onConfirm: () => void = () => {};

  getSuccessCount(): number {
    return this.results.filter((r: AssignResultItem): boolean => r.ok).length;
  }

  getFailCount(): number {
    return this.results.filter((r: AssignResultItem): boolean => !r.ok).length;
  }

  build() {
    Column() {
      Column() {
        Text('分配结果')
          .fontSize(FontSize.title)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.textPrimary)
          .margin({ bottom: Space.sm })

        Text(`${this.getSuccessCount()} 成功 / ${this.getFailCount()} 失败`)
          .fontSize(FontSize.body)
          .fontColor(Color.textSecondary)
          .margin({ bottom: Space.lg })

        Scroll() {
          Column() {
            ForEach(this.results, (r: AssignResultItem) => {
              Row() {
                Text(r.name)
                  .fontSize(FontSize.body)
                  .fontColor(Color.textPrimary)
                  .layoutWeight(1)

                if (r.ok) {
                  Text(`✓ ${r.roleName} @ ${r.deptName}`)
                    .fontSize(FontSize.caption)
                    .fontColor(StatusColor.done.fg)
                } else {
                  Text(`✗ ${r.errorMsg}`)
                    .fontSize(FontSize.caption)
                    .fontColor(StatusColor.overdue.fg)
                }
              }
              .width('100%')
              .padding({ top: Space.sm, bottom: Space.sm })
            }, (r: AssignResultItem) => r.id.toString())
          }
          .width('100%')
        }
        .height(200)
        .margin({ bottom: Space.lg })

        Button('知道了')
          .type(ButtonType.Capsule)
          .backgroundColor(Color.primary)
          .fontColor(Color.onPrimary)
          .width('100%')
          .borderRadius(Radius.button)
          .onClick(() => { this.onConfirm(); })
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
}

@Entry
@Component
export default struct PendingApprovalPage {
  @State members: PendingMemberUI[] = [];
  @State depts: Dept[] = [];
  @State loading: boolean = true;
  @State errorMsg: string = '';
  @State showAssignDialog: boolean = false;
  @State showAssignResult: boolean = false;
  @State assignResults: AssignResultItem[] = [];
  private memberApi: MemberApi = new MemberApi();
  private deptApi: DeptApi = new DeptApi();

  aboutToAppear(): void {
    this.loadData();
  }

  async loadData(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    await this.loadDepts();
    await this.loadPending();
    this.loading = false;
  }

  async loadDepts(): Promise<void> {
    const resp = await this.deptApi.list();
    if (resp.ok && resp.data) {
      this.depts = resp.data.items.map((d: DeptView): Dept => ({ id: d.id, name: d.name }));
    } else {
      this.errorMsg = resp.error?.message ?? '加载部门失败';
    }
  }

  async loadPending(): Promise<void> {
    const resp = await this.memberApi.pending();
    if (resp.ok && resp.data) {
      this.members = resp.data.items.map((v: PendingMemberView): PendingMemberUI => ({
        id: v.id,
        name: v.name,
        deptHint: v.dept_hint,
        registeredAt: v.registered_at ?? '',
        selected: false,
      }));
    } else {
      this.errorMsg = resp.error?.message ?? '加载待审批成员失败';
    }
  }

  toggleSelect(id: number): void {
    const idx = this.members.findIndex((m: PendingMemberUI): boolean => m.id === id);
    if (idx >= 0) {
      this.members[idx].selected = !this.members[idx].selected;
      this.members = [...this.members];
    }
  }

  getSelectedCount(): number {
    return this.members.filter((m: PendingMemberUI): boolean => m.selected).length;
  }

  selectAll(): void {
    const allSelected = this.getSelectedCount() === this.members.length;
    this.members.forEach((m: PendingMemberUI): void => { m.selected = !allSelected; });
    this.members = [...this.members];
  }

  // 执行批量分配：调真实接口，按后端 succeeded/failed 构造逐条结果
  async doAssign(deptIndex: number, roleIndex: number): Promise<void> {
    if (this.depts.length === 0) return;
    const dept: Dept = this.depts[deptIndex];
    const role: RoleOption = ROLE_OPTIONS[roleIndex];
    const selected: PendingMemberUI[] = this.members.filter((m: PendingMemberUI): boolean => m.selected);
    const memberIds: number[] = selected.map((m: PendingMemberUI): number => m.id);

    const resp = await this.memberApi.assignBatch({
      dept_id: dept.id,
      role: role.key,
      member_ids: memberIds,
    });

    if (resp.ok && resp.data) {
      const data: AssignBatchResponse = resp.data;
      const succeededIds: number[] = data.succeeded;
      const results: AssignResultItem[] = selected.map((m: PendingMemberUI): AssignResultItem => {
        const ok: boolean = succeededIds.includes(m.id);
        return {
          id: m.id,
          name: m.name,
          ok: ok,
          roleName: role.label,
          deptName: dept.name,
          errorMsg: ok ? '' : batchFailMsg(findFailCode(data.failed, m.id)),
        };
      });

      this.assignResults = results;
      this.showAssignDialog = false;
      this.showAssignResult = true;
      // 从列表移除分配成功的成员
      this.members = this.members.filter((m: PendingMemberUI): boolean => !succeededIds.includes(m.id));
    } else {
      // 整批失败（网络/权限等）：全部标为失败
      const errMsg: string = resp.error?.message ?? '分配失败';
      const results: AssignResultItem[] = selected.map((m: PendingMemberUI): AssignResultItem => ({
        id: m.id,
        name: m.name,
        ok: false,
        roleName: role.label,
        deptName: dept.name,
        errorMsg: errMsg,
      }));
      this.assignResults = results;
      this.showAssignDialog = false;
      this.showAssignResult = true;
    }
  }

  @Builder
  assignDialogBuilder() {
    AssignDialog({
      depts: this.depts,
      onConfirm: (deptIndex: number, roleIndex: number): void => {
        this.doAssign(deptIndex, roleIndex);
      },
      onCancel: (): void => {
        this.showAssignDialog = false;
      }
    })
  }

  @Builder
  assignResultBuilder() {
    AssignResultDialog({
      results: this.assignResults,
      onConfirm: (): void => {
        this.showAssignResult = false;
        // 清空已选状态（成功成员已移除，剩余成员重置 selected）
        this.members.forEach((m: PendingMemberUI): void => { m.selected = false; });
        this.members = [...this.members];
      }
    })
  }

  build() {
    Column() {
      Row() {
        Text('待审批列表')
          .fontSize(FontSize.body)
          .fontColor(Color.textSecondary)

        Blank()

        Text(this.getSelectedCount() === this.members.length ? '取消全选' : '全选')
          .fontSize(FontSize.body)
          .fontColor(Color.primary)
          .onClick(() => { this.selectAll(); })
      }
      .width('100%')
      .padding({ left: Space.page, right: Space.page, top: Space.md, bottom: Space.sm })

      if (this.loading) {
        Column() {
          LoadingProgress().width(32).height(32).color(Color.primary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.errorMsg.length > 0) {
        Column() {
          Text(this.errorMsg)
            .fontSize(FontSize.body)
            .fontColor(StatusColor.overdue.fg)
            .textAlign(TextAlign.Center)

          Button('重试')
            .type(ButtonType.Capsule)
            .backgroundColor(Color.primary)
            .fontColor(Color.onPrimary)
            .margin({ top: Space.md })
            .onClick(() => { this.loadData(); })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.members.length === 0) {
        Column() {
          Text('🎉')
            .fontSize(48)
            .margin({ bottom: Space.md })

          Text('暂无待审批成员')
            .fontSize(FontSize.body)
            .fontColor(Color.textTertiary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ space: Space.cardGap }) {
          ForEach(this.members, (item: PendingMemberUI) => {
            ListItem() {
              PendingMemberCard({
                member: item,
                onToggle: (id: number): void => this.toggleSelect(id)
              })
            }
          }, (item: PendingMemberUI) => item.id.toString())
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: Space.page, right: Space.page, top: Space.xs, bottom: Space.sm })
      }

      if (this.getSelectedCount() > 0) {
        AssignBottomBar({
          selectedCount: this.getSelectedCount(),
          onAssign: (): void => { this.showAssignDialog = true; }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.canvas)
    .bindContentCover(this.showAssignDialog, this.assignDialogBuilder)
    .bindContentCover(this.showAssignResult, this.assignResultBuilder)
  }
}
