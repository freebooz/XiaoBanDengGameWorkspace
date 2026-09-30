# Chess Texture and Perspective Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Use the latest supplied board image without local distortion and match the requested perspective game view.

**Architecture:** Project the bitmap onto the board with a single affine UV transform. Register geometry and game picking to the image grid, storing the physical grid arrays in the GLB extras. Both player cameras use the same perspective settings at opposite azimuths.

**Tech Stack:** Blender MCP, Blender 5.2, Python, glTF, Godot 4.7.

**Spec:** User instructions and attached references in this chat, most recently `codex-clipboard-3d5064aa-4bef-4a0a-882e-3f77d1e88161.png` and camera reference `codex-clipboard-ccf42a98-a8ca-4bf7-87b1-df1518ada765.png`.

## Global Constraints

- Keep the board at 412 × 452 × 6 mm and pieces at 36 × 10 mm.
- Preserve 6 mm convex corner rounding, 28 mm outer piece clearance, real engraved board lines and the reduced board lacquer.
- Preserve the supplied image bytes and river text orientation.
- Modify the current user workspace; preserve unrelated work and do not commit or push.

## Review Focus

- Single affine mapping on every top face avoids triangulation dependent distortion.
- All 90 grid positions remain clickable from both player sides.
- Perspective framing keeps all four corners visible.
- Missing model extras retain the uniform fallback grid.
- Packed and game imported images reflect the latest source rather than cached prior images.

### Task 1: Continuous Board Mapping

**Files:** `build_chess_set.py`, `audit_board_uv.py`, `check_latest_visual_contract.py`, `validate_chess_set.py` under `SourceAssets/Blender/ChineseChess/`.

**Interfaces:** Produce GLB extras `grid_x_m` (9 ascending floats), `grid_y_m` (10 descending floats).

- [ ] Verify the current mesh fails a < 0.01 pixel affine UV residual assertion.
- [ ] Replace piecewise UV interpolation, register the engraved geometry and preview pieces to the source grid, export extras and atomically save through Blender MCP.
- [ ] Reopen the saved model independently and verify UV residual, exact image bytes, geometry, margins, grooves and finishes.

### Task 2: Perspective View and Picking

**Files:** `client/games/chinese_chess/chinese_chess_3d_screen.gd`, `SourceAssets/Blender/ChineseChess/verify_game_assets.gd`.

**Interfaces:** Consume the GLB grid arrays; `_board_to_world(Vector2i)` and `_screen_to_board(Vector2)` retain existing callers.

- [ ] Verify the current camera fails the perspective assertion.
- [ ] Use perspective projection, 45° FOV, 13.7 height over the board and 6.05 orbit radius. Load validated GLB grid arrays and use nearest registered intersection for picking.
- [ ] Verify 180 projected picks, perspective front/rear width ratio around 1.30, all four visible corners, 14 masters and 32 pieces.
- [ ] Inspect both rendered views and launch two updated interactive clients. Record evidence and update the asset README.

### Task 3: Render Quality Menu (user addition)

**Files:** `client/games/chinese_chess/chinese_chess_3d_screen.gd`, `client/games/chinese_chess/tests/render_quality_smoke.gd`.

**Interfaces:** Menu selection applies immediately; `user://chinese_chess_visuals.cfg` persists integer quality 0–2. Camera and picking use the actual SubViewport resolution.

- [ ] Verify the current screen fails the missing quality settings test.
- [ ] Add low (750×855 / 2× MSAA / no shadows), medium (1000×1140 / 4× MSAA), high (1500×1710 / 8× MSAA), default medium. Preserve materials and perspective.
- [ ] Verify three selections reload, all 540 projected picks, and menu controls fit portrait and landscape.

### Task 4: Reference Duel Screen (later user correction)

**Files:** `client/games/chinese_chess/chinese_chess_3d_screen.gd`, `client/games/chinese_chess/assets/ui/mobile/brand_stool_3d.png`, `client/games/chinese_chess/tests/duel_layout_smoke.gd`.

**Interfaces:** Portrait order brand and quick controls, own card, board, opponent card, six actions in one row. Existing gameplay and quality menu remain intact.

- [ ] Verify the old portrait layout fails the design geometry test.
- [ ] Build the reference-inspired interactive layout with the generated stool asset, black/gold cards, round actions and preserved live player data.
- [ ] Verify 450×800 and 720×1280 screenshots, controls, board size, projection/picking, and actual running client.

## Evidence ledger

- Task 1: RED affine UV residual 21.54 pixels; GREEN saved mesh residual 0.00009 pixels, exact packed image hash and 120 structure checks passed.
- Task 2: RED orthographic camera; GREEN perspective FOV 45°, front/rear ratio 1.3017, 180 picks, 14 imported masters, 32 pieces, all corners visible.
- Latest bitmap: `codex-clipboard-3d5064aa-4bef-4a0a-882e-3f77d1e88161.png`, SHA-256 EC7B2623FD1A0C9FBB974645847CEB95CD824B02EFC7A0D5DC18CF1EE6C27EAF.
