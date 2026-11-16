package httpapi

import (
	"encoding/base64"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/config"
	"github.com/gorilla/websocket"
)

func TestWebsocketVoiceUsesProductionTransport(t *testing.T) {
	server := httptest.NewServer(New(config.Config{}, nil, nil))
	defer server.Close()
	conn := dialTestWebSocket(t, "ws"+strings.TrimPrefix(server.URL, "http")+"/ws")
	defer conn.Close()
	readUntilType(t, conn, "connected", nil)
	mustWriteJSON(t, conn, map[string]any{"type": "landlord_training_start"})
	readUntilType(t, conn, "landlord_state", nil)
	// Maximum supported 16kHz voice remains below the shared frame budget.
	encoded := base64.StdEncoding.EncodeToString(make([]byte, 16000*5*2))
	mustWriteJSON(t, conn, map[string]any{"type": "landlord_social", "action": "voice", "message_id": "transport-max-clip", "sample_rate": 16000, "duration_ms": 5000, "pcm_base64": encoded})
	event := readUntilType(t, conn, "landlord_social", nil)
	if event["pcm_base64"] != encoded || event["seat"] != float64(0) {
		t.Fatal("production route did not preserve bounded voice or assign sender seat")
	}
}

func TestWebsocketRejectsOversizedFrameBeforeJSON(t *testing.T) {
	server := httptest.NewServer(New(config.Config{}, nil, nil))
	defer server.Close()
	conn := dialTestWebSocket(t, "ws"+strings.TrimPrefix(server.URL, "http")+"/ws")
	defer conn.Close()
	readUntilType(t, conn, "connected", nil)
	// The server can close while the write is still in progress. Read its close
	// frame below; use valid JSON so removing the size limit would produce ACK.
	_ = conn.WriteMessage(websocket.TextMessage, []byte(`{"type":"oversized-probe","blob":"`+strings.Repeat("x", (256<<10)+1)+`"}`))
	_ = conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	_, _, err := conn.ReadMessage()
	if !websocket.IsCloseError(err, websocket.CloseMessageTooBig) {
		t.Fatalf("oversized transport must close with message-too-big: %v", err)
	}
}
