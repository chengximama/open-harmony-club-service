// 管理页面
// 包含：部门管理、注册口令、招募链接、危险操作

import { Dept as DeptModel, MOCK_DEPTS } from '../model/MemberModel';
import { Colors, Radius, Spacing, StatusColors } from '../model/Theme';

interface InviteLink {
  id: string;
  dept_name: string;
  url: string;
  enabled: boolean;
  created_at: string;
}

// ====== 假数据 ======
const INVITE_LINKS: InviteLink[] = [
  { id: 'link001', dept_name: '课题部', url: 'club.example.com/join/abc123', enabled: true, created_at: '2026-09-10' },
  { id: 'link002', dept_name: '运营部', url: 'club.example.com/join/def456', enabled: true, created_at: '2026-09-12' },
  { id: 'link003', dept_name: '宣传部', url: 'club.example.com/join/ghi789', enabled: false, created_at: '2026-09-08' },
];

// memberCount 是 UI 衍生数据，后端 Dept 没有这个字段
const DEPT_MEMBER_COUNT: Record<number, number> = { 1: 3, 2: 4, 3: 3, 4: 3 };

@Component
struct SectionHeader {
  title: string = '';
  actionText: string = '';
  onAction: () => void = () => {};

  build() {
    Row() {
      Text(this.title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.textPrimary)

      Blank()

      if (this.actionText.length > 0) {
        Text(this.actionText)
          .fontSize(14)
          .fontColor(Colors.primary)
          .onClick(() => { this.onAction(); })
      }
    }
    .width('100%')
    .padding({ left: Spacing.page, right: Spacing.page, top: Spacing.xl, bottom: Spacing.sm })
  }
}

// ====== 部门管理 ======
@Component
struct DeptManageSection {
  @State depts: DeptModel[] = MOCK_DEPTS;

  build() {
    Column() {
      SectionHeader({
        title: '部门管理',
        actionText: '+ 新建部门',
        onAction: () => {}
      })

      Column() {
        ForEach(this.depts, (dept: DeptModel) => {
          Row() {
            Column() {
              Text(dept.name)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(Colors.textPrimary)
              Text(`${DEPT_MEMBER_COUNT[dept.id] || 0} 人`)
                .fontSize(12)
                .fontColor(Colors.textTertiary)
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Text('编辑')
              .fontSize(14)
              .fontColor(Colors.primary)
              .margin({ right: Spacing.lg })

            Text('删除')
              .fontSize(14)
              .fontColor(StatusColors.overdue.fg)
          }
          .width('100%')
          .padding(Spacing.cardInner)
          .backgroundColor(Colors.surface)
          .margin({ bottom: 1 })
        }, (dept: DeptModel) => dept.id.toString())
      }
      .backgroundColor(Colors.surface)
      .borderRadius(Radius.card)
      .margin({ left: Spacing.page, right: Spacing.page })
    }
    .width('100%')
  }
}

// ====== 注册口令 ======
@Component
struct RegisterConfigSection {
  @State code: string = 'CLUB-2026';
  @State showRotateConfirm: boolean = false;

  build() {
    Column() {
      SectionHeader({ title: '注册口令', actionText: '' })

      Column() {
        Row() {
          Column() {
            Text('当前口令')
              .fontSize(12)
              .fontColor(Colors.textTertiary)
            Text(this.code)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(Colors.primary)
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button('复制')
            .type(ButtonType.Capsule)
            .fontSize(12)
            .height(32)
        }
        .width('100%')
        .padding(16)

        Divider()
          .color(Colors.divider)

        Row() {
          Button('更换口令')
            .layoutWeight(1)
            .backgroundColor(StatusColors.todo.bg)
            .fontColor(Colors.textSecondary)
            .margin({ right: 8 })

          Button('随机轮换')
            .layoutWeight(1)
            .onClick(() => {
              this.showRotateConfirm = true;
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 16 })
      }
      .backgroundColor(Color.White)
      .borderRadius(8)
      .margin({ left: 16, right: 16 })
    }
    .width('100%')
  }
}

// ====== 招募链接 ======
@Component
struct InviteLinkSection {
  @State links: InviteLink[] = INVITE_LINKS;

  toggleEnabled(id: string) {
    const idx = this.links.findIndex(l => l.id === id);
    if (idx >= 0) {
      this.links[idx].enabled = !this.links[idx].enabled;
      this.links = [...this.links];
    }
  }

  build() {
    Column() {
      SectionHeader({
        title: '招募链接',
        actionText: '+ 生成链接',
        onAction: () => {}
      })

      Column() {
        ForEach(this.links, (link: InviteLink) => {
          Column() {
            Row() {
              Text(link.dept_name)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(Colors.textPrimary)

              Blank()

              Text(link.enabled ? '启用中' : '已停用')
                .fontSize(12)
                .fontColor(link.enabled ? StatusColors.done.fg : Colors.textTertiary)
                .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                .backgroundColor(link.enabled ? StatusColors.done.bg : StatusColors.todo.bg)
                .borderRadius(Radius.capsule)
            }
            .width('100%')

            Text(link.url)
              .fontSize(12)
              .fontColor(Colors.primary)
              .margin({ top: 6 })

            Row() {
              Text(`创建于 ${link.created_at}`)
                .fontSize(12)
                .fontColor(Colors.textTertiary)

              Blank()

              Text(link.enabled ? '停用' : '启用')
                .fontSize(12)
                .fontColor(link.enabled ? StatusColors.overdue.fg : StatusColors.done.fg)
                .onClick(() => { this.toggleEnabled(link.id); })
            }
            .width('100%')
            .margin({ top: 8 })
          }
          .width('100%')
          .padding(Spacing.cardInner)
          .margin({ bottom: 1 })
        }, (link: InviteLink) => link.id)
      }
      .backgroundColor(Colors.surface)
      .borderRadius(Radius.card)
      .margin({ left: Spacing.page, right: Spacing.page })
    }
    .width('100%')
  }
}

// ====== 危险操作区 ======
@Component
struct DangerZoneSection {
  @State showTransferConfirm: boolean = false;
  @State showResetPasswordConfirm: boolean = false;

  build() {
    Column() {
      SectionHeader({ title: '危险操作', actionText: '' })

      Column() {
        // 移交会长
        Row() {
          Column() {
            Text('移交会长')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Colors.textPrimary)
            Text('将会长权限转让给另一位成员')
              .fontSize(12)
              .fontColor(Colors.textTertiary)
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Text('>')
            .fontSize(18)
            .fontColor(Colors.textTertiary)
        }
        .width('100%')
        .padding(Spacing.cardInner)
        .onClick(() => {
          this.showTransferConfirm = true;
        })

        Divider().color(Colors.divider).margin({ left: Spacing.lg })

        // 重置密码
        Row() {
          Column() {
            Text('重置成员密码')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Colors.textPrimary)
            Text('为成员生成一次性临时密码')
              .fontSize(12)
              .fontColor(Colors.textTertiary)
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Text('>')
            .fontSize(18)
            .fontColor(Colors.textTertiary)
        }
        .width('100%')
        .padding(Spacing.cardInner)
        .onClick(() => {
          this.showResetPasswordConfirm = true;
        })
      }
      .backgroundColor(Colors.surface)
      .borderRadius(Radius.card)
      .margin({ left: Spacing.page, right: Spacing.page })
    }
    .width('100%')
  }
}

@Component
export default struct ManagePage {
  @State currentTab: number = 0;

  build() {
    Column() {
      // 顶部 Tab 切换
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
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(Colors.textPrimary)
              .margin({ top: Spacing.xl })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }
        .tabBar('部门')

        TabContent() {
          Column() {
            Text('成员管理（独立页）')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(Colors.textPrimary)
              .margin({ top: Spacing.xl })
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
    .backgroundColor(Colors.canvas)
  }
}
