const API_BASE = import.meta.env.VITE_API_BASE_URL || globalThis.location.origin;

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
  return apiRequest<T>(path, { query, timeoutMs });
}

export async function apiRequest<T>(
  path: string,
  options: { query?: Record<string, QueryValue>; timeoutMs?: number; credential?: string; body?: unknown; signal?: AbortSignal } = {},
): Promise<T> {
  const { query, timeoutMs = 8000, credential, body, signal } = options;
  const controller = new AbortController();
  const abort = () => controller.abort();
  if (signal?.aborted) abort();
  else signal?.addEventListener("abort", abort, { once: true });
  const timer = globalThis.setTimeout(() => controller.abort(), timeoutMs);
  try {
    const headers: Record<string, string> = { Accept: "application/json" };
    if (credential) headers.Authorization = "Bearer " + credential;
    if (body !== undefined) headers["Content-Type"] = "application/json";
    const response = await fetch(buildURL(path, query), {
      headers,
      method: body === undefined ? "GET" : "POST",
      body: body === undefined ? undefined : JSON.stringify(body),
      cache: credential ? "no-store" : undefined,
      redirect: credential ? "error" : undefined,
      signal: controller.signal,
    });

    const text = await response.text();
    let payload: unknown = null;
    if (text) {
      try {
        payload = JSON.parse(text) as unknown;
      } catch {
        payload = null;
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
    if (payload === null || typeof payload !== "object") {
      throw new ApiError("业务服务返回了无效的 JSON 响应", 502, path);
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
    signal?.removeEventListener("abort", abort);
    globalThis.clearTimeout(timer);
  }
}

type EventStreamOptions = {
  credential: string;
  signal: AbortSignal;
  onEvent: (name: string, data: string) => void;
  onActivity?: () => void;
};

/** Fetch keeps the admin credential in the Authorization header while reading SSE. */
export async function openEventStream(
  path: string,
  { credential, signal, onEvent, onActivity }: EventStreamOptions,
): Promise<void> {
  const response = await fetch(buildURL(path), {
    headers: { Accept: "text/event-stream", Authorization: "Bearer " + credential },
    cache: "no-store",
    redirect: "error",
    signal,
  });
  if (!response.ok) throw new ApiError(`监视连接失败（HTTP ${response.status}）`, response.status, path);
  const contentType = response.headers.get("Content-Type")?.split(";")[0].trim().toLowerCase();
  if (contentType !== "text/event-stream" || !response.body) {
    throw new ApiError("监视服务返回了无效的事件流", 502, path);
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  const lineEnding = /\r\n|\r(?!$)|\n/;
  let pending = "";
  let eventName = "";
  let data: string[] = [];
  try {
    while (!signal.aborted) {
      const { done, value } = await reader.read();
      if (done || signal.aborted) break;
      pending += decoder.decode(value, { stream: true });
      if (pending.length > 2_000_000) throw new ApiError("单条监视事件超出大小限制", 502, path);
      let match = lineEnding.exec(pending);
      while (match) {
        const line = pending.slice(0, match.index);
        pending = pending.slice(match.index + match[0].length);
        if (!line) {
          if (data.length) onEvent(eventName || "message", data.join("\n"));
          eventName = "";
          data = [];
        } else if (line.startsWith(":")) {
          onActivity?.();
        } else {
          const colon = line.indexOf(":");
          const field = colon < 0 ? line : line.slice(0, colon);
          const contents = colon < 0 ? "" : line.slice(colon + 1).replace(/^ /, "");
          if (field === "event") eventName = contents;
          if (field === "data") data.push(contents);
        }
        match = lineEnding.exec(pending);
      }
    }
  } finally {
    void reader.cancel().catch(() => {});
  }
}
