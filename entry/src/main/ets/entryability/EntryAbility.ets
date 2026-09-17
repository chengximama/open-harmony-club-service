import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { TokenStore } from '../store/TokenStore';
import { OutboxStore } from '../store/OutboxStore';
import { OutboxSync } from '../store/OutboxSync';
import { HttpClient } from '../api/HttpClient';
import { BASE_URL } from '../config/Env';
import { extractInviteToken, openInviteRegistration, rememberInviteTokenFromUri } from '../utils/InviteDeepLink';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    rememberInviteTokenFromUri(want.uri);
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    HttpClient.getInstance().setBaseUrl(BASE_URL);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    const tokenStore = TokenStore.getInstance();
    const outboxStore = OutboxStore.getInstance();
    Promise.all([tokenStore.init(this.context), outboxStore.init(this.context)]).then(() => {
      windowStage.loadContent('pages/Index', (err) => {
        if (err.code) {
          hilog.error(DOMAIN, 'testTag', 'Failed to load Index. Cause: %{public}s', JSON.stringify(err));
        }
      });
    }).catch((err: Error) => {
      hilog.error(DOMAIN, 'testTag', 'Store init failed. Cause: %{public}s', JSON.stringify(err));
      windowStage.loadContent('pages/Index', (err) => {
        if (err.code) {
          hilog.error(DOMAIN, 'testTag', 'Failed to load Index. Cause: %{public}s', JSON.stringify(err));
        }
      });
    });
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const inviteToken: string = extractInviteToken(want.uri);
    if (inviteToken.length > 0) {
      openInviteRegistration(inviteToken);
    }
  }

  onForeground(): void {
    OutboxSync.syncAll().then(() => {
      hilog.info(DOMAIN, 'testTag', 'Outbox sync completed');
    }).catch((err: Error) => {
      hilog.warn(DOMAIN, 'testTag', 'Outbox sync skipped. Cause: %{public}s', JSON.stringify(err));
    });
  }
}
