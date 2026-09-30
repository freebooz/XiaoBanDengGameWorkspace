const API_BASE = import.meta.env.VITE_API_BASE_URL || "http://localhost:8080";

export type QueryValue = string | number | boolean | null | undefined;

/** ApiError（接口错误）保留HTTP状态、路径和可展示中文消息。 */
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

function buildURL(path: string, query?: Record<string, QueryValue>): string {
  const url = new URL(API_BASE + path);
  for (const [key, value] of Object.entries(query ?? {})) {
    if (value === undefined || value === null || value === "") continue;
    url.searchParams.set(key, String(value));
  }
  return url.toString();
}

/** apiGet（统一GET请求）处理超时、错误JSON和网络失败。 */
export async function apiGet<T>(
  path: string,
  query?: Record<string, QueryValue>,
  timeoutMs = 8000,
): Promise<T> {
  const controller = new AbortController();
  const timer = globalThis.setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(buildURL(path, query), {
      headers: { Accept: "application/json" },
      signal: controller.signal,
    });

    const text = await response.text();
    let payload: unknown = null;
    if (text) {
      try {
        payload = JSON.parse(text) as unknown;
      } catch {
        payload = text;
      }
    }

    if (!response.ok) {
      const message =
        typeof payload === "object" &&
        payload !== null &&
        "error" in payload &&
        typeof (payload as { error?: unknown }).error === "string"
          ? (payload as { error: string }).error
          : `请求失败：HTTP ${response.status}`;
      throw new ApiError(message, response.status, path);
    }
    return payload as T;
  } catch (error) {
    if (error instanceof ApiError) throw error;
    const message =
      error instanceof DOMException && error.name === "AbortError"
        ? "请求超时，请稍后重试"
        : "无法连接业务服务";
    throw new ApiError(message, 0, path);
  } finally {
    globalThis.clearTimeout(timer);
  }
}
