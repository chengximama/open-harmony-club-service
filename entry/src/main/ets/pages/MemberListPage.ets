// 成员名录页面
// 按 4 个部门分组展示成员，点击卡片进入成员详情

import { MemberBrief, Dept, MOCK_DEPTS, MOCK_MEMBERS, ROLE_MAP } from '../model/MemberModel';
import { Colors, Radius, Spacing, StatusColors } from '../model/Theme';

@Component
struct MemberCard {
  member: MemberBrief = { id: 0, name: '', role: 'member', dept: null, status: 'active', joined_at: '' };
  onCardClick: () => void = () => {};

  build() {
    Row() {
      Text(this.member.name.substring(0, 1))
        .fontSize(20)
        .fontColor(Color.White)
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(this.getAvatarColor())
        .textAlign(TextAlign.Center)

      Column() {
        Text(this.member.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.textPrimary)

        Text(this.getRoleName())
          .fontSize(12)
          .fontColor(Colors.textTertiary)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: Spacing.md })
      .layoutWeight(1)

      Text(this.member.dept?.name || '未分配')
        .fontSize(12)
        .fontColor(Colors.textTertiary)
    }
    .width('100%')
    .padding(Spacing.cardInner)
    .backgroundColor(Colors.surface)
    .borderRadius(Radius.card)
    .margin({ bottom: Spacing.cardGap })
    .onClick(() => { this.onCardClick(); })
  }

  getRoleName(): string {
    return ROLE_MAP[this.member.role] || '成员';
  }

  getAvatarColor(): string {
    switch (this.member.role) {
      case 'president': return StatusColors.overdue.fg;
      case 'vice_president': return StatusColors.blocked.fg;
      case 'lead': return Colors.primary;
      case 'vice_lead': return StatusColors.done.fg;
      default: return StatusColors.pending.fg;
    }
  }
}

@Component
struct DeptSection {
  deptName: string = '';
  members: MemberBrief[] = [];
  onMemberClick: (memberId: number) => void = (_id: number) => {};

  build() {
    Column() {
      Text(this.deptName)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.textPrimary)
        .width('100%')
        .padding({ left: 4, top: Spacing.sm, bottom: Spacing.xs })

      ForEach(this.members, (item: MemberBrief) => {
        MemberCard({
          member: item,
          onCardClick: () => this.onMemberClick(item.id)
        })
      }, (item: MemberBrief) => item.id.toString())
    }
    .width('100%')
  }
}

@Component
export default struct MemberListPage {
  onMemberClick: (memberId: number) => void = (_id: number) => {};
  @State members: MemberBrief[] = MOCK_MEMBERS;

  getMembersByDept(deptId: number): MemberBrief[] {
    return this.members.filter((m: MemberBrief) => m.dept?.id === deptId);
  }

  build() {
    Column() {
      Row() {
        Text('搜索成员')
          .fontSize(14)
          .fontColor(Colors.textTertiary)
          .width('100%')
          .padding(Spacing.md)
          .backgroundColor(Colors.surface)
          .borderRadius(Radius.input)
      }
      .width('100%')
      .padding({ left: Spacing.page, right: Spacing.page, top: Spacing.md, bottom: Spacing.sm })

      List({ space: Spacing.cardGap }) {
        ForEach(MOCK_DEPTS, (dept: Dept) => {
          ListItem() {
            DeptSection({
              deptName: dept.name,
              members: this.getMembersByDept(dept.id),
              onMemberClick: (id: number) => this.onMemberClick(id)
            })
          }
        }, (dept: Dept) => dept.id.toString())
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: Spacing.page, right: Spacing.page, top: Spacing.xs, bottom: Spacing.page })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Colors.canvas)
  }
}
