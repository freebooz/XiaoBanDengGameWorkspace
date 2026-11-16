# Mahjong Port Implementation Plan

> **For agentic workers:** Execute this plan in the current session. Keep the Unreal project read only.

**Goal:** Bring the Unreal Guiyang Mahjong game into the Xiaobandeng Godot and Go platform as a playable four player online product.

**Architecture:** Go owns the wall, private hands, turns, reaction windows, and settlement. Existing matchmaking gains a four seat mode while retaining the two seat chess contract. The Godot product shell passes the assigned seat to a Mahjong screen that renders source art and sends only action intentions.

**Tech Stack:** Go 1.23, Gorilla WebSocket, Godot 4 GDScript, source PNG art from `E:\work\Game\MahjongGame`.

**Spec:** `E:\work\Game\MahjongGame\Source\GuiyangMahjongCore\Public\Core\MahjongTypes.h` and `Private\Table\MahjongTableEngine.cpp` (read only source).

## Global Constraints

- Four seats, 108 suited tiles, dealer starts with 14 and others with 13.
- Turn order is seat index + 1 modulo 4; no Chi in the default rule set.
- The server must never send another player's concealed hand or the future wall to a client.
- Preserve the Chinese chess two player room and real time protocol.
- Reuse source visual assets and verify the generated Mahjong Godot product.

## Review Focus

- A third and fourth Mahjong player must enter the same room, while a fifth enters another room.
- A player cannot discard a tile ID that is absent from their hand.
- One client's state must contain only that client's concealed tiles.
- Two simultaneous claims on a discard must resolve by the source priority order.
- A disconnected player must be able to reconnect without changing their seat or restarting the wall.

---

### Task 1: Four seat matchmaking

**Files:** `server/internal/platform/matchmaking/manager.go`, `manager_test.go`, `client/app_shell/scripts/main.gd`.

- [x] Add a failing test for four Mahjong seats, ready count, and fifth player isolation.
- [x] Implement game specific capacity and stable seat indices without changing chess JSON semantics.
- [x] Run the matchmaking tests.

### Task 2: Authoritative Guiyang rules and game

**Files:** `server/internal/game/mahjong/guiyang/rules.go`, `rules_test.go`, `game.go`, `game_test.go`.

- [x] Add failing tests for the 108 tile wall, standard hand, seven pairs, unique IDs, legal discard, reaction priority, and hand secrecy.
- [x] Implement the four seat engine and private snapshots.
- [x] Run package tests.

### Task 3: WebSocket integration

**Files:** `server/internal/httpapi/mahjong_realtime.go`, `server/internal/httpapi/server.go`, realtime tests.

- [x] Add join and reconnect tests, including private snapshots.
- [x] Bind WebSocket accounts to authoritative matchmaking seats and broadcast private snapshots.
- [x] Run HTTP API tests.

### Task 4: Godot client and migrated art

**Files:** `client/games/mahjong/guiyang/*`, `client/app_shell/scripts/main.gd`, `client/games/mahjong/guiyang/assets/*`.

- [x] Copy the source tile faces and table art with their original names.
- [x] Replace the placeholder with a four seat live table, hand selection, and action controls.
- [x] Compose the Mahjong product, inspect parser output, and run multiple local clients through one room.

### Task 5: Final verification

- [x] Run the Go suite, build the server, launch the Godot product, and check four clients through the opening turns; verify full timeout settlement in the engine test.
- [x] Report implemented rules, visual evidence, and any source feature that remains unported.
