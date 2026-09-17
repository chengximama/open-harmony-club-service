/**
 * 加入社团：注册口令 + 手机号 + 姓名 + 密码。
 */
import { router } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import { AuthApi, DeptBrief, RegisterRequest } from '../api/AuthApi';
import { FormField } from '../components/FormField';
import { Color, FontSize, Radius, Shadow, Space } from '../core/Theme';
import { TokenStore } from '../store/TokenStore';
import { PermissionStore, UpdateData } from '../store/PermissionStore';
import { genClientToken } from '../util/ClientToken';
import { backPage, replaceTo } from '../utils/RouterUtils';

interface RegisterRouteParams {
  invite_token?: string;
  dept_hint?: string;
}

@Entry
@Component
struct RegisterPage {
  @State code: string = '';
  @State phone: string = '';
  @State name: string = '';
  @State password: string = '';
  @State loading: boolean = false;
  @State codeError: string = '';
  @State phoneError: string = '';
  @State nameError: string = '';
  @State passwordError: string = '';
  @State formError: string = '';
  @State backoffSeconds: number = 0;
  @State inviteToken: string = '';
  @State deptHint: DeptBrief | null = null;

  private authApi: AuthApi = new AuthApi();
  private tokenStore: TokenStore = TokenStore.getInstance();
  private permissionStore: PermissionStore = PermissionStore.getInstance();
  private clientToken: string = genClientToken();
  private backoffTimer: number = -1;

  aboutToAppear(): void {
    const params = router.getParams() as RegisterRouteParams;
    if (params !== undefined && params !== null && params.invite_token !== undefined && params.invite_token.length > 0) {
      this.inviteToken = params.invite_token;
      this.loadInvitePreview();
    }
  }

  aboutToDisappear(): void {
    this.stopBackoff();
  }

  build() {
    Column() {
      Column() {
        Row({ space: 4 }) {
          Image($r('app.media.chevron_left'))
            .width(18)
            .height(18)
            .onClick(() => backPage())
          Text('加入社团')
            .fontSize(FontSize.body)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.primary)
            .onClick(() => backPage())
        }
        .width('100%')
        .height(44)
        .padding({ left: Space.page, right: Space.page })
        .alignItems(VerticalAlign.Center)

        Divider()
          .color(Color.divider)
      }
      .width('100%')

      Scroll() {
        Column({ space: 16 }) {
          Text('注册口令由会长发放；通过招募链接进入只会预填部门，不赋予任何角色。')
            .width('100%')
            .fontSize(FontSize.body)
            .fontColor(Color.textSecondary)
            .padding(12)
            .backgroundColor(Color.primarySoft)
            .border({ width: 1, color: Color.primaryBorder })
            .borderRadius(Radius.button)
            .margin({ left: Space.page, right: Space.page })

          FormField({
            fieldLabel: '注册口令',
            placeholder: '请输入会长发放的注册口令',
            inputValue: $code,
            errorText: this.codeError,
            maxLength: 32
          })

          FormField({
            fieldLabel: '手机号',
            placeholder: '请输入 11 位手机号',
            inputValue: $phone,
            errorText: this.phoneError,
            numeric: true,
            maxLength: 11
          })

          FormField({
            fieldLabel: '姓名',
            placeholder: '请输入真实姓名，方便会长识别',
            inputValue: $name,
            errorText: this.nameError,
            maxLength: 32
          })

          FormField({
            fieldLabel: '密码',
            placeholder: '请设置密码',
            inputValue: $password,
            errorText: this.passwordError,
            hint: '长度按字节计：8–32 字节，仅数字、英文或符号。',
            isPassword: true,
            maxLength: 32
          })

          if (this.deptHint !== null) {
            Text(`来自于招募链接的部门预填：${this.deptHint.name}。它只是 dept_hint，审批前不生效。`)
              .width('100%')
              .fontSize(FontSize.body)
              .fontColor(Color.primary)
              .padding(12)
              .backgroundColor(Color.primarySoft)
              .border({ width: 1, color: Color.primaryBorder })
              .borderRadius(Radius.button)
              .margin({ left: Space.page, right: Space.page })
          }

          if (this.formError.length > 0) {
            Text(this.formError)
              .width('100%')
              .fontSize(FontSize.caption)
              .fontColor(Color.danger)
              .padding({ left: Space.page, right: Space.page })
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
                this.handleRegister();
              }
            })
            .margin({ left: Space.page, right: Space.page })

          Text('注册成功即返回 token，但账号是「待分配」、零权限——会被落在「等待管理员分配」页，而不是主界面。')
            .width('100%')
            .fontSize(FontSize.caption)
            .fontColor(Color.textTertiary)
            .textAlign(TextAlign.Center)
            .padding({ left: Space.page, right: Space.page })

          Text('连续输错口令会返回 429 TOO_MANY_ATTEMPTS，节流按客户端 IP，不影响他人，也不影响登录。')
            .width('100%')
            .fontSize(FontSize.caption)
            .fontColor(Color.textTertiary)
            .textAlign(TextAlign.Center)
            .padding({ left: Space.page, right: Space.page, bottom: 24 })
        }
        .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.surface)
  }

  private buttonText(): string {
    if (this.loading) return '提交中…';
    if (this.backoffSeconds > 0) return `请稍后再试 (${this.backoffSeconds})`;
    return '提交申请';
  }

  private async loadInvitePreview(): Promise<void> {
    const response = await this.authApi.previewInvite(this.inviteToken);
    if (response.ok && response.data !== undefined && response.data.enabled && response.data.dept !== null) {
      this.deptHint = response.data.dept;
    }
  }

  private isPasswordValid(value: string): boolean {
    const bytes: number = new util.TextEncoder().encodeInto(value).length;
    if (bytes < 8 || bytes > 32) {
      return false;
    }
    for (let i = 0; i < value.length; i++) {
      const code: number = value.charCodeAt(i);
      if (code < 0x21 || code > 0x7E) {
        return false;
      }
    }
    return true;
  }

  private clearErrors(): void {
    this.codeError = '';
    this.phoneError = '';
    this.nameError = '';
    this.passwordError = '';
    this.formError = '';
  }

  private validate(): boolean {
    this.clearErrors();
    let valid = true;
    if (this.code.length < 6 || this.code.length > 32) {
      this.codeError = '注册口令需为 6–32 位';
      valid = false;
    }
    if (!/^\d{11}$/.test(this.phone)) {
      this.phoneError = '请输入正确的手机号';
      valid = false;
    }
    if (this.name.length === 0 || this.name.length > 32) {
      this.nameError = '姓名不能为空且不能超过 32 个字符';
      valid = false;
    }
    if (!this.isPasswordValid(this.password)) {
      this.passwordError = '密码需为 8–32 字节，且仅含数字、英文或符号';
      valid = false;
    }
    return valid;
  }

  private applyServerFields(fields?: Record<string, string>): void {
    if (fields === undefined) return;
    if (fields['register_code'] !== undefined) this.codeError = fields['register_code'];
    if (fields['phone'] !== undefined) this.phoneError = fields['phone'];
    if (fields['name'] !== undefined) this.nameError = fields['name'];
    if (fields['password'] !== undefined) this.passwordError = fields['password'];
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

  async handleRegister(): Promise<void> {
    if (!this.validate()) return;
    this.loading = true;
    try {
      const request: RegisterRequest = {
        register_code: this.code,
        phone: this.phone,
        name: this.name,
        password: this.password,
        client_token: this.clientToken,
      };
      if (this.inviteToken.length > 0) {
        request.invite_token = this.inviteToken;
      }

      const response = await this.authApi.register(request);
      if (!response.ok || response.data === undefined) {
        const code = response.error?.code ?? '';
        if (code === 'REGISTER_CODE_INVALID') {
          this.codeError = '注册口令不正确';
        } else if (code === 'ALREADY_EXISTS') {
          this.phoneError = '已存在同名或同手机号的账号';
        } else {
          this.applyServerFields(response.error?.fields);
          this.formError = response.error?.message ?? '注册失败，请稍后重试';
        }
        if (code === 'TOO_MANY_ATTEMPTS') {
          this.startBackoff();
        }
        return;
      }

      await this.tokenStore.setToken(response.data.token);
      const update: UpdateData = {
        user: response.data.member,
        permissions: response.data.permissions,
      };
      this.permissionStore.update(update);
      replaceTo('pages/PendingPage');
    } catch (_) {
      this.formError = '网络不可用，请检查服务端是否可访问';
    } finally {
      this.loading = false;
    }
  }
}
