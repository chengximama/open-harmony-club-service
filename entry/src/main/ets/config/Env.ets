import BuildProfile from 'BuildProfile';

/**
 * 调试构建继续使用模拟器宿主机 HTTP 地址。
 * 真机联调时只需改 DEV_BASE_URL 为后端电脑的局域网 IP。
 */
const DEV_BASE_URL: string = 'http://10.194.208.10:8080/api/v1';

/**
 * 发布构建必须走 HTTPS。
 * URL 故意使用 .invalid 域名作为失败保护：换真实地址前不会把明文请求发到线上。
 * 发布前还需把后端自签 CA 配置到 network_config.json 的 trust-anchors。
 */
const RELEASE_BASE_URL: string = 'https://replace-before-release.invalid:8443/api/v1';

export const BASE_URL: string = BuildProfile.DEBUG ? DEV_BASE_URL : RELEASE_BASE_URL;
