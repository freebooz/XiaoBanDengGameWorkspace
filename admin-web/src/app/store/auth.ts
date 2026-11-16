import { defineStore } from "pinia";
import { computed, ref } from "vue";
import { ApiError, apiRequest, openEventStream, type QueryValue } from "../../services/api/client";

export const PLATFORM_READ = "platform:read";
export const MAHJONG_REVIEW = "mahjong:review";
export const WALLET_GRANT_EGGS = "wallet:grant_eggs";

type AdminSession = {
  admin_name: string;
  capabilities: string[];
};

export const useAuthStore = defineStore("auth", () => {
  const adminName = ref("");
  const capabilities = ref<string[]>([]);
  const revision = ref(0);
  const sessionRevision = computed(() => revision.value);
  let credential = "";
  let generation = 0;
  const streams = new Set<AbortController>();
  const isAuthenticated = computed(() => adminName.value !== "");
  const landingPath = computed(() => {
    if (can(PLATFORM_READ)) return "/dashboard";
    if (can(MAHJONG_REVIEW)) return "/mahjong/reports";
    if (can(WALLET_GRANT_EGGS)) return "/wallet/eggs";
    return "/access";
  });

  function can(capability: string): boolean {
    return capabilities.value.includes(capability);
  }

  async function login(input: string): Promise<boolean> {
    const candidate = input.trim();
    if (!/^[A-Za-z0-9_-]{43}$/.test(candidate)) throw new Error("请输入有效的管理员凭据");
    const attempt = ++generation;
    const session = await apiRequest<AdminSession>("/api/v1/admin/session", { credential: candidate });
    if (attempt !== generation) return false;
    if (typeof session?.admin_name !== "string" || !session.admin_name.trim() ||
        !Array.isArray(session.capabilities) || !session.capabilities.every((item) => typeof item === "string")) {
      throw new Error("管理员会话数据无效");
    }
    abortStreams();
    credential = candidate;
    capabilities.value = session.capabilities;
    adminName.value = session.admin_name;
    revision.value++;
    return true;
  }

  function logout(): void {
    generation++;
    abortStreams();
    credential = "";
    adminName.value = "";
    capabilities.value = [];
    revision.value++;
  }

  function abortStreams(): void {
    for (const stream of streams) stream.abort();
    streams.clear();
  }

  async function request<T>(path: string, query?: Record<string, QueryValue>, body?: unknown): Promise<T> {
    const requestGeneration = generation;
    if (!credential) throw new ApiError("请先登录管理员会话", 401, path);
    try {
      const result = await apiRequest<T>(path, { query, body, credential });
      if (requestGeneration !== generation) throw new ApiError("管理员会话已变更", 401, path);
      return result;
    } catch (error) {
      if (requestGeneration === generation && error instanceof ApiError && error.status === 401) logout();
      throw error;
    }
  }

  async function stream(
    path: string,
    signal: AbortSignal,
    onEvent: (name: string, data: string) => void,
    onActivity?: () => void,
  ): Promise<void> {
    if (!credential) throw new ApiError("请先登录管理员会话", 401, path);
    if (signal.aborted) return;
    const streamGeneration = generation;
    const controller = new AbortController();
    const stop = () => controller.abort();
    streams.add(controller);
    signal.addEventListener("abort", stop, { once: true });
    try {
      await openEventStream(path, {
        credential,
        signal: controller.signal,
        onEvent: (name, data) => {
          if (!controller.signal.aborted && streamGeneration === generation) onEvent(name, data);
        },
        onActivity: () => {
          if (!controller.signal.aborted && streamGeneration === generation) onActivity?.();
        },
      });
    } catch (error) {
      if (streamGeneration === generation && error instanceof ApiError && error.status === 401) logout();
      throw error;
    } finally {
      signal.removeEventListener("abort", stop);
      streams.delete(controller);
    }
  }

  return { adminName, capabilities, isAuthenticated, landingPath, sessionRevision, can, login, logout, request, stream };
});
