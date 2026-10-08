# Unified Landscape Battles Implementation Plan

> Execute the authorized redesign in the current workspace. Independent game layouts use the shared visual/display contract below; preserve existing models and rule protocols.

**Goal:** Redesign chess, mahjong, Landlord and Guandan battle screens as polished mobile landscape interfaces; change black poker ink to blue in the canonical library.

**Architecture:** `foundation/ui/battle_display.gd` temporarily sets 1440×810 landscape presentation and restores the lobby when the last battle closes. `battle_chrome.gd` owns shared dark jade backdrop, warm gold panels/buttons and avatars. Game scripts own model camera framing, seats, picking, actions and settlements.

**Display contract:** call `DISPLAY.enter(self)` at battle `_ready` and `DISPLAY.leave(self)` at `_exit_tree`. Existing login/lobby baseline stays intact. Layouts use actual Control.size, fit all buttons, keep board viewport aspect identical to its TextureRect, and isolate each viewport's World3D.

**Chrome contract:** preload `res://modules/foundation/ui/battle_chrome.gd`; `backdrop(parent,title,room)`, `style(bg,border,radius)`, `skin_button(button,primary,danger)`, `player(parent,title,detail,Rect2,active,portrait_index)`, `label(parent,text,Rect2,font_size,color)`. Public shared assets are in foundation/ui/battle_assets.

## Tasks

- [ ] Create shared visual and orientation helpers, preserve lobby restoration, regenerate blue poker suits and small joker.
- [ ] Redesign chess with large center board, opponent above own player, right action column and readable timers/modals.
- [ ] Redesign mahjong with wide 3D table, four seats, clear own tiles and reaction buttons.
- [ ] Redesign common poker and Guandan with wide 3D table, independent hands, clear seat cards/actions/settlements.
- [ ] Compose four products, verify real rendering at phone/tablet/PC landscape sizes, check picking and full game/lobby flows.

## Verification focus

- Native portrait window enters a landscape battle and returns to its original lobby display.
- No board/table texture stretching, no hidden or overlapping buttons; mouse and touch still pick the correct model.
- Mahjong reaction and poker bid/tribute/return/settlement controls remain available.
- Shared black suits become blue for both poker games, red suits remain red.
- Multiple clients retain independent 3D worlds and private hands.
