# Real Mahjong Tiles Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline; request one fresh review after the asset and runtime checks.

**Goal:** Replace the simplified tiles with the actual source project's rounded solid Mahjong50 geometry and physically plausible resin and engraved face materials.

**Architecture:** Import the existing read-only diagnostic FBX and four PBR atlas maps from `E:/work/Game/MahjongGame/Saved/Diagnostics/Mahjong50`. Convert the standing source mesh to the game's face-up convention without stretching its 36 × 50 × 26 mm shape. Preserve the green layer vertex mask, use one canonical body and shared 34-face PBR atlas, and keep game selection/hidden-hand behavior.

**Tech Stack:** Blender 5.2.1, glTF, Godot 4.7.2 Vulkan.

**Spec:** User request for real tile models and materials with permission to import, existing green/ivory tile reference in `docs/MAHJONG_REFERENCE_UI.md`.

## Global Constraints

- Read source project; write only this workspace.
- Keep 108-tile gameplay, hidden opponents, 14 selectable hand tiles, three quality levels, and current mobile landscape flow.
- Saved source and GLB must be independently reopened; visual acceptance requires real renders.
- Preserve existing uncommitted work and do not commit or push.

## Review Focus

- Correct front orientation and UV atlas row/column, especially nine bamboo and eight dots.
- Joined body/face closed shell, no overlapping face overlay or default grey vertex mask.
- Resin highlights must preserve red/green/black ink contrast.
- Hidden tiles must not reveal faces, including side seats.
- Hand selection and geometry containment on phone/tablet/PC.

### Task 1: Imported source and saved asset

- [x] Add independent geometry/UV/material/provenance assertions and observe old asset fail.
- [x] Import actual FBX, preserve UV/mask; build resin/PBR nodes and export one canonical tile.
- [x] Reopen saved blend and GLB independently, validate dimensions, welded closure, UV orientation, mask and embedded normals.
- [x] Render front/back/side close-up and inspect visually.

### Task 2: Runtime materials and integration

- [x] Use shared atlas base color, normal and ORM maps, no UI card overlay; provide green/ivory resin body shader.
- [x] Preserve hand apparent width while using correct source dimensions; verify own and concealed poses.
- [x] Run native Vulkan hand/control smoke and render phone/tablet/PC; add asset-specific orientation/material checks.
- [x] Request fresh review, fix concrete findings, document source hashes and outcomes.

## Rulings and progress

- Existing source project's saved diagnostic FBX is available (668 vertices / 1332 triangles, 36 × 50 × 26 mm). This removes the need to start Unreal or reconstruct from `.uasset`.
- Work in the existing active checkout to retain all already integrated UI and model changes; create no detached alternate copy.
- Landlord five-button image replacement is a separate authorized user follow-up and delegated to an independent agent with disjoint files.
- Explicit mask name/render index fixes glTF export's default white COLOR_0 plus second-channel mask; native test verifies the actual imported COLOR_0 range.
- Source smooth flags remain on both front triangles. A fresh reviewer reproduced the diagonal seam caused by changing smooth flags after custom normal assignment; saved normal continuity now passes and the render seam is removed.
- Source normal channels quantitatively agree with height gradients (correlations ~0.95), so green-channel flipping would be incorrect.
- Fresh reviewer rechecked the regenerated saved assets and nested manifest hashes: no remaining findings. Final Vulkan logs: `.tmp/real_mahjong_native_smoke_final.log`, `.tmp/real_mahjong_screen_{pc,phone,tablet}_final.log`. Original source remains unchanged.
