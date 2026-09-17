/**
 * 成员卡片 MemberCard（P06 名录 / P07 详情共用）
 * 左：角色色头像圈（姓名首字）· 中：姓名 + 角色 · 右：进入详情的 chevron
 *
 * 设计约束（P06）：
 *   · 名录**不含手机号**（隐私最小化）—— 所以卡片上只有姓名与角色，没有号码；
 *   · 颜色 / 圆角 / 间距一律取自 core/Theme.ets，不在本文件里写死色值；
 *   · 默认只列 active 成员，非 active 的用状态胶囊标出来（复用 Theme 的 memberStatusLabel）。
 */
import { MemberBrief } from '../api/AuthApi'
import { Color, FontSize, Radius, Shadow, Space, memberStatusFg, memberStatusLabel, roleAvatarColor, roleLabel } from '../core/Theme'

@Component
export struct MemberCard {
  @Prop member: MemberBrief
  onCardClick: () => void = () => {}

  build() {
    Row() {
      // ── 头像圈：取姓名首字 ──
      Text(this.initial())
        .fontSize(FontSize.subtitle)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.onPrimary)
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(roleAvatarColor(this.member.role))
        .textAlign(TextAlign.Center)

      // ── 姓名 + 角色 ──
      Column({ space: 2 }) {
        Row() {
          Text(this.member.name)
            .fontSize(FontSize.subtitle)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (this.member.status !== 'active') {
            Text(memberStatusLabel(this.member.status))
              .fontSize(FontSize.micro)
              .fontColor(memberStatusFg(this.member.status))
              .backgroundColor(Color.canvas)
              .borderRadius(Radius.pill)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .margin({ left: Space.sm })
          }
        }
        .width('100%')

        Text(this.deptLine())
          .fontSize(FontSize.caption)
          .fontColor(Color.textTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: Space.md })

      Image($r('app.media.chevron_right'))
        .width(16)
        .height(16)
        .margin({ left: Space.sm })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding(Space.card)
    .backgroundColor(Color.surface)
    .borderRadius(Radius.card)
    .shadow(Shadow.card)
    .onClick(() => {
      this.onCardClick()
    })
  }

  /** 姓名首字；姓名为空时用占位符，避免 substring 越界。 */
  private initial(): string {
    if (this.member.name.length === 0) {
      return '?'
    }
    return this.member.name.substring(0, 1)
  }

  /** 副信息：部门 · 角色（pending 账号 dept 为 null，落到「未分配部门」）。 */
  private deptLine(): string {
    const deptName: string = this.member.dept?.name ?? '未分配部门'
    return `${deptName} · ${roleLabel(this.member.role)}`
  }
}
