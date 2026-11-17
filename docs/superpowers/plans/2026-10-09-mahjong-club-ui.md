# Mahjong Club Reference UI Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans for UI changes and a fresh final reviewer. Bitmap assets are delegated independently.

**Goal:** Match the latest black/gold/emerald Mahjong reference using live 3D geometry and authoritative game data.

**Architecture:** Retain current networking, legal responses, voice lifecycles, 108-tile Guiyang rules and canonical tile asset. Replace the garden chrome and table overrides with a dark club presentation, standing concealed hands, upright own hand, projected octagonal compass/timer, cut-corner player cards, selected-tile glow and five asset-backed circular controls. Keep adaptive phone/tablet/PC layout and persistent quality settings.

**Spec:** User image `codex-clipboard-f9f8c07b-4aab-4fa0-aaea-dcaf1e9cf74a.png` (2026-10-09).

## Global Constraints

- Room numbers remain four digits and current 108-tile rules remain authoritative; do not invent eight rounds, wind rounds, fake ping/wealth or honors.
- Continue actual 3D tile selection and live table; no screenshot-as-game-surface.
- Self player below, opponent above; complete printed faces must remain unobstructed.
- Stable self microphone and response/play callbacks must survive snapshots and resizing.
- Work in current active checkout to preserve prior integrated models/UI; no commits or reset.

## Review Focus

- 14 complete hand faces and GUI hit targets across three quality levels and PC/phone/tablet ratios.
- Upright tiles' bounds, especially concealed side/back hands and selected own tile.
- Countdown based on server deadline, not remaining tiles; center compass does not hide public discards.
- Offline/sending/illegal response restrictions and long-press voice through snapshots.
- Generated asset alpha boundaries, readable small glyphs, no hard-coded false room/rule/ping labels.

### Task 1: Visual components and reference assets

- [x] Preserve reference bitmap in project for native portrait regions and generated transparent logo.
- [x] Generate empty club backdrop and transparent circular response sprites; record prompts.
- [x] Add cut-corner/compass/selection decoration with native drawing and semantic child controls.

### Task 2: Live 3D presentation and responsive UI

- [x] Replace garden layout with brand/top session bar, four dark player cards, voice/chat tools, right-lower circular actions and selected-hand indicator.
- [x] Use dark bronze/gold frame and emerald textured felt; fit perspective camera and upright hands to reference.
- [x] Show authoritative remaining count/header/turn countdown and preserve legal response behavior.

### Task 3: Validation and handoff

- [x] Run existing actual input/connection/voice/settings tests and add reference-specific layout/state assertions.
- [x] Render native PC, 844x390 phone and 1024x768 tablet, compare with reference, fix concrete differences.
- [x] Fresh independent review, fix findings, document actual checks and preview paths.

## Completion evidence

2026-10-09: All seven final native test logs (`.tmp/mahjong_club_*_final.log`) pass with no script errors or shutdown leaks. Reference cases cover standing-hand bounds, true countdown/data, selected outline, stable microphone, legal Hu emphasis, and 16 public kong faces clear of the hand silhouette, player cards, discards, compass and actions. Input cases cover all hand faces, touch deduplication, quality, dynamic resizing, training and exit. Buttons include duplicate submission while pending and retry on server rejection. Fresh independent review passed after closing own-meld occlusion and duplicate-submit findings. Current evidence is Windows native rendering and fixtures; prior multiplayer evidence and outstanding physical-device acceptance are distinguished in `docs/MAHJONG_REFERENCE_UI.md`.
