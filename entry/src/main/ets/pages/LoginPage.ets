/**
 * 登录页：手机号 + 密码 → token → /auth/me → 按账号状态分流。
 */
import { AuthApi, LoginRequest } from '../api/AuthApi';
import { FormField } from '../components/FormField';
import { Color, FontSize, Radius, Shadow, Space } from '../core/Theme';
import { TokenStore } from '../store/TokenStore';
import { PermissionStore, UpdateData } from '../store/PermissionStore';
import { pushTo, replaceTo } from '../utils/RouterUtils';

@Entry
@Component
struct LoginPage {
  @State phone: string = '';
  @State password: string = '';
  @State loading: boolean = false;
  @State phoneError: string = '';
  @State passwordError: string = '';
  @State errorMsg: string = '';
  @State backoffSeconds: number = 0;

  private authApi: AuthApi = new AuthApi();
  private tokenStore: TokenStore = TokenStore.getInstance();
  private permissionStore: PermissionStore = PermissionStore.getInstance();
  private backoffTimer: number = -1;

  aboutToDisappear(): void {
    this.stopBackoff();
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          Column() {
            Image($r('app.media.app_logo'))
              .width(64)
              .height(64)
              .shadow(Shadow.primary)

            Text('社团管理工具')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.textPrimary)
              .margin({ top: 20 })

            Text('登录后查看你负责的每一件事')
              .fontSize(FontSize.body)
              .fontColor(Color.textTertiary)
              .margin({ top: 4 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ left: Space.page, right: Space.page, top: 48, bottom: 32 })

          Column({ space: 16 }) {
            FormField({
              fieldLabel: '手机号',
              placeholder: '请输入 11 位手机号',
              inputValue: $phone,
              errorText: this.phoneError,
              numeric: true,
              maxLength: 11
            })
            FormField({
              fieldLabel: '密码',
              placeholder: '请输入密码',
              inputValue: $password,
              errorText: this.passwordError,
              isPassword: true,
              maxLength: 32
            })
          }
          .width('100%')

          if (this.errorMsg.length > 0) {
            Text(this.errorMsg)
              .width('100%')
              .fontSize(FontSize.caption)
              .fontColor(Color.danger)
              .padding({ left: Space.page, right: Space.page, top: 12 })
          }

          Button(this.buttonText())
            .width('100%')
            .height(52)
            .fontSize(FontSize.subtitle)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.onPrimary)
            .backgroundColor(Color.primary)
            .borderRadius(Radius.button)
            .shadow(Shadow.primary)
            .enabled(!this.loading && this.backoffSeconds === 0)
            .opacity(this.loading || this.backoffSeconds > 0 ? 0.65 : 1)
            .onClick(() => {
              if (!this.loading && this.backoffSeconds === 0) {
                this.handleLogin();
              }
            })
            .margin({ left: Space.page, right: Space.page, top: 8 })

          Row({ space: 4 }) {
            Text('还没有账号？')
              .fontSize(FontSize.body)
              .fontColor(Color.textTertiary)
            Text('用注册口令加入')
              .fontSize(FontSize.body)
              .fontColor(Color.primary)
              .fontWeight(FontWeight.Medium)
              .onClick(() => {
                pushTo('pages/RegisterPage');
              })
          }
          .justifyContent(FlexAlign.Center)
          .width('100%')
          .padding({ top: 4 })

          Column({ space: 12 }) {
            Text('忘记密码？请联系会长或副会长在管理页为你重置——v1 不做短信或邮箱自助找回。')
              .width('100%')
              .fontSize(FontSize.caption)
              .fontColor(Color.textTertiary)
              .textAlign(TextAlign.Center)

            Text('服务端为自签 HTTPS，首次使用需在 App 内信任内置 CA 证书。')
              .width('100%')
              .fontSize(FontSize.caption)
              .fontColor(Color.textDisabled)
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .padding({ left: Space.page, right: Space.page, top: 24, bottom: 32 })
        }
        .width('100%')
        .padding({ left: 8, right: 8 })
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.surface)
  }
  private buttonText(): string {
    if (this.loading) return '登录中…';
    if (this.backoffSeconds > 0) return `请稍后再试 (${this.backoffSeconds})`;
    return '登录';
  }

  private startBackoff(): void {
    this.stopBackoff();
    this.backoffSeconds = 30;
    this.backoffTimer = setInterval(() => {
      if (this.backoffSeconds <= 1) {
        this.backoffSeconds = 0;
        this.stopBackoff();
      } else {
        this.backoffSeconds -= 1;
      }
    }, 1000);
  }

  private stopBackoff(): void {
    if (this.backoffTimer !== -1) {
      clearInterval(this.backoffTimer);
      this.backoffTimer = -1;
    }
  }

  private routeAfterAuth(status: string, viewScope: string): void {
    if (status === 'pending' || viewScope === 'none') {
      replaceTo('pages/PendingPage');
    } else {
      replaceTo('pages/Index');
    }
  }

  async handleLogin(): Promise<void> {
    this.phoneError = '';
    this.passwordError = '';
    this.errorMsg = '';
    let valid = true;
    if (!/^\d{11}$/.test(this.phone)) {
      this.phoneError = '请输入正确的手机号';
      valid = false;
    }
    if (this.password.length === 0) {
      this.passwordError = '请输入密码';
      valid = false;
    }
    if (!valid) {
      return;
    }

    this.loading = true;
    try {
      const request: LoginRequest = { phone: this.phone, password: this.password };
      const loginResp = await this.authApi.login(request);
      if (!loginResp.ok || loginResp.data === undefined) {
        this.errorMsg = loginResp.error?.message ?? '登录失败，请稍后重试';
        if (loginResp.error?.code === 'TOO_MANY_ATTEMPTS') {
          this.startBackoff();
        }
        return;
      }

      await this.tokenStore.setToken(loginResp.data.token);
      const meResp = await this.authApi.me();
      if (!meResp.ok || meResp.data === undefined) {
        this.errorMsg = meResp.error?.message ?? '登录状态校验失败，请重试';
        return;
      }

      const update: UpdateData = {
        user: meResp.data.member,
        permissions: meResp.data.permissions,
      };
      this.permissionStore.update(update);
      this.routeAfterAuth(meResp.data.member.status, meResp.data.permissions.view_scope);
    } catch (_) {
      this.errorMsg = '网络不可用，请检查服务端是否可访问';
    } finally {
      this.loading = false;
    }
  }
}
