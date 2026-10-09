import { ApiError, apiGet, apiPost } from "./client";

/** 服务端公开的只读管理员身份，不包含 cookie 内容或密码。 */
export interface AdminSession {
  username: string;
  role: "readonly";
  expires_at: string;
}

/** 未知响应必须通过身份与有效期校验后才能成为页面授权依据。 */
function validateSession(payload: unknown, path: string): AdminSession {
  if (typeof payload !== "object" || payload === null ||
    !("username" in payload) || typeof payload.username !== "string" || !payload.username.trim() ||
    !("role" in payload) || payload.role !== "readonly" ||
    !("expires_at" in payload) || typeof payload.expires_at !== "string" ||
    !Number.isFinite(Date.parse(payload.expires_at)) || Date.parse(payload.expires_at) <= Date.now()) {
    throw new ApiError("管理员会话响应无效", 502, path);
  }
  return payload as AdminSession;
}

/** 登录只提交账号和密码，浏览器自行接收服务端的 HttpOnly cookie。 */
export async function loginAdmin(username: string, password: string): Promise<AdminSession> {
  const path = "/api/v1/admin/auth/login";
  return validateSession(await apiPost<unknown>(path, { username, password }), path);
}

/** 刷新页面时从服务端确认真实会话，而非信任浏览器存储。 */
export async function getAdminSession(): Promise<AdminSession> {
  const path = "/api/v1/admin/auth/session";
  return validateSession(await apiGet<unknown>(path), path);
}

/** 注销真实服务端会话；204 响应没有正文。 */
export async function logoutAdmin(): Promise<void> {
  await apiPost<void>("/api/v1/admin/auth/logout");
}
