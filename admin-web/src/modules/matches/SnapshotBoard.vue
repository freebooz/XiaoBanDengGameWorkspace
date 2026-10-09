<script setup lang="ts">
import { computed } from "vue";

interface SnapshotPiece { id: string; type: string; color: string; x: number; y: number }
const props = defineProps<{ snapshot: unknown }>();

// 棋盘来源只限持久化快照的有效坐标；未知格式由外层 JSON 原样展示。
const pieces = computed<SnapshotPiece[] | null>(() => {
  if (!props.snapshot || typeof props.snapshot !== "object" || !("pieces" in props.snapshot)) return null;
  const value = props.snapshot.pieces;
  if (!Array.isArray(value)) return null;
  if (!value.every((piece) => piece && typeof piece === "object"
    && typeof piece.id === "string" && typeof piece.type === "string" && typeof piece.color === "string"
    && Number.isInteger(piece.x) && piece.x >= 0 && piece.x <= 8
    && Number.isInteger(piece.y) && piece.y >= 0 && piece.y <= 9)) return null;
  return value as SnapshotPiece[];
});
const cells = computed(() => Array.from({ length: 90 }, (_, index) => {
  const x = index % 9;
  const y = Math.floor(index / 9);
  return { x, y, piece: pieces.value?.find((piece) => piece.x === x && piece.y === y) };
}));
function pieceLabel(piece: SnapshotPiece): string {
  const red: Record<string, string> = { general: "帅", advisor: "仕", elephant: "相", horse: "马", chariot: "车", cannon: "炮", soldier: "兵" };
  const black: Record<string, string> = { general: "将", advisor: "士", elephant: "象", horse: "马", chariot: "车", cannon: "炮", soldier: "卒" };
  return (piece.color === "red" ? red : black)[piece.type] ?? piece.type;
}
</script>

<template>
  <figure v-if="pieces !== null" class="snapshot-figure">
    <figcaption>只读棋盘 · 黑方在上，红方在下</figcaption>
    <div class="snapshot-board" data-testid="replay-board" role="img" aria-label="快照棋盘，黑方在上、红方在下">
      <span v-for="cell in cells" :key="cell.y * 9 + cell.x" class="snapshot-cell" :title="`坐标 ${cell.x},${cell.y}${cell.piece ? ' · ' + cell.piece.id : ''}`">
        <span v-if="cell.piece" class="snapshot-piece" :class="{ 'snapshot-piece-red': cell.piece.color === 'red' }">{{ pieceLabel(cell.piece) }}</span>
      </span>
    </div>
  </figure>
</template>

<style scoped>
.snapshot-figure { margin: 12px 0; }
.snapshot-figure figcaption { margin-bottom: 8px; font-size: 11px; color: var(--xbd-text-secondary); }
.snapshot-board { display: grid; grid-template-columns: repeat(9, minmax(0, 1fr)); max-width: 360px; width: 100%; border: 1px solid var(--xbd-border); background: var(--xbd-page-bg); }
.snapshot-cell { min-width: 0; aspect-ratio: 1; display: flex; align-items: center; justify-content: center; border: 1px solid var(--xbd-border); }
.snapshot-piece { display: flex; align-items: center; justify-content: center; width: 80%; aspect-ratio: 1; border: 1px solid currentColor; border-radius: 50%; font-size: 12px; font-weight: 600; overflow-wrap: anywhere; }
.snapshot-piece-red { color: #c34343; }
</style>
