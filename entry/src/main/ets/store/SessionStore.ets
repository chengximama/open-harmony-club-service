import { TokenStore } from './TokenStore';
import { PermissionStore } from './PermissionStore';
import { OutboxStore } from './OutboxStore';
import { CalendarMapStore } from './CalendarMapStore';

/** 所有登录态相关的本地数据必须通过这里统一清理。 */
export class SessionStore {
  static async clearAll(): Promise<void> {
    await TokenStore.getInstance().clearToken();
    PermissionStore.getInstance().clear();
    await OutboxStore.getInstance().clear();
    await CalendarMapStore.getInstance().clear();
  }
}
