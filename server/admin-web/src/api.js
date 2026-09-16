// 统一 API 封装：自动带 token，统一处理 {code, message, data} 响应壳
async function request(path, options = {}) {
  const token = localStorage.getItem('qz_token')
  const headers = { 'Content-Type': 'application/json', ...(options.headers || {}) }
  if (token) headers['Authorization'] = 'Bearer ' + token
  const res = await fetch(path, { ...options, headers })
  const json = await res.json()
  if (json.code !== 0) {
    if (json.code === 401) {
      // 登录失效，清 token 回登录页
      localStorage.removeItem('qz_token')
      window.location.href = '/login'
    }
    throw new Error(json.message || 'request failed')
  }
  return json.data
}

export const api = {
  login: (username, password) =>
    request('/api/login', { method: 'POST', body: JSON.stringify({ username, password }) }),
  me: () => request('/api/me'),
  dashboard: () => request('/api/dashboard'),
  users: () => request('/api/users'),
  createUser: (username, password, roleId) =>
    request('/api/users', { method: 'POST', body: JSON.stringify({ username, password, roleId }) }),
  deleteUser: (id) => request('/api/users/' + id, { method: 'DELETE' }),
  roles: () => request('/api/roles'),
  perms: () => request('/api/perms'),

  // ---- 社团管理运维页（/club）----
  // 读：走运维台自己的后端（它只读社团库文件，因此不需要 club-server 在跑）
  // 写：不走这里 —— 直接 fetch club-server 的真实 API，见 views/Club.vue
  clubConfig: () => request('/api/club/config'),
  clubOverview: () => request('/api/club/overview'),
  clubMembers: (qs = '') => request('/api/club/members' + qs),
  clubDepts: () => request('/api/club/depts'),
  clubTasks: (qs = '') => request('/api/club/tasks' + qs),
  clubPlans: () => request('/api/club/plans'),
  clubLinks: () => request('/api/club/links'),
  clubAudit: (limit = 200) => request('/api/club/audit?limit=' + limit),
  clubServerHealth: () => request('/api/club/server-health'),
  clubBackup: () => request('/api/club/backup', { method: 'POST', body: '{}' })
}
