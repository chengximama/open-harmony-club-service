/**
 * pending 账号唯一落地页。只提供手动刷新状态与退出登录。
 */
import { promptAction } from '@kit.ArkUI';
import { AuthApi } from '../api/AuthApi';
import { Color, FontSize, Radius, Shadow, Space, StatusColor } from '../core/Theme';
import { PermissionStore, UpdateData } from '../store/PermissionStore';
import { SessionStore } from '../store/SessionStore';
import { replaceTo } from '../utils/RouterUtils';

@Entry
@Component
struct PendingPage {
  @State phone: string = '';
  @State loading: boolean = false;
  @State errorMsg: string = '';

  private authApi: AuthApi = new AuthApi();
  private permissionStore: PermissionStore = PermissionStore.getInstance();

  aboutToAppear(): void {
    this.phone = this.permissionStore.userInfo?.phone ?? '';
    this.refreshStatus(false);
  }

  build() {
    Column() {
      Column() {
        Stack() {
          Circle()
            .width(96)
            .height(96)
            .fill(StatusColor.pending.bg)

          Image($r('app.media.clock_pending'))
            .width(44)
            .height(44)
        }
        .width(96)
        .height(96)
        .margin({ bottom: 32 })

        Text('等待管理员分配')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.textPrimary)
          .margin({ bottom: 12 })

        Text('账号已注册成功，但还没有被分配部门与角色。\n此时 permissions 全部为 false、view_scope = none，所以不能进入主界面。')
          .fontSize(FontSize.body)
          .fontColor(Color.textSecondary)
          .textAlign(TextAlign.Center)
          .lineHeight(22)
          .constraintSize({ maxWidth: 280 })

        Column({ space: 12 }) {
          Text('接下来会发生什么')
            .width('100%')
            .fontSize(FontSize.body)
            .fontWeight(600)
            .fontColor(Color.textPrimary)

          this.stepRow(Color.primary, '把姓名告诉会长或副会长。')
          this.stepRow(Color.primary, '他们在「管理 · 待分配审批」里为你分配部门与角色。')
          this.stepRow(StatusColor.done.fg, '分配生效后重新登录，首页「我的任务」就会出现在你面前。')
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 16 })
        .backgroundColor(Color.surface)
        .border({ width: 1, color: Color.divider })
        .borderRadius(16)
        .shadow(Shadow.L1)
        .alignItems(HorizontalAlign.Start)
        .margin({ top: 24 })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Column({ space: 10 }) {
        Row() {
          Text('注册手机号')
            .fontSize(FontSize.body)
            .fontColor(Color.textTertiary)
          Blank()
          Text(this.maskPhone(this.phone))
            .fontSize(FontSize.body)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.textPrimary)
            .fontFamily('Inter')
            .fontFeature('"tnum" 1')
        }
        .width('100%')

        Divider()
          .color(Color.divider)

        Row() {
          Text('账号状态')
            .fontSize(FontSize.body)
            .fontColor(Color.textTertiary)
          Blank()
          Text('待分配')
            .fontSize(FontSize.body)
            .fontWeight(FontWeight.Medium)
            .fontColor(StatusColor.pending.fg)
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .backgroundColor(Color.surface)
      .border({ width: 1, color: Color.divider })
      .borderRadius(16)
      .margin({ bottom: 16 })

      if (this.errorMsg.length > 0) {
        Text(this.errorMsg)
          .width('100%')
          .fontSize(FontSize.caption)
          .fontColor(Color.danger)
          .textAlign(TextAlign.Center)
          .margin({ bottom: 12 })
      }

      Button(this.loading ? '刷新中…' : '刷新状态')
        .width('100%')
        .height(52)
        .fontSize(FontSize.subtitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.onPrimary)
        .backgroundColor(Color.primary)
        .borderRadius(Radius.button)
        .shadow(Shadow.primary)
        .enabled(!this.loading)
        .onClick(() => this.refreshStatus(true))
        .margin({ bottom: 12 })

      Text('退出登录')
        .width('100%')
        .fontSize(FontSize.body)
        .fontColor(Color.textTertiary)
        .textAlign(TextAlign.Center)
        .padding({ top: 4, bottom: 4 })
        .onClick(() => this.handleLogout())
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, bottom: 32 })
    .backgroundColor(Color.surface)
  }

  @Builder
  stepRow(color: string, text: string) {
    Row({ space: 12 }) {
      Circle()
        .width(8)
        .height(8)
        .fill(color)
        .margin({ top: 7 })
      Text(text)
        .layoutWeight(1)
        .fontSize(FontSize.body)
        .fontColor(Color.textSecondary)
        .lineHeight(22)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }
  private maskPhone(phone: string): string {
    if (phone.length === 11) {
      return `${phone.substring(0, 3)}****${phone.substring(7)}`;
    }
    return phone.length > 0 ? phone : '未获取';
  }

  async refreshStatus(showResult: boolean): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    const response = await this.authApi.me();
    if (response.ok && response.data !== undefined) {
      const update: UpdateData = {
        user: response.data.member,
        permissions: response.data.permissions,
      };
      this.permissionStore.update(update);
      this.phone = response.data.member.phone;
      if (response.data.member.status === 'active' && response.data.permissions.view_scope !== 'none') {
        if (showResult) {
          promptAction.showToast({ message: '已分配，正在进入…', duration: 2000 });
        }
        replaceTo('pages/Index');
      } else if (showResult) {
        promptAction.showToast({ message: '还没有被分配，请稍后再试', duration: 2000 });
      }
    } else {
      this.errorMsg = response.error?.message ?? '刷新失败，请稍后再试';
    }
    this.loading = false;
  }

  async handleLogout(): Promise<void> {
    await this.authApi.logout();
    await SessionStore.clearAll();
    replaceTo('pages/LoginPage');
  }
}
