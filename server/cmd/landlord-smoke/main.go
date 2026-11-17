// Landlord live smoke: three real guest accounts, one room, a complete game.
// Run against an already-running local server with: go run ./cmd/landlord-smoke -base http://127.0.0.1:8080
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

	"github.com/gorilla/websocket"
)

type card struct {
	ID   int `json:"id"`
	Rank int `json:"rank"`
}
type play struct {
	Seat    int `json:"seat"`
	Pattern struct {
		Kind string `json:"kind"`
		Main int    `json:"main"`
	} `json:"pattern"`
}
type state struct {
	Type             string `json:"type"`
	Phase            string `json:"phase"`
	Status           string `json:"status"`
	Turn             int    `json:"turn"`
	YourSeat         int    `json:"your_seat"`
	Hand             []card `json:"hand"`
	HandCounts       [3]int `json:"hand_counts"`
	LastPlay         play   `json:"last_play"`
	HasLastPlay      bool   `json:"has_last_play"`
	Winner           int    `json:"winner"`
	Epoch            int    `json:"epoch"`
	ConnectedPlayers int    `json:"connected_players"`
}

func post(base, path string, payload any, token string) (map[string]any, error) {
	body, _ := json.Marshal(payload)
	request, err := http.NewRequest(http.MethodPost, base+path, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	request.Header.Set("Content-Type", "application/json")
	if token != "" {
		request.Header.Set("Authorization", "Bearer "+token)
	}
	client := http.Client{Timeout: 10 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error {
		return http.ErrUseLastResponse
	}}
	response, err := client.Do(request)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	data, err := io.ReadAll(response.Body)
	if err != nil {
		return nil, err
	}
	var parsed map[string]any
	if err := json.Unmarshal(data, &parsed); err != nil {
		return nil, err
	}
	if response.StatusCode >= 300 {
		return nil, fmt.Errorf("%s: %s", path, data)
	}
	return parsed, nil
}

func nextState(conn *websocket.Conn, minimumEpoch int, minimumConnected int) (state, error) {
	_ = conn.SetReadDeadline(time.Now().Add(10 * time.Second))
	for {
		var snapshot state
		if err := conn.ReadJSON(&snapshot); err != nil {
			return state{}, err
		}
		if snapshot.Type == "landlord_error" {
			return state{}, fmt.Errorf("landlord action rejected")
		}
		if snapshot.Type == "landlord_state" && snapshot.Epoch >= minimumEpoch && snapshot.ConnectedPlayers >= minimumConnected {
			return snapshot, nil
		}
	}
}

func run(base string) error {
	accounts := [3]string{}
	tokens := [3]string{}
	for i := range accounts {
		result, err := post(base, "/api/v1/auth/guest", map[string]any{}, "")
		if err != nil {
			return err
		}
		accounts[i], _ = result["account_id"].(string)
		tokens[i], _ = result["session_token"].(string)
		if accounts[i] == "" || tokens[i] == "" {
			return fmt.Errorf("guest login did not return an authenticated account")
		}
	}
	roomID := ""
	for seat, account := range accounts {
		result, err := post(base, "/api/v1/matchmaking/quick", map[string]any{"account_id": account, "product_id": "xbd_landlord", "game_id": "landlord", "rule_set_id": "classic_three_player", "rule_version": "2.0.0"}, tokens[seat])
		if err != nil {
			return err
		}
		if roomID == "" {
			roomID = result["room_id"].(string)
		} else if result["room_id"] != roomID {
			return fmt.Errorf("players entered different rooms")
		}
	}
	for seat, account := range accounts {
		if _, err := post(base, "/api/v1/matchmaking/ready", map[string]any{"account_id": account, "room_id": roomID}, tokens[seat]); err != nil {
			return err
		}
	}
	parsedURL, err := url.Parse(base)
	if err != nil {
		return err
	}
	if parsedURL.Scheme == "https" {
		parsedURL.Scheme = "wss"
	} else {
		parsedURL.Scheme = "ws"
	}
	parsedURL.Path = "/ws"
	var connections [3]*websocket.Conn
	var snapshots [3]state
	defer func() {
		for _, conn := range connections {
			if conn != nil {
				_ = conn.Close()
			}
		}
	}()
	for seat := 0; seat < 3; seat++ {
		conn, _, err := websocket.DefaultDialer.Dial(parsedURL.String(), http.Header{"Authorization": {"Bearer " + tokens[seat]}})
		if err != nil {
			return err
		}
		connections[seat] = conn
		if err := conn.WriteJSON(map[string]any{"type": "landlord_join", "room_id": roomID, "client_id": accounts[seat]}); err != nil {
			return err
		}
		initial, err := nextState(conn, 1, seat+1)
		if err != nil {
			return err
		}
		if seat == 2 {
			snapshots[seat] = initial
		}
	}
	for seat := 0; seat < 2; seat++ {
		snapshots[seat], err = nextState(connections[seat], 1, 3)
		if err != nil {
			return err
		}
	}
	for seat := 0; seat < 3; seat++ {
		if len(snapshots[seat].Hand) != 17 {
			return fmt.Errorf("seat %d hand count %d", seat, len(snapshots[seat].Hand))
		}
	}
	if err := connections[0].WriteJSON(map[string]any{"type": "landlord_action", "action": "bid", "amount": 3}); err != nil {
		return err
	}
	for seat := 0; seat < 3; seat++ {
		snapshots[seat], err = nextState(connections[seat], 2, 3)
		if err != nil {
			return err
		}
	}
	if snapshots[0].Phase != "double" || len(snapshots[0].Hand) != 20 {
		return fmt.Errorf("landlord did not receive bottom cards")
	}
	for snapshots[0].Phase == "double" {
		current := snapshots[0]
		if err := connections[current.Turn].WriteJSON(map[string]any{"type": "landlord_action", "action": "double", "enabled": false}); err != nil {
			return err
		}
		for seat := 0; seat < 3; seat++ {
			snapshots[seat], err = nextState(connections[seat], current.Epoch+1, 3)
			if err != nil {
				return err
			}
		}
	}
	if snapshots[0].Phase != "play" {
		return fmt.Errorf("double decisions did not enter play")
	}
	for actionCount := 0; actionCount < 250; actionCount++ {
		current := snapshots[0]
		if current.Phase == "finished" {
			fmt.Printf("LANDLORD_LIVE_SMOKE_OK room=%s actions=%d winner=%d counts=%v\n", roomID, actionCount, current.Winner, current.HandCounts)
			return nil
		}
		seat := current.Turn
		if seat < 0 || seat > 2 {
			return fmt.Errorf("invalid turn %d", seat)
		}
		hand := snapshots[seat].Hand
		if len(hand) == 0 {
			return fmt.Errorf("empty active hand")
		}
		action := map[string]any{"type": "landlord_action", "action": "pass"}
		if !current.HasLastPlay || current.LastPlay.Seat == seat {
			action = map[string]any{"type": "landlord_action", "action": "play", "card_ids": []int{hand[0].ID}}
		} else if current.LastPlay.Pattern.Kind == "single" {
			for _, candidate := range hand {
				if candidate.Rank > current.LastPlay.Pattern.Main {
					action = map[string]any{"type": "landlord_action", "action": "play", "card_ids": []int{candidate.ID}}
					break
				}
			}
		}
		if err := connections[seat].WriteJSON(action); err != nil {
			return err
		}
		nextEpoch := current.Epoch + 1
		for i := 0; i < 3; i++ {
			snapshots[i], err = nextState(connections[i], nextEpoch, 3)
			if err != nil {
				return err
			}
		}
	}
	return fmt.Errorf("game did not finish within action limit")
}

func main() {
	base := flag.String("base", "http://127.0.0.1:8080", "running XiaoBanDeng server URL")
	flag.Parse()
	if err := run(*base); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
