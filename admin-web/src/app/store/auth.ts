import { ref } from "vue";
import { defineStore } from "pinia";
import { ApiError } from "../../services/api/client";
import { getAdminSession, loginAdmin, logoutAdmin, type AdminSession } from "../../services/api/auth";

/** 管理员身份只保存在内存中，所有授权均来自服务端 cookie 会话。 */
export const useAuthStore = defineStore("auth", () => {
  const isAuthenticated = ref(false);
  const adminName = ref("");
  const expiresAt = ref("");
  const sessionChecked = ref(false);
  const sessionError = ref("");
  let pendingRestore: Promise<void> | undefined;
  // 身份操作的代次用于忽略登录、清理或注销之前发出的旧恢复响应。
  let sessionRevision = 0;

  /** 只读获取当前身份代次，供请求边界识别已经过时的业务响应。 */
  function getSessionRevision(): number { return sessionRevision; }

  /** 清理页面身份，同时标记本次会话检查完成，避免 401 导航循环。 */
  function clearSession(): void {
    sessionRevision += 1;
    pendingRestore = undefined;
    isAuthenticated.value = false;
    adminName.value = "";
    expiresAt.value = "";
    sessionError.value = "";
    sessionChecked.value = true;
  }

  /** 仅接受已由接口层校验的管理员身份。 */
  function applySession(session: AdminSession): void {
    // 成功授权也开启新代次，隔离登录完成前发出的未授权请求。
    sessionRevision += 1;
    adminName.value = session.username;
    expiresAt.value = session.expires_at;
    isAuthenticated.value = true;
    sessionError.value = "";
    sessionChecked.value = true;
  }

  /** 首次导航恢复会话，并合并并发检查；失败信息供登录页重试展示。 */
  async function restoreSession(force = false): Promise<void> {
    if (pendingRestore) return pendingRestore;
    if (isAuthenticated.value && Date.parse(expiresAt.value) <= Date.now()) {
      clearSession();
      sessionChecked.value = false;
    }
    if (sessionChecked.value && !force) return;
    const revision = sessionRevision;
    const restoration = (async () => {
      try {
        const session = await getAdminSession();
        if (revision === sessionRevision) applySession(session);
      } catch (error) {
        if (revision !== sessionRevision) return;
        clearSession();
        if (!(error instanceof ApiError && error.status === 401)) {
          sessionError.value = error instanceof Error ? error.message : "会话恢复失败，请重试";
        }
      }
    })();
    pendingRestore = restoration;
    try { await restoration; } finally {
      if (pendingRestore === restoration) pendingRestore = undefined;
    }
  }

  /** 服务端确认登录成功后才授予页面访问，不保留密码。 */
  async function login(username: string, password: string): Promise<void> {
    clearSession();
    const revision = sessionRevision;
    const session = await loginAdmin(username, password);
    if (revision === sessionRevision) applySession(session);
  }

  /** 注销失败时保留身份供重试，401 说明服务端会话已经失效。 */
  async function logout(): Promise<void> {
    try {
      await logoutAdmin();
    } catch (error) {
      if (!(error instanceof ApiError && error.status === 401)) throw error;
    }
    clearSession();
  }

  return { isAuthenticated, adminName, expiresAt, sessionChecked, sessionError, getSessionRevision, clearSession, restoreSession, login, logout };
});
