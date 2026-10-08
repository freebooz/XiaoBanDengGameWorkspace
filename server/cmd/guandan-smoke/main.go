// Four real guest accounts complete two rounds, ranking, leveling, tribute and return.
package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/guandan"
	"github.com/gorilla/websocket"
)

type snapshot struct {
	Type             string          `json:"type"`
	Message          string          `json:"message"`
	Phase            string          `json:"phase"`
	Status           string          `json:"status"`
	Turn             int             `json:"turn"`
	YourSeat         int             `json:"your_seat"`
	Hand             []guandan.Card  `json:"hand"`
	HandCounts       [4]int          `json:"hand_counts"`
	LastPlay         guandan.Play    `json:"last_play"`
	HasLastPlay      bool            `json:"has_last_play"`
	Epoch            int             `json:"epoch"`
	Round            int             `json:"round"`
	LevelRank        int             `json:"level_rank"`
	TeamLevels       [2]int          `json:"team_levels"`
	FinishOrder      []int           `json:"finish_order"`
	ConnectedPlayers int             `json:"connected_players"`
	PendingSeats     []int           `json:"pending_seats"`
	EligibleIDs      []int           `json:"eligible_card_ids"`
	HandsRevealed    json.RawMessage `json:"hands_revealed"`
}

func post(base, path string, payload any) (map[string]any, error) {
	body, _ := json.Marshal(payload)
	client := http.Client{Timeout: 10 * time.Second}
	response, err := client.Post(base+path, "application/json", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	data, err := io.ReadAll(response.Body)
	if err != nil {
		return nil, err
	}
	var parsed map[string]any
	err = json.Unmarshal(data, &parsed)
	if err != nil {
		return nil, err
	}
	if response.StatusCode >= 300 {
		return nil, fmt.Errorf("%s: %s", path, data)
	}
	return parsed, nil
}

func next(conn *websocket.Conn, epoch, connected int) (snapshot, error) {
	_ = conn.SetReadDeadline(time.Now().Add(10 * time.Second))
	for {
		var state snapshot
		if err := conn.ReadJSON(&state); err != nil {
			return state, err
		}
		if state.Type == "guandan_error" {
			return state, fmt.Errorf("action rejected: %s", state.Message)
		}
		if state.Type == "guandan_state" && state.Epoch >= epoch && state.ConnectedPlayers >= connected {
			return state, nil
		}
	}
}

func run(base string) error {
	var accounts [4]string
	roomID := ""
	for seat := range accounts {
		result, err := post(base, "/api/v1/auth/guest", map[string]any{})
		if err != nil {
			return err
		}
		accounts[seat] = result["account_id"].(string)
		result, err = post(base, "/api/v1/matchmaking/quick", map[string]any{"account_id": accounts[seat], "product_id": "xbd_guandan", "game_id": "guandan", "rule_set_id": "classic_partnership", "rule_version": "1.0.0"})
		if err != nil {
			return err
		}
		id := result["room_id"].(string)
		if roomID != "" && roomID != id {
			return fmt.Errorf("different rooms")
		}
		roomID = id
	}
	if len(roomID) != 4 {
		return fmt.Errorf("room number is not four digits: %s", roomID)
	}
	for _, account := range accounts {
		if _, err := post(base, "/api/v1/matchmaking/ready", map[string]any{"account_id": account, "room_id": roomID}); err != nil {
			return err
		}
	}
	u, err := url.Parse(base)
	if err != nil {
		return err
	}
	u.Scheme = "ws"
	if base[:5] == "https" {
		u.Scheme = "wss"
	}
	u.Path = "/ws"
	var connections [4]*websocket.Conn
	var states [4]snapshot
	defer func() {
		for _, conn := range connections {
			if conn != nil {
				_ = conn.Close()
			}
		}
	}()
	for seat := range connections {
		conn, _, err := websocket.DefaultDialer.Dial(u.String(), nil)
		if err != nil {
			return err
		}
		connections[seat] = conn
		if err := conn.WriteJSON(map[string]any{"type": "guandan_join", "room_id": roomID, "client_id": accounts[seat]}); err != nil {
			return err
		}
		initial, err := next(conn, 1, seat+1)
		if err != nil {
			return err
		}
		if seat == 3 {
			states[seat] = initial
		}
	}
	for seat := 0; seat < 3; seat++ {
		states[seat], err = next(connections[seat], 1, 4)
		if err != nil {
			return err
		}
	}
	for seat, state := range states {
		if len(state.Hand) != 27 || len(state.HandsRevealed) > 0 {
			return fmt.Errorf("seat %d privacy/deal error", seat)
		}
	}
	exchanges := 0
	rounds := 0
	for actions := 0; actions < 1800; actions++ {
		current := states[0]
		seat := current.Turn
		action := map[string]any{"type": "guandan_action"}
		switch current.Phase {
		case "play":
			if len(states[seat].Hand) == 0 {
				return fmt.Errorf("empty active hand")
			}
			action["action"] = "pass"
			for _, card := range states[seat].Hand {
				var previous *guandan.Pattern
				if current.HasLastPlay {
					previous = &current.LastPlay.Pattern
				}
				if _, err := guandan.Choose([]guandan.Card{card}, current.LevelRank, previous); err == nil {
					action["action"] = "play"
					action["card_ids"] = []int{card.ID}
					break
				}
			}
		case "round_finished":
			if len(current.FinishOrder) != 4 {
				return fmt.Errorf("missing rank order")
			}
			if current.Round > rounds {
				rounds = current.Round
				fmt.Printf("ROUND_COMPLETE round=%d order=%v levels=%v actions=%d\n", rounds, current.FinishOrder, current.TeamLevels, actions)
			}
			if rounds >= 2 && exchanges > 0 {
				action["action"] = "leave"
				seat = 0
			} else {
				for i := 0; i < 4; i++ {
					seat = i
					action["action"] = "next_round"
					if err := connections[seat].WriteJSON(action); err != nil {
						return err
					}
					for j := range connections {
						states[j], err = next(connections[j], states[j].Epoch+1, 4)
						if err != nil {
							return err
						}
					}
				}
				continue
			}
		case "tribute", "return":
			if len(current.PendingSeats) == 0 {
				return fmt.Errorf("missing exchange seats")
			}
			seat = current.PendingSeats[0]
			if len(states[seat].EligibleIDs) == 0 {
				return fmt.Errorf("no eligible exchange card")
			}
			action["action"] = current.Phase
			action["card_id"] = states[seat].EligibleIDs[0]
			exchanges++
		case "finished":
			fmt.Printf("GUANDAN_LIVE_SMOKE_OK room=%s rounds=%d tribute_return_actions=%d final_counts=%v\n", roomID, rounds, exchanges, current.HandCounts)
			return nil
		default:
			return fmt.Errorf("unexpected phase %s", current.Phase)
		}
		before := current.Epoch
		if err := connections[seat].WriteJSON(action); err != nil {
			return err
		}
		for i := range connections {
			states[i], err = next(connections[i], before+1, 4)
			if err != nil {
				return err
			}
		}
		if current.Phase == "return" && states[0].Phase == "play" && states[0].HandCounts != [4]int{27, 27, 27, 27} {
			return fmt.Errorf("exchange did not balance hands")
		}
	}
	return fmt.Errorf("action limit exceeded")
}

func main() {
	base := flag.String("base", "http://127.0.0.1:8080", "local server")
	flag.Parse()
	if err := run(*base); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
