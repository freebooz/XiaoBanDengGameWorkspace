package httpapi

import (
	"encoding/json"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// Opt-in native Godot integration harness. All users/rooms are isolated,
// in-memory test fixtures; no production account or database is involved.
func TestMahjongNativeVoiceRelay(t *testing.T) {
	directory := os.Getenv("XBD_NATIVE_VOICE_PROBE_DIR")
	if directory == "" {
		t.Skip("set XBD_NATIVE_VOICE_PROBE_DIR for the native AudioServer probe")
	}
	f := referenceMahjongServer(t, 1, 0)
	stop := make(chan struct{})
	defer close(stop)
	go func() {
		for {
			select {
			case <-f.captured:
			case <-stop:
				return
			}
		}
	}()
	target, err := url.Parse(strings.Replace(f.url, "ws://", "http://", 1))
	if err != nil {
		t.Fatal(err)
	}
	listener, err := net.Listen("tcp", ":18764")
	if err != nil {
		t.Fatal(err)
	}
	server := &http.Server{Handler: httputil.NewSingleHostReverseProxy(target)}
	defer server.Close()
	go server.Serve(listener)
	ready, _ := json.Marshal(map[string]any{"room_id": f.rooms[0], "url": "ws://127.0.0.1:18764/api/v1/mahjong/ws"})
	if err := os.WriteFile(filepath.Join(directory, "native-ready.json"), ready, 0600); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(300 * time.Second)
	for time.Now().Before(deadline) {
		if data, err := os.ReadFile(filepath.Join(directory, "native-done.json")); err == nil {
			var result struct {
				Success bool `json:"success"`
			}
			if json.Unmarshal(data, &result) != nil || !result.Success {
				t.Fatal("Godot native voice/mixer verification failed")
			}
			t.Log("four native Godot transports received isolated authoritative voice and produced nonzero mixer output")
			return
		}
		time.Sleep(25 * time.Millisecond)
	}
	t.Fatal("native voice probe did not finish")
}
