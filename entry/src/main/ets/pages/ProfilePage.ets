/**
 * 我的：身份、权限、管理入口、改密码与 Outbox。
 */
import { promptAction } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import { AuthApi, ChangePasswordRequest, MemberSelf, UserPermissions } from '../api/AuthApi';
import { FormField } from '../components/FormField';
import { Color, FontSize, Radius, Shadow, Space, StatusColor } from '../core/Theme';
import { can } from '../store/PermissionStore';
import { PermissionStore, UpdateData } from '../store/PermissionStore';
import { OutboxItem, OutboxStore } from '../store/OutboxStore';
import { OutboxSync, OutboxSyncResult } from '../store/OutboxSync';
import { SessionStore } from '../store/SessionStore';
import { pushTo, replaceTo } from '../utils/RouterUtils';

interface PermissionDisplay {
  name: string;
  desc: string;
  value: string;
  ok: boolean;
}

@Component
export struct ProfilePage {
  @Prop @Watch('onRefreshSignal') refreshSignal: number = 0;
  @State user: MemberSelf | null = null;
  @State permissions: UserPermissions | null = null;
  @State loading: boolean = false;
  @State errorMsg: string = '';

  @State outboxCount: number = 0;
  @State outboxItems: OutboxItem[] = [];
  @State showOutbox: boolean = false;
  @State syncingOutbox: boolean = false;

  @State showPasswordSheet: boolean = false;
  @State oldPassword: string = '';
  @State newPassword: string = '';
  @State confirmPassword: string = '';
  @State oldPasswordError: string = '';
  @State newPasswordError: string = '';
  @State confirmPasswordError: string = '';
  @State passwordError: string = '';
  @State changingPassword: boolean = false;

  private authApi: AuthApi = new AuthApi();
  private permissionStore: PermissionStore = PermissionStore.getInstance();
  private outboxStore: OutboxStore = OutboxStore.getInstance();

  aboutToAppear(): void {
    this.refreshPage();
  }

  onRefreshSignal(): void {
    this.refreshPage();
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Text('我的')
            .width('100%')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.textPrimary)
        }
        .width('100%')
        .height(52)
        .padding({ left: Space.page, right: Space.page })
        .alignItems(VerticalAlign.Center)
        .backgroundColor(Color.surface)

        Divider()
          .strokeWidth(1)
          .color(Color.divider)

        Scroll() {
          Column({ space: 12 }) {
            this.profileCard()

            if (this.errorMsg.length > 0) {
              Text(this.errorMsg)
                .width('100%')
                .fontSize(FontSize.caption)
                .fontColor(Color.danger)
                .textAlign(TextAlign.Center)
            }

            this.permissionCard()
            this.managementCard()
            this.settingsCard()

            Button('退出登录')
              .width('100%')
              .height(46)
              .fontSize(FontSize.body)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.danger)
              .backgroundColor(Color.surface)
              .border({ width: 1, color: Color.dangerBorder })
              .borderRadius(Radius.button)
              .onClick(() => this.confirmLogout())
          }
          .width('100%')
          .padding({ left: Space.page, right: Space.page, top: 12, bottom: 24 })
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.canvas)

      if (this.showPasswordSheet) {
        this.passwordSheet()
      }
      if (this.showOutbox) {
        this.outboxSheet()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  profileCard() {
    Row({ space: 14 }) {
      Column() {
        Image($r('app.media.icon_person'))
          .width(28)
          .height(28)
      }
      .width(56)
      .height(56)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(Color.primarySoft)
      .borderRadius(28)

      Column({ space: 4 }) {
        Text(this.user?.name ?? '未登录')
          .fontSize(FontSize.title)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.textPrimary)

        Text(this.maskPhone(this.user?.phone ?? ''))
          .fontSize(FontSize.body)
          .fontFamily('Inter')
          .fontFeature('"tnum" 1')
          .fontColor(Color.textTertiary)

        Row({ space: 6 }) {
          Text(this.user?.dept?.name ?? '未分配')
            .fontSize(FontSize.caption)
            .fontWeight(FontWeight.Medium)
            .fontColor(StatusColor.done.fg)
            .padding({ left: 9, right: 9, top: 3, bottom: 3 })
            .backgroundColor(StatusColor.done.bg)
            .borderRadius(Radius.pill)

          Text(this.roleLabel(this.user?.role ?? ''))
            .fontSize(FontSize.caption)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.textSecondary)
            .padding({ left: 9, right: 9, top: 3, bottom: 3 })
            .backgroundColor(StatusColor.todo.bg)
            .borderRadius(Radius.pill)
        }
        .margin({ top: 1 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Color.surface)
    .border({ width: 1, color: Color.divider })
    .borderRadius(Radius.card)
    .shadow(Shadow.L1)
  }

  @Builder
  permissionCard() {
    Column() {
      Text('我的权限 · 由 GET /auth/me 下发')
        .width('100%')
        .fontSize(FontSize.body)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.textPrimary)

      Text('客户端读它只为了画界面，绝不替代服务端校验。')
        .width('100%')
        .fontSize(FontSize.caption)
        .fontColor(Color.textTertiary)
        .margin({ top: 4 })

      Divider()
        .strokeWidth(1)
        .color(Color.divider)
        .margin({ top: 10 })

      ForEach(this.permissionRows(), (item: PermissionDisplay, index: number) => {
        if (index > 0) {
          Divider()
            .strokeWidth(1)
            .color(Color.divider)
        }

        Row({ space: 8 }) {
          Text(`${item.name} · ${item.desc}`)
            .layoutWeight(1)
            .fontSize(FontSize.body)
            .fontColor(Color.textSecondary)

          Row({ space: 6 }) {
            Text(item.value)
              .fontSize(FontSize.body)
              .fontWeight(FontWeight.Medium)
              .fontColor(item.ok ? Color.textSecondary : Color.textTertiary)

            Image(item.ok ? $r('app.media.icon_check') : $r('app.media.icon_cross'))
              .width(16)
              .height(16)
          }
        }
        .width('100%')
        .padding({ top: 9, bottom: 9 })
      }, (item: PermissionDisplay): string => item.name)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Color.surface)
    .border({ width: 1, color: Color.divider })
    .borderRadius(Radius.card)
    .shadow(Shadow.L1)
  }

  @Builder
  managementCard() {
    if (this.canManageMembers() || this.canOpenManage()) {
      Column() {
        if (this.canManageMembers()) {
          this.entryRow('待分配审批', 'pages/ApprovePage')
        }

        if (this.canManageMembers() && this.canOpenManage()) {
          Divider()
            .strokeWidth(1)
            .color(Color.divider)
        }

        if (this.canOpenManage()) {
          this.entryRow('管理 · 部门 / 口令 / 链接 / 成员', 'pages/AdminPage')
        }
      }
      .width('100%')
      .backgroundColor(Color.surface)
      .border({ width: 1, color: Color.divider })
      .borderRadius(Radius.card)
      .shadow(Shadow.L1)
    }
  }

  @Builder
  settingsCard() {
    Column() {
      Row() {
        Text('改密码')
          .fontSize(FontSize.body)
          .fontColor(Color.textPrimary)
        Blank()
        Image($r('app.media.chevron_right'))
          .width(16)
          .height(16)
      }
      .width('100%')
      .height(50)
      .padding({ left: Space.page, right: Space.page })
      .onClick(() => this.openPasswordSheet())

      Divider()
        .strokeWidth(1)
        .color(Color.divider)

      Row() {
        Text('待同步的更改（Outbox）')
          .layoutWeight(1)
          .fontSize(FontSize.body)
          .fontColor(Color.textPrimary)

        Text(this.outboxCount === 0 ? '已同步' : `${this.outboxCount} 条排队中`)
          .fontSize(FontSize.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.outboxCount > 0 ? StatusColor.blocked.fg : Color.textTertiary)

        Image($r('app.media.chevron_right'))
          .width(16)
          .height(16)
          .margin({ left: 6 })
      }
      .width('100%')
      .height(50)
      .padding({ left: Space.page, right: Space.page })
      .onClick(() => this.openOutbox())
    }
    .width('100%')
    .backgroundColor(Color.surface)
    .border({ width: 1, color: Color.divider })
    .borderRadius(Radius.card)
    .shadow(Shadow.L1)
  }

  @Builder
  entryRow(title: string, path: string) {
    Row() {
      Text(title)
        .layoutWeight(1)
        .fontSize(FontSize.body)
        .fontColor(Color.textPrimary)

      Image($r('app.media.chevron_right'))
        .width(16)
        .height(16)
    }
    .width('100%')
    .height(50)
    .padding({ left: Space.page, right: Space.page })
    .onClick(() => pushTo(path))
  }

  @Builder
  passwordSheet() {
    Column() {
      Column({ space: 10 }) {
        Row()
          .width(36)
          .height(4)
          .backgroundColor(Color.divider)
          .borderRadius(2)

        Row() {
          Text('改密码')
            .fontSize(FontSize.title)
            .fontWeight(600)
            .fontColor(Color.textPrimary)
          Blank()
          Text('关闭')
            .fontSize(FontSize.caption)
            .fontColor(Color.textTertiary)
            .onClick(() => {
              if (!this.changingPassword) this.showPasswordSheet = false;
            })
        }
        .width('100%')

        Text('改密后你当前这台设备不受影响，但其它设备的登录会立即失效。')
          .width('100%')
          .fontSize(FontSize.caption)
          .fontColor(Color.textSecondary)

        FormField({
          fieldLabel: '当前密码',
          placeholder: '请输入当前密码',
          inputValue: $oldPassword,
          errorText: this.oldPasswordError,
          isPassword: true,
          maxLength: 32
        })
        FormField({
          fieldLabel: '新密码',
          placeholder: '请输入新密码',
          inputValue: $newPassword,
          errorText: this.newPasswordError,
          hint: '长度 8–32 字节，且仅含数字、英文或符号。',
          isPassword: true,
          maxLength: 32
        })
        FormField({
          fieldLabel: '再次输入新密码',
          placeholder: '请再次输入新密码',
          inputValue: $confirmPassword,
          errorText: this.confirmPasswordError,
          isPassword: true,
          maxLength: 32
        })

        if (this.passwordError.length > 0) {
          Text(this.passwordError)
            .width('100%')
            .fontSize(FontSize.caption)
            .fontColor(Color.danger)
        }

        Text('忘记密码只能由会长/副会长在管理页重置——v1 不做短信或邮箱自助找回。')
          .width('100%')
          .fontSize(FontSize.micro)
          .fontColor(Color.textTertiary)

        Button(this.changingPassword ? '提交中…' : '确认修改')
          .width('100%')
          .height(46)
          .fontSize(15)
          .fontWeight(600)
          .fontColor(Color.onPrimary)
          .backgroundColor(Color.primary)
          .borderRadius(Radius.button)
          .shadow(Shadow.primary)
          .enabled(!this.changingPassword)
          .onClick(() => this.changePassword())
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 24 })
      .backgroundColor(Color.surface)
      .borderRadius({ topLeft: Radius.sheet, topRight: Radius.sheet })
    }
    .width('100%')
    .height('100%')
    .padding({ top: 80 })
    .backgroundColor(Color.overlay)
    .justifyContent(FlexAlign.End)
  }

  @Builder
  outboxSheet() {
    Column() {
      Column({ space: 10 }) {
        Row()
          .width(36)
          .height(4)
          .backgroundColor(Color.divider)
          .borderRadius(2)

        Row() {
          Text(`待同步的更改（${this.outboxCount}）`)
            .fontSize(FontSize.title)
            .fontWeight(600)
            .fontColor(Color.textPrimary)
          Blank()
          Text('关闭')
            .fontSize(FontSize.caption)
            .fontColor(Color.textTertiary)
            .onClick(() => {
              this.showOutbox = false;
            })
        }
        .width('100%')

        if (this.outboxItems.length === 0) {
          Text('没有待同步的更改。')
            .fontSize(FontSize.body)
            .fontColor(Color.textTertiary)
            .padding({ top: 24, bottom: 24 })
        } else {
          List({ space: 8 }) {
            ForEach(this.outboxItems, (item: OutboxItem) => {
              ListItem() {
                Column({ space: 4 }) {
                  Row() {
                    Text(item.label)
                      .fontSize(FontSize.body)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(Color.textPrimary)
                    Blank()
                    Text(`${item.method} ${item.path}`)
                      .fontSize(FontSize.micro)
                      .fontColor(Color.textTertiary)
                  }
                  .width('100%')
                  if (item.last_error.length > 0) {
                    Text(item.last_error)
                      .width('100%')
                      .fontSize(FontSize.micro)
                      .fontColor(Color.danger)
                  }
                  Row() {
                    Blank()
                    Text('丢弃')
                      .fontSize(FontSize.caption)
                      .fontColor(Color.danger)
                      .onClick(() => this.discardOne(item.id))
                  }
                  .width('100%')
                }
                .width('100%')
                .padding(12)
                .backgroundColor(Color.canvas)
                .borderRadius(Radius.input)
              }
            }, (item: OutboxItem): string => item.id)
          }
          .width('100%')
          .height(280)

          Row({ space: 10 }) {
            Button('丢弃全部')
              .layoutWeight(1)
              .height(46)
              .fontSize(FontSize.body)
              .fontColor(Color.danger)
              .backgroundColor(Color.dangerBg)
              .borderRadius(Radius.button)
              .enabled(!this.syncingOutbox)
              .onClick(() => this.discardAll())

            Button(this.syncingOutbox ? '同步中…' : '立即同步')
              .layoutWeight(1)
              .height(46)
              .fontSize(FontSize.body)
              .fontColor(Color.onPrimary)
              .backgroundColor(Color.primary)
              .borderRadius(Radius.button)
              .enabled(!this.syncingOutbox)
              .onClick(() => this.syncOutbox())
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 24 })
      .backgroundColor(Color.surface)
      .borderRadius({ topLeft: Radius.sheet, topRight: Radius.sheet })
    }
    .width('100%')
    .height('100%')
    .padding({ top: 80 })
    .backgroundColor(Color.overlay)
    .justifyContent(FlexAlign.End)
  }

  private async refreshPage(): Promise<void> {
    this.loading = true;
    const response = await this.authApi.me();
    if (response.ok && response.data !== undefined) {
      const update: UpdateData = {
        user: response.data.member,
        permissions: response.data.permissions,
      };
      this.permissionStore.update(update);
      this.user = response.data.member;
      this.permissions = response.data.permissions;
      this.errorMsg = '';
    } else {
      this.errorMsg = response.error?.message ?? '加载失败，请重试';
    }
    await this.loadOutbox();
    this.loading = false;
  }

  private async loadOutbox(): Promise<void> {
    this.outboxItems = await this.outboxStore.list();
    this.outboxCount = this.outboxItems.length;
  }

  private async openOutbox(): Promise<void> {
    await this.loadOutbox();
    this.showOutbox = true;
  }

  private openPasswordSheet(): void {
    this.oldPassword = '';
    this.newPassword = '';
    this.confirmPassword = '';
    this.oldPasswordError = '';
    this.newPasswordError = '';
    this.confirmPasswordError = '';
    this.passwordError = '';
    this.showPasswordSheet = true;
  }

  private canManageMembers(): boolean {
    return can(this.user, 'ManageMembers');
  }

  private canOpenManage(): boolean {
    return can(this.user, 'ManageDepts') || can(this.user, 'ViewRegisterCode') ||
      can(this.user, 'ChangeRegisterCode') || can(this.user, 'ManageInviteLinks') ||
      can(this.user, 'TransferPresidency');
  }

  private permissionRows(): PermissionDisplay[] {
    const permissions = this.permissions;
    if (permissions === null) return [];
    const rows: PermissionDisplay[] = [];
    rows.push({
      name: 'view_scope',
      desc: '可见范围',
      value: this.scopeLabel(permissions.view_scope),
      ok: permissions.view_scope !== 'none',
    });
    rows.push(this.boolRow('manage_members', '审批与成员处置', permissions.manage_members));
    rows.push(this.boolRow('set_role', '分配角色', permissions.set_role));
    rows.push(this.boolRow('create_task', '新建任务', permissions.create_task));
    rows.push(this.boolRow('create_plan', '新建课题', permissions.create_plan));
    rows.push(this.boolRow('update_any_task', '修改他人任务', permissions.update_any_task));
    if (permissions.manage_depts !== undefined) {
      rows.push(this.boolRow('manage_depts', '部门与组织', permissions.manage_depts));
    }
    if (permissions.view_register_code !== undefined) {
      rows.push(this.boolRow('view_register_code', '查看注册口令', permissions.view_register_code));
    }
    if (permissions.change_register_code !== undefined) {
      rows.push(this.boolRow('change_register_code', '更换注册口令', permissions.change_register_code));
    }
    if (permissions.manage_invite_links !== undefined) {
      rows.push(this.boolRow('manage_invite_links', '招募链接管理', permissions.manage_invite_links));
    }
    if (permissions.transfer_presidency !== undefined) {
      rows.push(this.boolRow('transfer_presidency', '会长移交', permissions.transfer_presidency));
    }
    return rows;
  }

  private boolRow(name: string, desc: string, value: boolean): PermissionDisplay {
    return { name: name, desc: desc, value: value ? 'true' : 'false', ok: value };
  }

  private scopeLabel(scope: string): string {
    if (scope === 'all') return 'all · 全社团';
    if (scope === 'dept') return 'dept · 本部门';
    if (scope === 'self') return 'self · 本人';
    return 'none';
  }

  private roleLabel(role: string): string {
    if (role === 'president') return '会长';
    if (role === 'vice_president') return '副会长';
    if (role === 'lead') return '部长';
    if (role === 'vice_lead') return '副部长';
    if (role === 'member') return '成员';
    return '未分配';
  }

  private maskPhone(phone: string): string {
    if (phone.length === 11) return `${phone.substring(0, 3)}****${phone.substring(7)}`;
    return phone.length > 0 ? phone : '未获取';
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

  private validatePassword(): boolean {
    this.oldPasswordError = '';
    this.newPasswordError = '';
    this.confirmPasswordError = '';
    this.passwordError = '';
    let valid = true;
    if (this.oldPassword.length === 0) {
      this.oldPasswordError = '请输入当前密码';
      valid = false;
    }
    if (!this.isPasswordValid(this.newPassword)) {
      this.newPasswordError = '新密码需为 8–32 字节，且仅含数字、英文或符号';
      valid = false;
    }
    if (this.newPassword !== this.confirmPassword) {
      this.confirmPasswordError = '两次输入的新密码不一致';
      valid = false;
    }
    return valid;
  }

  private async changePassword(): Promise<void> {
    if (!this.validatePassword()) return;
    this.changingPassword = true;
    try {
      const request: ChangePasswordRequest = {
        old_password: this.oldPassword,
        new_password: this.newPassword,
      };
      const response = await this.authApi.changePassword(request);
      if (!response.ok) {
        const fields = response.error?.fields;
        if (fields !== undefined) {
          if (fields['old_password'] !== undefined) this.oldPasswordError = fields['old_password'];
          if (fields['new_password'] !== undefined) this.newPasswordError = fields['new_password'];
        }
        this.passwordError = response.error?.message ?? '修改失败，请重试';
        return;
      }
      this.showPasswordSheet = false;
      promptAction.showToast({ message: '密码修改成功，本机仍保持登录', duration: 2000 });
    } finally {
      this.changingPassword = false;
    }
  }

  private async syncOutbox(): Promise<void> {
    this.syncingOutbox = true;
    const result: OutboxSyncResult = await OutboxSync.syncAll();
    await this.loadOutbox();
    this.syncingOutbox = false;
    if (result.remaining === 0) {
      this.showOutbox = false;
      promptAction.showToast({ message: `已同步 ${result.synced} 条`, duration: 2000 });
    } else {
      promptAction.showToast({ message: result.last_error.length > 0 ? result.last_error : '仍有待同步项', duration: 2000 });
    }
  }

  private async discardOne(id: string): Promise<void> {
    await this.outboxStore.remove(id);
    await this.loadOutbox();
  }

  private async discardAll(): Promise<void> {
    await this.outboxStore.clear();
    await this.loadOutbox();
    this.showOutbox = false;
  }

  private confirmLogout(): void {
    promptAction.showDialog({
      title: '退出登录？',
      message: '本地缓存与待同步的更改会被一起清空。',
      buttons: [
        { text: '取消', color: Color.textSecondary },
        { text: '退出', color: Color.danger }
      ]
    }).then((result) => {
      if (result.index === 1) {
        this.logout();
      }
    });
  }

  private async logout(): Promise<void> {
    await this.authApi.logout();
    await SessionStore.clearAll();
    replaceTo('pages/LoginPage');
  }
}
