export interface HealthStatus {
  service: string;
  postgres: string;
  redis: string;
  time: string;
}

export interface GameDescriptor {
  product_id: string;
  game_category: string;
  game_id: string;
  rule_set_id: string;
  rule_version: string;
  name: string;
  enabled: boolean;
}

const API_BASE = import.meta.env.VITE_API_BASE_URL || "http://localhost:8080";

/** apiGet（统一GET请求）集中处理HTTP错误，避免每个页面重复写fetch判断。 */
async function apiGet<T>(path: string): Promise<T> {
  const response = await fetch(API_BASE + path);
  if (!response.ok) {
    throw new Error("请求失败：" + response.status);
  }
  return (await response.json()) as T;
}

export const api = {
  health: () => apiGet<HealthStatus>("/health"),
  catalog: () => apiGet<{ games: GameDescriptor[] }>("/api/v1/catalog"),
  aiCapabilities: () =>
    apiGet<Array<{ key: string; name: string; description: string; enabled: boolean }>>(
      "/api/v1/ai/capabilities",
    ),
};