import ManagePage from './ManagePage';
import { can, PermissionStore } from '../store/PermissionStore';
import { Color, FontSize, Space } from '../core/Theme';
import { backPage, replaceTo } from '../utils/RouterUtils';

@Entry
@Component
struct AdminPage {
  aboutToAppear(): void {
    const current = PermissionStore.getInstance().userInfo;
    const allowed = can(current, 'ManageDepts') || can(current, 'ViewRegisterCode') ||
      can(current, 'ChangeRegisterCode') || can(current, 'ManageInviteLinks') ||
      can(current, 'TransferPresidency');
    if (!allowed) {
      replaceTo('pages/Index');
    }
  }

  build() {
    Column() {
      Row() {
        Row({ space: 4 }) {
          Image($r('app.media.icon_chevron_left_primary'))
            .width(18)
            .height(18)

          Text('管理')
            .fontSize(FontSize.body)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.primary)
        }
        .height('100%')
        .onClick(() => backPage())

        Blank()

        Image($r('app.media.icon_more'))
          .width(20)
          .height(20)
      }
      .width('100%')
      .height(52)
      .padding({ left: Space.page, right: Space.page })
      .alignItems(VerticalAlign.Center)
      .backgroundColor(Color.surface)

      Divider()
        .strokeWidth(1)
        .color(Color.divider)

      Column() {
        ManagePage()
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.canvas)
  }
}