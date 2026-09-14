// 待分配审批页面
// 展示 pending 状态的成员，支持多选批量分配部门+角色

import { MemberBrief, Dept, DeptBrief, MOCK_DEPTS, MOCK_PENDING_MEMBERS, ROLE_MAP } from '../model/MemberModel';
import { Colors, Radius, Spacing, StatusColors } from '../model/Theme';

// 带 UI 选择状态的待分配成员（独立 interface，不用 extends，ArkTS 兼容）
interface PendingMemberUI {
  id: number;
  name: string;
  role: string | null;
  dept: DeptBrief | null;
  status: string;
  joined_at: string;
  selected: boolean;
}

// 手动构造，避免对象展开（ArkTS 兼容）
function toPendingUI(m: MemberBrief): PendingMemberUI {
  return {
    id: m.id,
    name: m.name,
    role: m.role,
    dept: m.dept,
    status: m.status,
    joined_at: m.joined_at,
    selected: false,
  };
}

const PENDING_MEMBERS_UI: PendingMemberUI[] = MOCK_PENDING_MEMBERS.map(toPendingUI);

const ROLES: string[] = ['member', 'vice_lead', 'lead', 'vice_president', 'president'];

@Component
struct PendingMemberCard {
  member: PendingMemberUI = { id: 0, name: '', role: '', dept: null, status: 'pending', joined_at: '', selected: false };
  onToggle: (id: number) => void = (_id: number) => {};

  build() {
    Row() {
      Checkbox()
        .select(this.member.selected)
        .onChange((checked: boolean) => { this.onToggle(this.member.id); })
        .width(24)
        .height(24)

      Column() {
        Text(this.member.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.textPrimary)

        Text(`注册于 ${this.member.joined_at}`)
          .fontSize(12)
          .fontColor(Colors.textTertiary)
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: Spacing.md })
      .layoutWeight(1)
    }
    .width('100%')
    .padding(Spacing.cardInner)
    .backgroundColor(Colors.surface)
    .borderRadius(Radius.card)
    .margin({ bottom: Spacing.cardGap })
  }
}

@Component
struct AssignBottomBar {
  selectedCount: number = 0;
  onAssign: () => void = () => {};

  build() {
    Row() {
      Text(`已选 ${this.selectedCount} 人`)
        .fontSize(14)
        .fontColor(Colors.textSecondary)

      Button('批量分配')
        .type(ButtonType.Capsule)
        .backgroundColor(Colors.primary)
        .fontColor(Color.White)
        .enabled(this.selectedCount > 0)
        .onClick(() => { this.onAssign(); })
    }
    .width('100%')
    .padding({ left: Spacing.page, right: Spacing.page, top: Spacing.md, bottom: Spacing.md })
    .backgroundColor(Colors.surface)
    .justifyContent(FlexAlign.SpaceBetween)
    .shadow({ radius: 4, color: '#1A000000', offsetY: -2 })
  }
}

@Component
struct AssignDialog {
  show: boolean = false;
  selectedDeptId: number = 1;
  selectedRoleIndex: number = 0;
  onConfirm: () => void = () => {};
  onCancel: () => void = () => {};

  build() {
    if (this.show) {
      Column() {
        Column() {
          Text('批量分配')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Colors.textPrimary)
            .margin({ bottom: Spacing.lg })

          Text('分配到部门')
            .fontSize(14)
            .fontColor(Colors.textSecondary)
            .width('100%')
            .margin({ bottom: Spacing.xs })

          Select([
            { value: MOCK_DEPTS[0].name },
            { value: MOCK_DEPTS[1].name },
            { value: MOCK_DEPTS[2].name },
            { value: MOCK_DEPTS[3].name },
          ])
            .selected(this.selectedDeptId)
            .value(MOCK_DEPTS[this.selectedDeptId].name)
            .onSelect((index: number) => { this.selectedDeptId = index; })
            .width('100%')
            .margin({ bottom: Spacing.lg })

          Text('角色')
            .fontSize(14)
            .fontColor(Colors.textSecondary)
            .width('100%')
            .margin({ bottom: Spacing.xs })

          Select([
            { value: ROLE_MAP['member'] },
            { value: ROLE_MAP['vice_lead'] },
            { value: ROLE_MAP['lead'] },
            { value: ROLE_MAP['vice_president'] },
            { value: ROLE_MAP['president'] },
          ])
            .selected(this.selectedRoleIndex)
            .value(ROLE_MAP[ROLES[this.selectedRoleIndex]])
            .onSelect((index: number) => { this.selectedRoleIndex = index; })
            .width('100%')
            .margin({ bottom: Spacing.xl })

          Row() {
            Button('取消')
              .type(ButtonType.Normal)
              .backgroundColor(StatusColors.todo.bg)
              .fontColor(Colors.textSecondary)
              .layoutWeight(1)
              .borderRadius(Radius.button)
              .onClick(() => { this.onCancel(); })

            Button('确认分配')
              .type(ButtonType.Capsule)
              .backgroundColor(Colors.primary)
              .fontColor(Color.White)
              .layoutWeight(1)
              .margin({ left: Spacing.md })
              .onClick(() => { this.onConfirm(); })
          }
          .width('100%')
        }
        .width('85%')
        .padding(Spacing.xl)
        .backgroundColor(Colors.surface)
        .borderRadius(Radius.card)
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#80000000')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }
}

@Component
export default struct PendingApprovalPage {
  @State members: PendingMemberUI[] = PENDING_MEMBERS_UI;
  @State showAssignDialog: boolean = false;

  toggleSelect(id: number): void {
    const idx = this.members.findIndex((m: PendingMemberUI) => m.id === id);
    if (idx >= 0) {
      this.members[idx].selected = !this.members[idx].selected;
      this.members = [...this.members];
    }
  }

  getSelectedCount(): number {
    return this.members.filter((m: PendingMemberUI) => m.selected).length;
  }

  selectAll(): void {
    const allSelected = this.getSelectedCount() === this.members.length;
    this.members.forEach((m: PendingMemberUI) => m.selected = !allSelected);
    this.members = [...this.members];
  }

  build() {
    Column() {
      Row() {
        Text('待审批列表')
          .fontSize(14)
          .fontColor(Colors.textSecondary)

        Blank()

        Text(this.getSelectedCount() === this.members.length ? '取消全选' : '全选')
          .fontSize(14)
          .fontColor(Colors.primary)
          .onClick(() => { this.selectAll(); })
      }
      .width('100%')
      .padding({ left: Spacing.page, right: Spacing.page, top: Spacing.md, bottom: Spacing.sm })

      if (this.members.length === 0) {
        Column() {
          Text('🎉')
            .fontSize(48)
            .margin({ bottom: Spacing.md })

          Text('暂无待审批成员')
            .fontSize(14)
            .fontColor(Colors.textTertiary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ space: Spacing.cardGap }) {
          ForEach(this.members, (item: PendingMemberUI) => {
            ListItem() {
              PendingMemberCard({
                member: item,
                onToggle: (id: number) => this.toggleSelect(id)
              })
            }
          }, (item: PendingMemberUI) => item.id.toString())
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: Spacing.page, right: Spacing.page, top: Spacing.xs, bottom: Spacing.sm })
      }

      if (this.getSelectedCount() > 0) {
        AssignBottomBar({
          selectedCount: this.getSelectedCount(),
          onAssign: () => { this.showAssignDialog = true; }
        })
      }

      AssignDialog({
        show: this.showAssignDialog,
        onConfirm: () => {
          this.showAssignDialog = false;
          this.members.forEach((m: PendingMemberUI) => m.selected = false);
          this.members = [...this.members];
        },
        onCancel: () => {
          this.showAssignDialog = false;
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Colors.canvas)
  }
}
