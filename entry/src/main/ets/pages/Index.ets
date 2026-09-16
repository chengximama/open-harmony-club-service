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
            MyTasksPage({ onOpenPlans: () => { this.currentIndex = 2 } })
          }
          .tabBar(this.tabBarBuilder('我的\n任务', 0))

          TabContent() {
            TaskListPage()
          }
          .tabBar(this.tabBarBuilder('任务', 1))

          TabContent() {
            PlanTreePage()
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
