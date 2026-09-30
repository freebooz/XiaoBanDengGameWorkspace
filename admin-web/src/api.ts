import { platformApi } from "./services/api/admin";
export type { GameDescriptor, HealthStatus } from "./services/api/types";

/**
 * api（兼容入口）保留旧调用名，新增页面统一使用 services/api。
 * 后续旧代码清理完成后可删除本文件。
 */
export const api = {
  health: platformApi.health,
  catalog: platformApi.catalog,
  aiCapabilities: platformApi.aiCapabilities,
};
