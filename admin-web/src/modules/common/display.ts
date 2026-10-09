/** formatDate（时间展示）固定中文与北京时间；缺失或非法时间不输出 Invalid Date（无效日期）。 */
export function formatDate(value: string | null | undefined, missing = "—"): string {
  if (!value) return missing;
  const date = new Date(value);
  return Number.isFinite(date.getTime())
    ? date.toLocaleString("zh-CN", { timeZone: "Asia/Shanghai", hour12: false })
    : "时间异常";
}

/** formatDuration（时长展示）保留秒级精度，不把缺失时长显示成确定的零。 */
export function formatDuration(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds < 0) return "时间异常";
  const total = Math.floor(seconds);
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  return `${hours ? hours + "小时" : ""}${minutes ? minutes + "分" : ""}${total % 60}秒`;
}

/** matchDuration（确定对局时长）只用已存在的开始和结束时间，进行中的对局不伪造结束时刻。 */
export function matchDuration(start: string | null, finish: string | null): string {
  if (!start) return "未开始";
  if (!finish) return "待结束";
  return formatDuration((new Date(finish).getTime() - new Date(start).getTime()) / 1000);
}

/** categoryLabel（游戏类别）保留未知目录值，方便扩展产品而不丢失服务端语义。 */
export function categoryLabel(value: string): string {
  const labels: Record<string, string> = { board: "棋类", tile: "麻将类", mahjong: "麻将类", card: "牌类" };
  return `${labels[value] ?? "其他类别"}（${value}）`;
}

/** formatJSON（结构化数据展示）仅生成文本，由 Vue 插值转义，不解释为 HTML（网页标记）。 */
export function formatJSON(value: unknown): string {
  return JSON.stringify(value, null, 2) ?? "无内容";
}
