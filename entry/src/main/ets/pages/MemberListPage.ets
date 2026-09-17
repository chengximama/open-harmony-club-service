// 成员名录页面（B同学负责）
// 按部门分组展示成员，点击卡片进入成员详情

interface Member {
  id: number;
  name: string;
  role: string;
  deptId: number;
  deptName: string;
  status: string;
  joinedAt: string;
}

interface Dept {
  id: number;
  name: string;
}

// 接入后端后由部门与成员接口填充
const DEPTS: Dept[] = [];

const MEMBERS: Member[] = [];

const ROLE_MAP: Record<string, string> = {
  'president': '会长',
  'vice_president': '副会长',
  'lead': '部长',
  'vice_lead': '副部长',
  'member': '成员',
};

@Component
struct MemberCard {
  member: Member = { id: 0, name: '', role: 'member', deptId: 0, deptName: '', status: 'active', joinedAt: '' };
  onCardClick: () => void = () => {};

  build() {
    Row() {
      Text(this.member.name.substring(0, 1))
        .fontSize(20)
        .fontColor(Color.White)
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(this.getAvatarColor())
        .textAlign(TextAlign.Center)

      Column() {
        Text(this.member.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)

        Text(this.getRoleName())
          .fontSize(12)
          .fontColor('#999999')
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      .layoutWeight(1)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(Color.White)
    .borderRadius(8)
    .margin({ bottom: 8 })
    .onClick(() => {
      this.onCardClick();
    })
  }

  getRoleName(): string {
    return ROLE_MAP[this.member.role] || '成员';
  }

  getAvatarColor(): string {
    switch (this.member.role) {
      case 'president': return '#E53935';
      case 'vice_president': return '#FB8C00';
      case 'lead': return '#1E88E5';
      case 'vice_lead': return '#43A047';
      default: return '#7E57C2';
    }
  }
}

@Component
struct DeptSection {
  deptName: string = '';
  members: Member[] = [];
  onMemberClick: (memberId: number) => void = (_id: number) => {};

  build() {
    Column() {
      Text(this.deptName)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
        .width('100%')
        .padding({ left: 4, top: 8, bottom: 4 })

      ForEach(this.members, (item: Member) => {
        MemberCard({
          member: item,
          onCardClick: () => this.onMemberClick(item.id)
        })
      }, (item: Member) => item.id.toString())
    }
    .width('100%')
  }
}

@Component
export default struct MemberListPage {
  onMemberClick: (memberId: number) => void = (_id: number) => {};
  @State members: Member[] = MEMBERS;

  getMembersByDept(deptId: number): Member[] {
    return this.members.filter((m: Member) => m.deptId === deptId);
  }

  build() {
    Column() {
      Row() {
        Text('🔍  搜索成员')
          .fontSize(14)
          .fontColor('#999999')
          .width('100%')
          .padding(12)
          .backgroundColor('#F5F5F5')
          .borderRadius(8)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      List({ space: 8 }) {
        if (DEPTS.length === 0) {
          ListItem() {
            Column({ space: 8 }) {
              Text('暂无成员数据')
                .fontSize(16)
                .fontColor('#999999')
              Text('接入成员接口后，这里会按部门显示名录。')
                .fontSize(12)
                .fontColor('#999999')
            }
            .width('100%')
            .padding({ top: 80, bottom: 80 })
            .justifyContent(FlexAlign.Center)
          }
        } else {
          ForEach(DEPTS, (dept: Dept) => {
            ListItem() {
              DeptSection({
                deptName: dept.name,
                members: this.getMembersByDept(dept.id),
                onMemberClick: (id: number) => this.onMemberClick(id)
              })
            }
          }, (dept: Dept) => dept.id.toString())
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 16, right: 16, top: 4, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FAFAFA')
  }
}
