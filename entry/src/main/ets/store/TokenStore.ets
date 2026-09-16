/**
 * Token 持久化存储
 * 使用 @kit.ArkData 的 Preferences API
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TOKEN_KEY = 'auth_token';
const PREFERENCES_NAME = 'app_preferences';
const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'TokenStore';

export class TokenStore {
  private static instance: TokenStore;
  private preferences_: preferences.Preferences | null = null;
  private cachedToken: string | null = null;

  private constructor() {
    // 单例
  }

  static getInstance(): TokenStore {
    if (!TokenStore.instance) {
      TokenStore.instance = new TokenStore();
    }
    return TokenStore.instance;
  }

  /**
   * 初始化 Preferences，需传入 context
   */
  async init(context: common.Context): Promise<void> {
    if (this.preferences_) {
      return;
    }

    try {
      const options: preferences.Options = { name: PREFERENCES_NAME };
      this.preferences_ = await preferences.getPreferences(context, options);
      const val = await this.preferences_.get(TOKEN_KEY, '');
      const token = typeof val === 'string' ? val : '';
      this.cachedToken = token.length > 0 ? token : null;
    } catch (err) {
      this.preferences_ = null;
      this.cachedToken = null;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'init failed: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 获取 token
   */
  async getToken(): Promise<string | null> {
    if (this.cachedToken) {
      return this.cachedToken;
    }

    if (!this.preferences_) {
      return null;
    }

    try {
      const val = await this.preferences_.get(TOKEN_KEY, '');
      const token = typeof val === 'string' ? val : '';
      this.cachedToken = token.length > 0 ? token : null;
      return this.cachedToken;
    } catch (err) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'getToken failed: %{public}s', JSON.stringify(err));
      return null;
    }
  }

  /**
   * 保存 token
   */
  async setToken(token: string): Promise<void> {
    this.cachedToken = token;

    if (!this.preferences_) {
      return;
    }

    try {
      await this.preferences_.put(TOKEN_KEY, token);
      await this.preferences_.flush();
    } catch (err) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'setToken failed: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 清除 token（退出登录）
   */
  async clearToken(): Promise<void> {
    this.cachedToken = null;

    if (!this.preferences_) {
      return;
    }

    try {
      await this.preferences_.delete(TOKEN_KEY);
      await this.preferences_.flush();
    } catch (err) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'clearToken failed: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 是否已登录（有 token）
   */
  async isLoggedIn(): Promise<boolean> {
    const token = await this.getToken();
    return token !== null && token.length > 0;
  }
}
