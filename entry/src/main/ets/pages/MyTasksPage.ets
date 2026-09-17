// 首页「我的任务」：服务端分组直接渲染，客户端不做逾期判断。
import router from '@ohos.router'
import { TaskApi, MineGroups, TaskBrief } from '../api/TaskApi'
import { StatusChip } from '../components/StatusChip'
import { Color, FontSize, Radius, Shadow, Space, StatusColor } from '../core/Theme'
import { PermissionStore } from '../store/PermissionStore'
import { CalendarSyncService } from '../util/CalendarSync'

const EMPTY_MINE_GROUPS: MineGroups = {
  overdue: [], blocked: [], due_today: [], due_week: [], later: [], no_due: [],
  counts: { overdue: 0, blocked: 0, open_total: 0 }
}

@Component
export default struct MyTasksPage {
  @State myTasks: MineGroups = EMPTY_MINE_GROUPS
  @State loading: boolean = true
  @State errorMsg: string = ''
  @State syncedAt: string = '--:--'

  onOpenPlans?: () => void
  @Prop @Watch('onRefreshSignal') refreshSignal: number = 0

  private taskApi: TaskApi = new TaskApi()
  private permissionStore: PermissionStore = PermissionStore.getInstance()
  private calendarSync: CalendarSyncService = CalendarSyncService.getInstance()

  aboutToAppear(): void {
    this.load()
  }

  onRefreshSignal(): void {
    this.load()
  }

  private async load(): Promise<void> {
    this.loading = true
    this.errorMsg = ''
    const resp = await this.taskApi.mine()
    if (resp.ok && resp.data) {
      this.myTasks = resp.data
      this.syncedAt = this.clockText()
    } else {
      this.errorMsg = resp.error?.message ?? '加载失败'
    }
    this.loading = false
    this.calendarSync.reconcile(getContext(this))
  }

  private clockText(): string {
    const d = new Date()
    const h = d.getHours() < 10 ? `0${d.getHours()}` : `${d.getHours()}`
    const m = d.getMinutes() < 10 ? `0${d.getMinutes()}` : `${d.getMinutes()}`
    return `${h}:${m}`
  }

  private todayKey(): string {
    const d = new Date()
    const m = d.getMonth() + 1
    const day = d.getDate()
    return `${d.getFullYear()}-${m < 10 ? '0' : ''}${m}-${day < 10 ? '0' : ''}${day}`
  }

  private dueText(task: TaskBrief): string {
    if (task.is_overdue) {
      return `逾期 ${task.overdue_days ?? 0} 天`
    }
    if (task.due_at === null || task.due_at.length < 10) {
      return '无截止时间'
    }
    const datePart = task.due_at.substring(0, 10)
    const month = Number(datePart.substring(5, 7))
    const day = Number(datePart.substring(8, 10))
    if (datePart === this.todayKey() && task.due_at.length >= 16) {
      return `今天 ${task.due_at.substring(11, 16)}`
    }
    return `${month}-${day} 截止`
  }

  private ownerText(task: TaskBrief): string {
    const dept = task.dept?.name ?? '未分配部门'
    const owner = task.owner?.name ?? '未指派'
    return `${dept} · 负责人 ${owner}`
  }

  private roleLabel(role: string | null | undefined): string {
    if (role === 'president') return '会长'
    if (role === 'vice_president') return '副会长'
    if (role === 'lead') return '部长'
    if (role === 'vice_lead') return '副部长'
    if (role === 'member') return '成员'
    return '未分配'
  }

  private currentUserLine(): string {
    const user = this.permissionStore.userInfo
    if (user === null) return ''
    const dept = user.dept?.name ?? '未分配部门'
    return `${user.name} · ${dept} · ${this.roleLabel(user.role)}`
  }

  @Builder
  header() {
    Column({ space: 2 }) {
      Text('我的任务')
        .fontSize(FontSize.headline)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.textPrimary)
      if (this.currentUserLine().length > 0) {
        Text(this.currentUserLine())
          .fontSize(FontSize.caption)
          .fontColor(Color.textTertiary)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  statCell(value: number, label: string, color: string) {
    Column({ space: 2 }) {
      Text(`${value}`)
        .fontSize(FontSize.numL)
        .fontWeight(FontWeight.Bold)
        .fontFamily('Inter')
        .fontFeature('"tnum" 1')
        .fontColor(color)
      Text(label)
        .fontSize(FontSize.micro)
        .fontColor(Color.textTertiary)
    }
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  statsBar() {
    Row() {
      Row({ space: 22 }) {
        this.statCell(this.myTasks.counts.overdue, '逾期', StatusColor.overdue.fg)
        this.statCell(this.myTasks.counts.blocked, '阻塞', StatusColor.blocked.fg)
        this.statCell(this.myTasks.counts.open_total, '未完成', Color.primary)
      }
      Blank()
      Column({ space: 2 }) {
        Text('下拉刷新')
          .fontSize(FontSize.micro)
          .fontColor(Color.textTertiary)
        Text(`${this.syncedAt} 已同步`)
          .fontSize(FontSize.micro)
          .fontFamily('Inter')
          .fontFeature('"tnum" 1')
          .fontColor(Color.textTertiary)
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .height(76)
    .padding({ left: 16, right: 16 })
    .backgroundColor(Color.surface)
    .border({ width: 1, color: Color.divider })
    .borderRadius(Radius.card)
    .shadow(Shadow.L2)
    .onClick(() => {
      this.load()
    })
  }

  @Builder
  sectionHeader(title: string, belowHint: string, rightHint: string) {
    Column({ space: 4 }) {
      Row() {
        Text(title)
          .fontSize(FontSize.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.textPrimary)
        Blank()
        if (rightHint.length > 0) {
          Text(rightHint)
            .fontSize(FontSize.micro)
            .fontColor(Color.textTertiary)
        }
      }
      .width('100%')
      if (belowHint.length > 0) {
        Text(belowHint)
          .fontSize(FontSize.micro)
          .fontColor(Color.textTertiary)
          .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 2, right: 2 })
  }

  @Builder
  taskRow(task: TaskBrief) {
    Column({ space: 6 }) {
      Row() {
        Text(task.title)
          .fontSize(FontSize.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(task.is_overdue ? StatusColor.overdue.fg : Color.textPrimary)
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        StatusChip({ status: task.status, isOverdue: task.is_overdue })
          .margin({ left: Space.sm })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Row() {
        Text(this.ownerText(task))
          .fontSize(FontSize.micro)
          .fontColor(Color.textTertiary)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.dueText(task))
          .fontSize(FontSize.micro)
          .fontWeight(task.is_overdue ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(task.is_overdue ? StatusColor.overdue.fg : Color.textSecondary)
          .margin({ left: Space.sm })
      }
      .width('100%')

      if (task.status === 'blocked' && task.blocker !== undefined && task.blocker !== null && task.blocker.length > 0) {
        Column({ space: 2 }) {
          Text('阻塞原因（进入 blocked 必填）')
            .fontSize(FontSize.micro)
            .fontWeight(FontWeight.Medium)
            .fontColor(StatusColor.blocked.fg)
          Text(task.blocker)
            .fontSize(FontSize.micro)
            .fontColor(Color.blockedText)
            .lineHeight(18)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(10)
        .backgroundColor(StatusColor.blocked.bg)
        .borderRadius(9)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(Color.surface)
    .onClick(() => {
      router.pushUrl({ url: 'pages/TaskDetailPage', params: { task_id: task.id } })
    })
  }

  @Builder
  taskList(tasks: TaskBrief[]) {
    Column({ space: 1 }) {
      ForEach(tasks, (task: TaskBrief) => {
        this.taskRow(task)
      }, (task: TaskBrief): string => `${task.id}`)
    }
    .width('100%')
    .backgroundColor(Color.divider)
    .borderRadius(Radius.card)
    .clip(true)
    .border({ width: 1, color: Color.divider })
  }

  @Builder
  emptyRow(text: string) {
    Text(text)
      .width('100%')
      .fontSize(FontSize.caption)
      .fontColor(Color.textTertiary)
      .padding({ left: 14, right: 14, top: 16, bottom: 16 })
      .backgroundColor(Color.surface)
  }

  @Builder
  taskSection(title: string, belowHint: string, rightHint: string, tasks: TaskBrief[]) {
    Column({ space: 8 }) {
      this.sectionHeader(title, belowHint, rightHint)
      if (tasks.length > 0) {
        this.taskList(tasks)
      } else {
        this.emptyRow('这里暂时没有任务。')
      }
    }
    .width('100%')
  }

  @Builder
  statusHint() {
    if (this.loading && this.myTasks.counts.open_total === 0) {
      Row() {
        LoadingProgress().width(28).height(28).color(Color.primary)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: Space.xxl, bottom: Space.xxl })
    } else if (this.errorMsg.length > 0) {
      Column({ space: Space.sm }) {
        Text(this.errorMsg)
          .fontSize(FontSize.caption)
          .fontColor(StatusColor.overdue.fg)
          .width('100%')
          .textAlign(TextAlign.Center)
        Button('重试')
          .height(36)
          .backgroundColor(Color.primary)
          .fontColor(Color.surface)
          .onClick(() => {
            this.load()
          })
      }
      .width('100%')
      .padding({ top: Space.xxl })
    }
  }

  build() {
    Column() {
      Column() {
        this.header()
      }
      .width('100%')
      .padding({ left: Space.page, right: Space.page, top: 16, bottom: 12 })

      Scroll() {
        Column({ space: 20 }) {
          this.statusHint()
          this.statsBar()
          this.taskSection(`已逾期 · ${this.myTasks.overdue.length}`, '距截止已过，请尽快处理', '', this.myTasks.overdue)
          this.taskSection(`阻塞中 · ${this.myTasks.blocked.length}`, '', '阻塞项同时也会出现在下面的时间里', this.myTasks.blocked)
          this.taskSection(`今天到期 · ${this.myTasks.due_today.length}`, '', `本周内还有 ${this.myTasks.due_week.length} 项`, this.myTasks.due_today)
          this.taskSection(`本周内 · ${this.myTasks.due_week.length}`, '', '', this.myTasks.due_week)
          this.taskSection(`以后 · ${this.myTasks.later.length}`, '', '', this.myTasks.later)
          this.taskSection(`无截止时间 · ${this.myTasks.no_due.length}`, '', '', this.myTasks.no_due)
        }
        .width('100%')
        .padding({ left: Space.page, right: Space.page, bottom: 110 })
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.canvas)
  }
}
