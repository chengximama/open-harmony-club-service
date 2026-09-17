import ManagePage from './ManagePage';
import { can, PermissionStore } from '../store/PermissionStore';
import { replaceTo } from '../utils/RouterUtils';

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
      ManagePage()
    }
    .width('100%')
    .height('100%')
  }
}
