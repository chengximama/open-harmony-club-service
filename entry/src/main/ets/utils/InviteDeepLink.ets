import { pushTo, replaceTo } from './RouterUtils';

const JOIN_PATH_PREFIX: string = '/join/';
const MAX_INVITE_TOKEN_LENGTH: number = 64;

let pendingInviteToken: string = '';

export interface InviteRouteParams {
  invite_token: string;
}

function isAllowedTokenChar(code: number): boolean {
  const isDigit: boolean = code >= 0x30 && code <= 0x39;
  const isUpper: boolean = code >= 0x41 && code <= 0x5A;
  const isLower: boolean = code >= 0x61 && code <= 0x7A;
  return isDigit || isUpper || isLower || code === 0x2D || code === 0x5F;
}

export function extractInviteToken(uri?: string): string {
  if (uri === undefined || uri.length === 0) {
    return '';
  }

  let pathAndQuery: string = '';
  const schemeSeparator: number = uri.indexOf('://');
  if (schemeSeparator >= 0) {
    const scheme: string = uri.substring(0, schemeSeparator).toLowerCase();
    if (scheme !== 'https') {
      return '';
    }
    const pathStart: number = uri.indexOf('/', schemeSeparator + 3);
    if (pathStart < 0) {
      return '';
    }
    pathAndQuery = uri.substring(pathStart);
  } else if (uri.startsWith('/')) {
    pathAndQuery = uri;
  } else {
    return '';
  }

  const hashStart: number = pathAndQuery.indexOf('#');
  if (hashStart >= 0) {
    pathAndQuery = pathAndQuery.substring(0, hashStart);
  }
  const queryStart: number = pathAndQuery.indexOf('?');
  if (queryStart >= 0) {
    pathAndQuery = pathAndQuery.substring(0, queryStart);
  }

  if (!pathAndQuery.startsWith(JOIN_PATH_PREFIX)) {
    return '';
  }
  const rawToken: string = pathAndQuery.substring(JOIN_PATH_PREFIX.length);
  if (rawToken.length === 0 || rawToken.indexOf('/') >= 0) {
    return '';
  }

  let token: string = '';
  try {
    token = decodeURIComponent(rawToken);
  } catch (_) {
    return '';
  }
  if (token.length === 0 || token.length > MAX_INVITE_TOKEN_LENGTH) {
    return '';
  }
  for (let i: number = 0; i < token.length; i++) {
    if (!isAllowedTokenChar(token.charCodeAt(i))) {
      return '';
    }
  }
  return token;
}

export function rememberInviteTokenFromUri(uri?: string): string {
  const token: string = extractInviteToken(uri);
  if (token.length > 0) {
    pendingInviteToken = token;
  }
  return token;
}

export function consumePendingInviteToken(): string {
  const token: string = pendingInviteToken;
  pendingInviteToken = '';
  return token;
}

export function openInviteRegistration(token: string, replace: boolean = false): void {
  if (token.length === 0) {
    return;
  }
  const params: InviteRouteParams = { invite_token: token };
  if (replace) {
    replaceTo('pages/RegisterPage', params);
  } else {
    pushTo('pages/RegisterPage', params);
  }
}