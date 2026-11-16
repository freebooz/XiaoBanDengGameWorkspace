import { afterEach, describe, expect, it, vi } from "vitest";
import { openEventStream } from "./client";

const encoder = new TextEncoder();

afterEach(() => vi.unstubAllGlobals());

describe("管理员监视事件流", () => {
  it("重组分段 UTF-8、CRLF 和多行事件，且凭据只通过请求头发送", async () => {
    const bytes = encoder.encode(': heartbeat\r\n\r\nevent: snapshot\r\ndata: {"name":\r\ndata: "贵阳麻将"}\r\n\r\n');
    const body = new ReadableStream<Uint8Array>({
      start(controller) {
        for (let i = 0; i < bytes.length; i += 2) controller.enqueue(bytes.slice(i, i + 2));
        controller.close();
      },
    });
    const fetch = vi.fn().mockResolvedValue(new Response(body, { headers: { "Content-Type": "text/event-stream; charset=utf-8" } }));
    vi.stubGlobal("fetch", fetch);
    const signal = new AbortController().signal;
    const onActivity = vi.fn();
    const onEvent = vi.fn();
    const credential = "s".repeat(43);

    await openEventStream("/api/v1/admin/monitor/stream", { credential, signal, onEvent, onActivity });

    expect(onEvent).toHaveBeenCalledExactlyOnceWith("snapshot", '{"name":\n"贵阳麻将"}');
    expect(onActivity).toHaveBeenCalled();
    const [url, request] = fetch.mock.calls[0];
    expect(new URL(url).pathname).toBe("/api/v1/admin/monitor/stream");
    expect(new URL(url).search).toBe("");
    expect(request).toMatchObject({ headers: { Authorization: "Bearer " + credential }, signal, cache: "no-store", redirect: "error" });
  });

  it("传播权限错误并拒绝普通 HTML 响应", async () => {
    vi.stubGlobal("fetch", vi.fn()
      .mockResolvedValueOnce(new Response(null, { status: 403 }))
      .mockResolvedValueOnce(new Response("<!doctype html>", { headers: { "Content-Type": "text/html" } })));
    const options = { credential: "s".repeat(43), signal: new AbortController().signal, onEvent: vi.fn() };

    await expect(openEventStream("/api/v1/admin/monitor/stream", options)).rejects.toMatchObject({ status: 403 });
    await expect(openEventStream("/api/v1/admin/monitor/stream", options)).rejects.toMatchObject({ status: 502 });
    expect(options.onEvent).not.toHaveBeenCalled();
  });
});
