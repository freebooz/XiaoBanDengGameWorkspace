import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createPinia, setActivePinia } from "pinia";
import { useAuthStore } from "../../app/store/auth";

// 服务端响应允许乱序到达，旧恢复请求不能覆盖新登录或复活已清理身份。
const session = { username: "test-reader", role: "readonly", expires_at: "2099-01-01T00:00:00Z" };
function response(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), { status, headers: { "Content-Type": "application/json" } });
}
function deferredResponse() {
  let resolve!: (value: Response) => void;
  const promise = new Promise<Response>((done) => { resolve = done; });
  return { promise, resolve };
}

describe("管理员会话响应代次", () => {
  beforeEach(() => { setActivePinia(createPinia()); });
  afterEach(() => { vi.unstubAllGlobals(); });
  it("迟到的恢复401不能清掉更新的成功登录", async () => {
    const oldRestore = deferredResponse();
    vi.stubGlobal("fetch", vi.fn().mockReturnValueOnce(oldRestore.promise).mockResolvedValue(response(session)));
    const auth = useAuthStore();
    const restoring = auth.restoreSession(true);
    await auth.login("test-reader", "test-password");
    expect(auth.isAuthenticated).toBe(true);
    oldRestore.resolve(response({ error: "旧会话已过期" }, 401));
    await restoring;
    expect(auth.isAuthenticated).toBe(true);
    expect(auth.adminName).toBe("test-reader");
    expect(auth.sessionError).toBe("");
  });
  it("主动清理身份后迟到的恢复成功不能重新授权", async () => {
    const oldRestore = deferredResponse();
    vi.stubGlobal("fetch", vi.fn().mockReturnValue(oldRestore.promise));
    const auth = useAuthStore();
    const restoring = auth.restoreSession(true);
    auth.clearSession();
    oldRestore.resolve(response(session));
    await restoring;
    expect(auth.isAuthenticated).toBe(false);
    expect(auth.adminName).toBe("");
  });
  it("注销成功后迟到的恢复成功不能复活会话", async () => {
    const oldRestore = deferredResponse();
    vi.stubGlobal("fetch", vi.fn().mockResolvedValueOnce(response(session)).mockReturnValueOnce(oldRestore.promise).mockResolvedValue(new Response(null, { status: 204 })));
    const auth = useAuthStore();
    await auth.restoreSession();
    const restoring = auth.restoreSession(true);
    await auth.logout();
    oldRestore.resolve(response(session));
    await restoring;
    expect(auth.isAuthenticated).toBe(false);
    expect(auth.adminName).toBe("");
  });
});
