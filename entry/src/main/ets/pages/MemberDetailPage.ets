// 成员详情页面
// 点击成员名录里的卡片跳转进来

import { MemberDetail, TaskBrief, ROLE_MAP } from '../model/MemberModel';
import { Colors, Radius, Spacing, StatusColors, StatusColorPair } from '../model/Theme';

const MEMBER_DETAIL: MemberDetail = {
  id: 1,
  name: '王会长',
  role: 'president',
  dept: { id: 1, name: '主席团' },
  status: 'active',
  joined_at: '2026-09-01',
};

const MEMBER_TASKS: TaskBrief[] = [
  { id: 101, title: '社团招新总体方案', status: 'doing', owner: null, dept: null, plan: null, due_at: '2026-09-20', is_overdue: false, blocked: false, updated_at: '2026-09-10T10:00:00+08:00' },
  { id: 102, title: '与指导老师沟通', status: 'todo', owner: null, dept: null, plan: null, due_at: '2026-09-18', is_overdue: false, blocked: false, updated_at: '2026-09-12T14:00:00+08:00' },
  { id: 103, title: '第一次全体大会', status: 'todo', owner: null, dept: null, plan: null, due_at: '2026-09-25', is_overdue: false, blocked: false, updated_at: '2026-09-14T09:00:00+08:00' },
];

const STATUS_LABEL: Record<string, string> = {
  'todo': '未开始',
  'doing': '进行中',
  'blocked': '阻塞',
  'done': '已完成',
};

@Component
struct TaskRow {
  task: TaskBrief = { id: 0, title: '', status: 'todo', owner: null, dept: null, plan: null, due_at: '', is_overdue: false, blocked: false, updated_at: '' };

  build() {
    Row() {
      Column() {
        Text(this.task.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.textPrimary)

        Text(this.getDueText())
          .fontSize(12)
          .fontColor(Colors.textTertiary)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(STATUS_LABEL[this.task.status] || '未开始')
        .fontSize(12)
        .fontColor(this.getStatusColor().fg)
        .padding({ left: 8, right: 8, top: 2, bottom: 2 })
        .backgroundColor(this.getStatusColor().bg)
        .borderRadius(Radius.capsule)
    }
    .width('100%')
    .padding(Spacing.cardInner)
    .backgroundColor(Colors.surface)
    .margin({ bottom: 1 })
  }

  getDueText(): string {
    if (!this.task.due_at) return '无截止';
    const label = this.task.is_overdue ? '已逾期' : '截止';
    return `${label} ${this.task.due_at}`;
  }

  getStatusColor(): StatusColorPair {
    switch (this.task.status) {
      case 'overdue': return StatusColors.overdue;
      case 'blocked': return StatusColors.blocked;
      case 'doing':   return StatusColors.doing;
      case 'done':    return StatusColors.done;
      default:        return StatusColors.todo;
    }
  }
}

@Component
export default struct MemberDetailPage {
  memberId: number = 0;
  @State member: MemberDetail = MEMBER_DETAIL;
  @State tasks: TaskBrief[] = MEMBER_TASKS;

  getRoleLabel(): string {
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

  build() {
    Scroll() {
      Column() {
        // 顶部个人信息卡
        Column() {
          Text(this.member.name.substring(0, 1))
            .fontSize(36)
            .fontColor(Color.White)
            .width(72)
            .height(72)
            .borderRadius(36)
            .backgroundColor(this.getAvatarColor())
            .textAlign(TextAlign.Center)
            .margin({ bottom: Spacing.md })

          Text(this.member.name)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(Colors.textPrimary)

          Text(`${this.member.dept?.name || '未分配'} · ${this.getRoleLabel()}`)
            .fontSize(14)
            .fontColor(Colors.textSecondary)
            .margin({ top: Spacing.xs })
        }
        .width('100%')
        .padding(Spacing.xl)
        .backgroundColor(Colors.surface)
        .borderRadius(Radius.card)
        .margin({ left: Spacing.page, right: Spacing.page, top: Spacing.page })

        // 基本信息
        Column() {
          Text('基本信息')
            .fontSize(14)
            .fontColor(Colors.textTertiary)
            .width('100%')
            .padding({ left: Spacing.lg, top: Spacing.md, bottom: Spacing.sm })

          Row() {
            Text('部门')
              .fontSize(14)
              .fontColor(Colors.textSecondary)
              .width(80)
            Text(this.member.dept?.name || '未分配')
              .fontSize(14)
              .fontColor(Colors.textPrimary)
          }
          .width('100%')
          .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.sm, bottom: Spacing.sm })

          Divider().color(Colors.divider).margin({ left: Spacing.lg })

          Row() {
            Text('加入时间')
              .fontSize(14)
              .fontColor(Colors.textSecondary)
              .width(80)
            Text(this.member.joined_at)
              .fontSize(14)
              .fontColor(Colors.textPrimary)
          }
          .width('100%')
          .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.sm, bottom: Spacing.sm })

          Divider().color(Colors.divider).margin({ left: Spacing.lg })

          Row() {
            Text('状态')
              .fontSize(14)
              .fontColor(Colors.textSecondary)
              .width(80)
            Text(this.member.status === 'active' ? '正常' : this.member.status)
              .fontSize(14)
              .fontColor(this.member.status === 'active' ? StatusColors.done.fg : StatusColors.overdue.fg)
          }
          .width('100%')
          .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.sm, bottom: Spacing.md })
        }
        .width('100%')
        .backgroundColor(Colors.surface)
        .borderRadius(Radius.card)
        .margin({ left: Spacing.page, right: Spacing.page, top: Spacing.md })

        // 负责的任务
        Column() {
          Row() {
            Text('负责的任务')
              .fontSize(14)
              .fontColor(Colors.textTertiary)

            Blank()

            Text(`${this.tasks.length} 项`)
              .fontSize(14)
              .fontColor(Colors.textTertiary)
          }
          .width('100%')
          .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.lg, bottom: Spacing.sm })

          Column() {
            ForEach(this.tasks, (task: TaskBrief) => {
              TaskRow({ task: task })
            }, (task: TaskBrief) => task.id.toString())

            if (this.tasks.length === 0) {
              Text('暂无任务')
                .fontSize(14)
                .fontColor(Colors.textTertiary)
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding(Spacing.xl)
            }
          }
        }
        .width('100%')
        .backgroundColor(Colors.surface)
        .borderRadius(Radius.card)
        .margin({ left: Spacing.page, right: Spacing.page, top: Spacing.md })

        // 操作按钮区
        Column() {
          Button('重置密码')
            .type(ButtonType.Normal)
            .backgroundColor(StatusColors.blocked.bg)
            .fontColor(StatusColors.blocked.fg)
            .width('100%')
            .borderRadius(Radius.button)
            .margin({ bottom: Spacing.md })

          Button('移出社团')
            .type(ButtonType.Normal)
            .backgroundColor(StatusColors.overdue.bg)
            .fontColor(StatusColors.overdue.fg)
            .width('100%')
            .borderRadius(Radius.button)
        }
        .width('100%')
        .padding(Spacing.lg)
        .margin({ left: Spacing.page, right: Spacing.page, top: Spacing.xl, bottom: Spacing.page })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Colors.canvas)
    .scrollBar(BarState.Off)
  }
}
