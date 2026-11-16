# Unified Landscape Battles Implementation Plan

> Execute the authorized redesign in the current workspace. Independent game layouts use the shared visual/display contract below; preserve existing models and rule protocols.

**Goal:** Redesign chess, mahjong, Landlord and Guandan battle screens as polished mobile landscape interfaces; change black poker ink to blue in the canonical library.

**Architecture:** `foundation/ui/battle_display.gd` temporarily sets 1440×810 landscape presentation and restores the lobby when the last battle closes. `battle_chrome.gd` owns shared dark jade backdrop, warm gold panels/buttons and avatars. Game scripts own model camera framing, seats, picking, actions and settlements.

**Display contract:** call `DISPLAY.enter(self)` at battle `_ready` and `DISPLAY.leave(self)` at `_exit_tree`. Existing login/lobby baseline stays intact. Layouts use actual Control.size, fit all buttons, keep board viewport aspect identical to its TextureRect, and isolate each viewport's World3D.

**Chrome contract:** preload `res://modules/foundation/ui/battle_chrome.gd`; `backdrop(parent,title,room)`, `style(bg,border,radius)`, `skin_button(button,primary,danger)`, `player(parent,title,detail,Rect2,active,portrait_index)`, `label(parent,text,Rect2,font_size,color)`. Public shared assets are in foundation/ui/battle_assets.

## Tasks

- [x] Create shared visual and orientation helpers, preserve lobby restoration, regenerate blue poker suits and small joker.
- [x] Redesign chess with large center board, opponent above own player, right action column and readable timers/modals.
- [x] Redesign mahjong with wide 3D table, four seats, clear own tiles and reaction buttons.
- [x] Redesign common poker and Guandan with wide 3D table, independent hands, clear seat cards/actions/settlements.
- [x] Compose four products, verify real rendering at phone/tablet/PC landscape sizes, check picking and full game/lobby flows.

## Verification focus

- Native portrait window enters a landscape battle and returns to its original lobby display.
- No board/table texture stretching, no hidden or overlapping buttons; mouse and touch still pick the correct model.
- Mahjong reaction and poker bid/tribute/return/settlement controls remain available.
- Shared black suits become blue for both poker games, red suits remain red.
- Multiple clients retain independent 3D worlds and private hands.

## User amendment: Landlord reference and functional controls

The user supplied a lakeside pavilion / warm wood table reference and explicitly requested actual button logic. The Landlord subclass owns this presentation; other poker games keep their own landscape screen and the canonical models.

- [x] Generate a clean garden background, retain real 3D table/cards and arrange reference header, opponent sides, large bottom hand, colored action row and social toolbar.
- [x] Implement service-authoritative optional doubling phase, legal hints, bounded room chat/emote/prop/voice events and server action deadlines; preserve default rules constructor compatibility.
- [x] Implement real settings, free cosmetic selection saved locally, actual local settlement history, sort/collapse/exit flow, microphone capture and PCM playback.
- [x] Verify button actions and invalid operations, actual touch dispatch, server rules and three-client room/training flows. Capture final device-size rendering.

## Completion evidence

See `docs/LANDSCAPE_UI.md` and `docs/LANDLORD.md`. Final native Landlord room 7852 completed with three clients, bid/double/chat/hint/play/pass/settlement/history/lobby restoration. Final Guandan room 1431 verified four clients and 108 private cards. Native five-second voice clips passed both 8000 and 16000 Hz transport. Physical Android microphone and device performance remain device acceptance items; window-ratio renders are Windows evidence.
