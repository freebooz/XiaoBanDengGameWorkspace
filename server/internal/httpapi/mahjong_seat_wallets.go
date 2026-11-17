package httpapi

import (
	"context"
	"slices"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchmaking"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/wallet"
	"github.com/google/uuid"
)

type mahjongSeatProfile struct {
	wallet.EggProfile
	known bool
}

func (r *mahjongRoom) addSeatProfilesLocked(state map[string]any) {
	var eggs [4]*int64
	var names [4]*string
	for seat, profile := range r.seatProfiles {
		if profile.known {
			eggs[seat] = &profile.Amount
			if profile.DisplayName != "" {
				names[seat] = &profile.DisplayName
			}
		}
	}
	state["egg_counts"], state["player_names"] = eggs, names
	if r.eggDeltas != nil {
		state["egg_deltas"] = *r.eggDeltas
	}
}

func (r *mahjongRoom) refreshSeatProfilesLocked(h *mahjongHub) bool {
	changed, _ := r.loadSeatProfilesLocked(h, r.game.Phase == guiyang.PhaseFinished)
	return changed
}

// A terminal publication is gated on committed wallet reads. If the commit
// reply or following read fails, commitLocked retries the same completion
// receipt without paying twice, and keeps clients in the saving state.
func (r *mahjongRoom) loadSeatProfilesLocked(h *mahjongHub, settled bool) (bool, error) {
	if h.seatWallets == nil {
		return false, nil
	}
	players := r.game.Players[:]
	if r.kind == matchmaking.MahjongTraining {
		players = players[:1]
	}
	var accountsBySeat [4]string
	accountIDs := make([]string, 0, len(players))
	for seat, player := range players {
		if id, err := uuid.Parse(player); err == nil {
			accountID := id.String()
			accountsBySeat[seat] = accountID
			accountIDs = append(accountIDs, accountID)
		}
	}
	if len(accountIDs) == 0 {
		return false, nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	var deltas *[4]int64
	if settled && h.settlementEggDeltas != nil {
		var err error
		deltas, err = h.settlementEggDeltas(ctx, r.matchID)
		if err != nil {
			return false, err
		}
	}
	profiles, err := h.seatWallets(ctx, accountIDs)
	if err != nil {
		return false, err
	}
	var latest [4]mahjongSeatProfile
	for seat, accountID := range accountsBySeat {
		if profile, ok := profiles[accountID]; accountID != "" && ok {
			latest[seat] = mahjongSeatProfile{EggProfile: profile, known: true}
		}
	}
	changed := latest != r.seatProfiles
	r.seatProfiles, r.profilesLoaded = latest, true
	if settled {
		r.eggDeltas = deltas
	}
	return changed, nil
}

// Refresh from the database so concurrent grant responses cannot overwrite a
// newer balance with an earlier receipt. Normal gameplay uses the cached values.
func (h *mahjongHub) refreshWalletForPlayer(accountID string) {
	if h == nil || h.seatWallets == nil || h.stopping.Load() {
		return
	}
	h.mu.Lock()
	rooms := make([]*mahjongRoom, 0, len(h.rooms))
	for _, room := range h.rooms {
		if slices.Contains(room.assignment.PlayerAccountIDs, accountID) {
			rooms = append(rooms, room)
		}
	}
	h.mu.Unlock()
	for _, room := range rooms {
		room.mu.Lock()
		if len(room.clients) != 0 && slices.Contains(room.game.Players[:], accountID) && room.refreshSeatProfilesLocked(h) {
			room.broadcastLocked()
		}
		room.mu.Unlock()
	}
}
