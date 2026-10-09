/** 座位与结果只翻译已知服务端编码；未知值保留，方便检查新规则。 */
export function seatLabel(value: string): string {
  return ({ red: "红方", black: "黑方", spectator: "观战", draw: "和棋" } as Record<string, string>)[value] ?? value;
}

export function resultReasonLabel(value: string): string {
  return ({ checkmate: "将死", general_captured: "将帅被吃", player_disconnected: "玩家断线", resign: "认输", draw: "和棋" } as Record<string, string>)[value] ?? value;
}
