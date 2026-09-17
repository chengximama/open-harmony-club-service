import MemberListPage from './MemberListPage';
import MemberDetailPage from './MemberDetailPage';
import { ProfilePage } from './ProfilePage';
import MyTasksPage from './MyTasksPage';
import TaskListPage from './TaskListPage';
import PlanTreePage from './PlanTreePage';
import { AuthApi } from '../api/AuthApi';
import { Color, FontSize, Radius, Space } from '../core/Theme';
import { PermissionStore, UpdateData } from '../store/PermissionStore';
import { TokenStore } from '../store/TokenStore';
import { replaceTo } from '../utils/RouterUtils';

@Entry
@Component
struct Index {
  @State phase: string = 'loading';
  @State errorMsg: string = '';
  @State currentIndex: number = 0;
  @State showDetail: boolean = false;
  @State selectedMemberId: number = 0;
  @State refreshSignal: number = 0;

  private authApi: AuthApi = new AuthApi();
  private tokenStore: TokenStore = TokenStore.getInstance();
  private permissionStore: PermissionStore = PermissionStore.getInstance();
  private hasShown: boolean = false;

  aboutToAppear(): void {
    this.checkAuth();
  }

  onPageShow(): void {
    if (this.hasShown) {
      this.refreshSignal += 1;
      if (this.phase === 'home') {
        this.verifySession();
      }
    }
    this.hasShown = true;
  }

  build() {
    if (this.phase === 'loading') {
      this.loadingView()
    } else if (this.phase === 'error') {
      this.errorView()
    } else if (this.showDetail) {
      this.memberDetailView()
    } else {
      this.homeView()
    }
  }

  @Builder
  loadingView() {
    Column({ space: 12 }) {
      LoadingProgress()
        .width(36)
        .height(36)
        .color(Color.primary)
      Text('正在加载…')
        .fontSize(FontSize.body)
        .fontColor(Color.textTertiary)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Color.canvas)
  }

  @Builder
  errorView() {
    Column({ space: 16 }) {
      Text(this.errorMsg)
        .fontSize(FontSize.body)
        .fontColor(Color.textSecondary)
        .textAlign(TextAlign.Center)
      Button('重试')
        .width(120)
        .height(42)
        .fontColor(Color.onPrimary)
        .backgroundColor(Color.primary)
        .borderRadius(Radius.button)
        .onClick(() => this.checkAuth())
    }
    .width('100%')
    .height('100%')
    .padding(Space.page)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Color.canvas)
  }

  @Builder
  memberDetailView() {
    Column() {
      Row() {
        Image($r('app.media.chevron_left'))
          .width(24)
          .height(24)
          .onClick(() => {
            this.showDetail = false;
          })
        Text('成员详情')
          .fontSize(FontSize.title)
          .fontWeight(600)
          .fontColor(Color.textPrimary)
          .layoutWeight(1)
        Blank().width(28)
      }
      .width('100%')
      .height(52)
      .padding({ left: Space.page, right: Space.page })

      MemberDetailPage({ memberId: this.selectedMemberId })
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.canvas)
  }

  @Builder
  homeView() {
    Tabs({ barPosition: BarPosition.End, index: this.currentIndex }) {
      TabContent() {
        MyTasksPage({ onOpenPlans: () => { this.currentIndex = 2 }, refreshSignal: this.refreshSignal })
      }
      .tabBar(this.tabBarBuilder('我的任务', 0, $r('app.media.tab_my_tasks')))

      TabContent() {
        TaskListPage({ refreshSignal: this.refreshSignal })
      }
      .tabBar(this.tabBarBuilder('任务', 1, $r('app.media.tab_tasks')))

      TabContent() {
        PlanTreePage({ refreshSignal: this.refreshSignal })
      }
      .tabBar(this.tabBarBuilder('课题', 2, $r('app.media.tab_plans')))

      TabContent() {
        MemberListPage({
          onMemberClick: (id: number) => {
            this.selectedMemberId = id;
            this.showDetail = true;
          }
        })
      }
      .tabBar(this.tabBarBuilder('名录', 3, $r('app.media.tab_members')))

      TabContent() {
        ProfilePage({ refreshSignal: this.refreshSignal })
      }
      .tabBar(this.tabBarBuilder('我的', 4, $r('app.media.tab_mine')))
    }
    .barMode(BarMode.Fixed)
    .barHeight(94)
    .barBackgroundColor(Color.surface)
    .onChange((index: number) => {
      this.currentIndex = index;
      this.refreshSignal += 1;
    })
    .width('100%')
    .height('100%')
  }

  @Builder
  tabBarBuilder(label: string, index: number, icon: Resource) {
    Column({ space: 4 }) {
      Image(icon)
        .width(18)
        .height(18)
        .fillColor(this.currentIndex === index ? Color.onPrimary : Color.textTertiary)

      Text(label)
        .fontSize(FontSize.navLabel)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.currentIndex === index ? Color.onPrimary : Color.textTertiary)
    }
    .width('100%')
    .height(60)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.currentIndex === index ? Color.primary : Color.surface)
    .borderRadius(Radius.navItem)
    .margin({ left: 2, right: 2, top: 12, bottom: 22 })
  }

  private async checkAuth(): Promise<void> {
    this.phase = 'loading';
    this.errorMsg = '';
    const hasToken = await this.tokenStore.isLoggedIn();
    if (!hasToken) {
      replaceTo('pages/LoginPage');
      return;
    }
    const response = await this.authApi.me();
    if (!response.ok || response.data === undefined) {
      this.errorMsg = response.error?.message ?? '加载失败，请重试';
      this.phase = 'error';
      return;
    }
    const update: UpdateData = {
      user: response.data.member,
      permissions: response.data.permissions,
    };
    this.permissionStore.update(update);
    if (response.data.member.status === 'pending' || response.data.permissions.view_scope === 'none') {
      replaceTo('pages/PendingPage');
      return;
    }
    this.phase = 'home';
  }

  private async verifySession(): Promise<void> {
    const response = await this.authApi.me();
    if (response.ok && response.data !== undefined) {
      const update: UpdateData = {
        user: response.data.member,
        permissions: response.data.permissions,
      };
      this.permissionStore.update(update);
      if (response.data.member.status === 'pending' || response.data.permissions.view_scope === 'none') {
        replaceTo('pages/PendingPage');
      }
    }
  }
}
