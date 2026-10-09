import { onScopeDispose, ref, shallowRef } from "vue";
import { ApiError } from "../../services/api/client";

/** useReadOnlyQuery（只读查询状态）统一错误、加载态与并发响应隔离，不回退到开发数据。 */
export function useReadOnlyQuery<T>() {
  const data = shallowRef<T | null>(null);
  const loading = ref(false);
  const errorMessage = ref("");
  let generation = 0;

  /** clear（清理查询）使关闭抽屉或离开页面前的未完成响应失效。 */
  function clear(): void {
    generation += 1;
    data.value = null;
    errorMessage.value = "";
    loading.value = false;
  }

  /** run（执行只读查询）只有最新请求可以更新状态，失败与空数据保持可区分。 */
  async function run(loader: () => Promise<T>): Promise<void> {
    const current = ++generation;
    loading.value = true;
    errorMessage.value = "";
    data.value = null;
    try {
      const result = await loader();
      if (current === generation) data.value = result;
    } catch (error) {
      if (current !== generation) return;
      errorMessage.value = error instanceof ApiError && error.status === 0
        ? `服务离线或连接异常：${error.message}`
        : error instanceof Error ? error.message : "数据加载失败，请重试";
    } finally {
      if (current === generation) loading.value = false;
    }
  }

  onScopeDispose(clear);
  return { data, loading, errorMessage, run, clear };
}
