import MemberListPage from './MemberListPage';
import MemberDetailPage from './MemberDetailPage';
import { ProfilePage } from './ProfilePage';
import MyTasksPage from './MyTasksPage';
import TaskListPage from './TaskListPage';
import PlanTreePage from './PlanTreePage';

@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
  @State showDetail: boolean = false;
  @State selectedMemberId: number = 0;
  // 任务列表刷新信号：切换 Tab / 从子页返回时 +1，子页用 @Watch 监听并重新拉取
  @State refreshSignal: number = 0;
  private hasShown: boolean = false;

  onPageShow(): void {
    // 从新建任务等子页返回时刷新；首次展示不额外触发（子页 aboutToAppear 已拉取）
    if (this.hasShown) {
      this.refreshSignal++;
    }
    this.hasShown = true;
  }

  build() {
    if (this.showDetail) {
      Column() {
        // 顶部返回栏
        Row() {
          Text('← 返回')
            .fontSize(16)
            .fontColor('#1E88E5')
            .onClick(() => {
              this.showDetail = false;
            })

          Blank()
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })

        MemberDetailPage({ memberId: this.selectedMemberId })
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    } else {
      Navigation() {
        Tabs({ barPosition: BarPosition.End, index: this.currentIndex }) {
          TabContent() {
            MyTasksPage({ onOpenPlans: () => { this.currentIndex = 2 }, refreshSignal: this.refreshSignal })
          }
          .tabBar(this.tabBarBuilder('我的\n任务', 0))

          TabContent() {
            TaskListPage({ refreshSignal: this.refreshSignal })
          }
          .tabBar(this.tabBarBuilder('任务', 1))

          TabContent() {
            PlanTreePage({ refreshSignal: this.refreshSignal })
          }
          .tabBar(this.tabBarBuilder('课题', 2))

          TabContent() {
            MemberListPage({
              onMemberClick: (id: number) => {
                this.selectedMemberId = id;
                this.showDetail = true;
              }
            })
          }
          .tabBar(this.tabBarBuilder('名录', 3))

          TabContent() {
            ProfilePage()
          }
          .tabBar(this.tabBarBuilder('我的', 4))
        }
        .barMode(BarMode.Fixed)
        .onChange((index: number) => {
          this.currentIndex = index;
          // 切到数据 Tab（我的任务/任务/课题）时刷新，保证看到最新数据
          if (index === 0 || index === 1 || index === 2) {
            this.refreshSignal++;
          }
        })
      }
      .title('社团管家')
      .titleMode(NavigationTitleMode.Mini)
    }
  }

  @Builder
  tabBarBuilder(title: string, index: number) {
    Column() {
      Text(title)
        .fontSize(12)
        .lineHeight(16)
        .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.currentIndex === index ? '#0A59F7' : '#666666')
        .maxLines(2)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height(48)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
