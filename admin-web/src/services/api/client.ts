export type QueryValue = string | number | boolean | null | undefined;

// 路由负责处理会话失效，客户端只提供统一的通知边界，避免依赖状态层。
let unauthorizedContext: { handler: () => void; getSessionRevision: () => number } | undefined;
/** 路由注入身份代次读取能力，客户端无需循环依赖认证状态层。 */
export function setUnauthorizedHandler(handler: () => void, getSessionRevision: () => number): void {
  unauthorizedContext = { handler, getSessionRevision };
}

/** ApiError（接口错误）保留 HTTP 状态、路径和可展示中文消息。 */
export class ApiError extends Error {
  readonly status: number;
  readonly path: string;

  constructor(message: string, status: number, path: string) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.path = path;
  }
}

/** 同源为默认接口根地址，明确配置的根地址也兼容末尾斜线。 */
function buildURL(path: string, query?: Record<string, QueryValue>): string {
  const base = (import.meta.env.VITE_API_BASE_URL || "").replace(/\/$/, "");
  const url = new URL(base + path, window.location.origin);
  for (const [key, value] of Object.entries(query ?? {})) {
    if (value === undefined || value === null || value === "") continue;
    url.searchParams.set(key, String(value));
  }
  return url.toString();
}

/** 统一请求使用 HttpOnly cookie，不读取或持久化任何令牌。 */
async function apiRequest<T>(path: string, method: "GET" | "POST", body?: unknown,
  query?: Record<string, QueryValue>, timeoutMs = 8000): Promise<T> {
  // 每次请求绑定发起时的身份及路由注册，迟到的旧 401 不影响新会话。
  const requestContext = unauthorizedContext;
  const requestRevision = requestContext?.getSessionRevision();
  const controller = new AbortController();
  const timer = globalThis.setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(buildURL(path, query), {
      method,
      credentials: "include",
      cache: "no-store",
      headers: body === undefined ? { Accept: "application/json" }
        : { Accept: "application/json", "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: controller.signal,
    });
    const text = await response.text();
    let payload: unknown = null;
    if (text) {
      try { payload = JSON.parse(text) as unknown; } catch { payload = text; }
    }
    if (!response.ok) {
      // 登录和会话检查的 401 由认证流程处理，避免重新导航到自身。
      if (response.status === 401 && path.startsWith("/api/v1/admin/") && !path.startsWith("/api/v1/admin/auth/")) {
        if (requestContext && requestContext === unauthorizedContext &&
          requestRevision === requestContext.getSessionRevision()) requestContext.handler();
      }
      const message = typeof payload === "object" && payload !== null && "error" in payload &&
        typeof (payload as { error?: unknown }).error === "string"
        ? (payload as { error: string }).error : `请求失败：HTTP ${response.status}`;
      throw new ApiError(message, response.status, path);
    }
    return payload as T;
  } catch (error) {
    if (error instanceof ApiError) throw error;
    const message = error instanceof DOMException && error.name === "AbortError"
      ? "请求超时，请稍后重试" : "无法连接业务服务";
    throw new ApiError(message, 0, path);
  } finally {
    globalThis.clearTimeout(timer);
  }
}

/** apiGet（统一 GET 请求）处理超时、错误 JSON 和网络失败。 */
export function apiGet<T>(path: string, query?: Record<string, QueryValue>, timeoutMs = 8000): Promise<T> {
  return apiRequest<T>(path, "GET", undefined, query, timeoutMs);
}

/** apiPost（统一 POST 请求）只在本次网络调用中序列化请求体。 */
export function apiPost<T>(path: string, body?: unknown, timeoutMs = 8000): Promise<T> {
  return apiRequest<T>(path, "POST", body, undefined, timeoutMs);
}
