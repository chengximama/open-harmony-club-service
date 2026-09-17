import PendingApprovalPage from './PendingApprovalPage';
import { can, PermissionStore } from '../store/PermissionStore';
import { replaceTo } from '../utils/RouterUtils';

@Entry
@Component
struct ApprovePage {
  aboutToAppear(): void {
    if (!can(PermissionStore.getInstance().userInfo, 'ManageMembers')) {
      replaceTo('pages/Index');
    }
  }

  build() {
    Column() {
      PendingApprovalPage()
    }
    .width('100%')
    .height('100%')
  }
}
