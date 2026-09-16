// 待分配审批页面（B同学负责）
// 展示 pending 状态的成员，支持多选批量分配部门+角色
// 含：dept_hint 招募来源展示、批量分配结果逐条展示（succeeded/failed）
// 工程化：Theme token 化、bindContentCover 化

import type { DeptBrief } from '../api/AuthApi';
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

// ─── 假数据（接 API 后改为 MemberApi.pending() 加载）───
const DEPTS: Dept[] = [
  { id: 0, name: '主席团' },
  { id: 1, name: '课题部' },
  { id: 2, name: '运营部' },
  { id: 3, name: '宣传部' },
];

const ROLE_OPTIONS: RoleOption[] = [
  { key: 'member', label: '成员' },
  { key: 'vice_lead', label: '副部长' },
  { key: 'lead', label: '部长' },
  { key: 'vice_president', label: '副会长' },
  { key: 'president', label: '会长' },
];

const PENDING_MEMBERS: PendingMemberUI[] = [
  { id: 101, name: '新同学A', deptHint: { id: 1, name: '课题部' }, registeredAt: '2026-09-14 10:30', selected: false },
  { id: 102, name: '新同学B', deptHint: null, registeredAt: '2026-09-14 11:00', selected: false },
  { id: 103, name: '新同学C', deptHint: { id: 2, name: '运营部' }, registeredAt: '2026-09-14 14:20', selected: false },
  { id: 104, name: '新同学D', deptHint: { id: 3, name: '宣传部' }, registeredAt: '2026-09-14 15:45', selected: false },
  { id: 105, name: '新同学E', deptHint: null, registeredAt: '2026-09-14 16:10', selected: false },
];

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

        Select(DEPTS.map((d: Dept): SelectOption => ({ value: d.name })))
          .selected(this.selectedDeptIndex)
          .value(DEPTS[this.selectedDeptIndex].name)
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

@Component
export default struct PendingApprovalPage {
  @State members: PendingMemberUI[] = PENDING_MEMBERS;
  @State showAssignDialog: boolean = false;
  @State showAssignResult: boolean = false;
  @State assignResults: AssignResultItem[] = [];

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

  // 执行批量分配，构造逐条结果，展示结果弹窗
  doAssign(deptIndex: number, roleIndex: number): void {
    const dept: Dept = DEPTS[deptIndex];
    const role: RoleOption = ROLE_OPTIONS[roleIndex];
    const selected: PendingMemberUI[] = this.members.filter((m: PendingMemberUI): boolean => m.selected);

    // TODO: 接入 MemberApi.assignBatch({ dept_id: dept.id, role: role.key, member_ids: ... })
    //       后端返回 AssignBatchResponse { succeeded: number[], failed: BatchFailItem[] }
    //       根据响应构造 results：succeeded 里的 id → ok=true；failed 里的 → ok=false，按 code 映射错误信息
    // mock：本地构造结果（模拟部分失败 —— deptHint 为 null 的成员失败，演示"逐条结果"展示）
    const results: AssignResultItem[] = selected.map((m: PendingMemberUI): AssignResultItem => {
      const ok: boolean = m.deptHint !== null;
      const item: AssignResultItem = {
        id: m.id,
        name: m.name,
        ok: ok,
        roleName: role.label,
        deptName: dept.name,
        errorMsg: ok ? '' : '未指定招募来源，需人工分配',
      };
      return item;
    });

    this.assignResults = results;
    this.showAssignDialog = false;
    this.showAssignResult = true;

    // 从列表移除成功的成员（mock；真接入后用后端返回的 succeeded 数组判断）
    const succeededIds: number[] = results
      .filter((r: AssignResultItem): boolean => r.ok)
      .map((r: AssignResultItem): number => r.id);
    this.members = this.members.filter((m: PendingMemberUI): boolean => !succeededIds.includes(m.id));
  }

  @Builder
  assignDialogBuilder() {
    AssignDialog({
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

      if (this.members.length === 0) {
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
