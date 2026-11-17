# Shared bamboo panel frame

Approved source: `codex-clipboard-8a8ade2c-b366-4708-bdae-f0b57c67ba99.png`, supplied by the user on 2026-11-15.

`bamboo_frame_approved.png` is a byte-identical copy of that source. SHA256:
`4509544041B39BE302032ADE3EF4C7CD8F2C32B19055AC7251C9A575FEA69CFF`.
The 1254 × 1254 PNG already has alpha transparency. The apparent black center is transparent; no color key, recoloring, sharpening, or generative repaint was applied.

## Rendering contract

- Single shared texture: `mahjong_rural_modal.gd::VILLAGE_FRAME`.
- Source region: `(0, 0, 1254, 1200)`. The unused bottom 54 pixels are transparent padding; the file itself remains intact.
- Nine-slice source margins, left/top/right/bottom: **360 / 260 / 320 / 280 pixels**. These contain the complete corner ropes and the upper-left/lower-right leaves.
- `foundation/ui/nine_patch_panel_style.gd` sets the corner scale independently of the panel's content height. Four corners scale uniformly; only edge spans extend. Edge strips repeat to keep the bamboo joints recognisable on tall and wide panels.
- The center slice is not drawn. A separate shared paper texture is tiled at native density inside the rounded frame. Paper geometry is clipped without modifying the source pixels.
- `village_panel()` and the legacy `paper_frame()` factory both use the same shared surface. No per-page frame copy is needed.
- Title plaques remain separate native controls. `overlapping_panel_title.gd` tracks the frame's actual upper bamboo center through `title_border_offset`; titles overlap the upper edge when the viewport changes.

The old `bamboo_frame.png` is retained as prior artwork, but production Mahjong scripts no longer reference it. Interactive text, status, scores, and actions are rendered by Godot controls.
