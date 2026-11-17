package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/mahjongrooms"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchmaking"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type mahjongAdmissionStore interface {
	FindAdmissionOperation(context.Context, uuid.UUID) (mahjongrooms.AdmissionOperation, error)
	CommitAdmission(context.Context, mahjongrooms.AdmissionChange, mahjongrooms.Snapshot) (mahjongrooms.AdmissionOperation, error)
	ListAdmissionOperations(context.Context, string, time.Time) ([]mahjongrooms.AdmissionOperation, error)
}

var (
	mahjongRoomGenerationUTC       = regexp.MustCompile(`^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,9})?(Z|\+00:00)$`)
	errMahjongAdmissionUnavailable = errors.New("好友房入座管理暂时不可用")
)

func parseMahjongRoomGeneration(value string) (time.Time, bool) {
	if !mahjongRoomGenerationUTC.MatchString(value) {
		return time.Time{}, false
	}
	generation, err := time.Parse(time.RFC3339Nano, value)
	nanoseconds := generation.UnixNano()
	if err != nil || nanoseconds <= 0 || !generation.Equal(time.Unix(0, nanoseconds)) {
		return time.Time{}, false
	}
	return generation.UTC(), true
}

func validAdminMahjongRoomID(id string) bool {
	number, err := strconv.Atoi(id)
	return err == nil && len(id) == 4 && number >= 1000
}

func (s *Server) adminSetMahjongRoomAdmission(w http.ResponseWriter, r *http.Request) {
	principal, ok := s.requireAdmin(w, r, adminMahjongManageRooms)
	if !ok {
		return
	}
	roomID := r.PathValue("id")
	if !validAdminMahjongRoomID(roomID) {
		writeError(w, http.StatusNotFound, matchmaking.ErrMahjongRoomNotFound.Error())
		return
	}
	var body struct {
		RoomGeneration   string `json:"room_generation"`
		ExpectedRevision *int64 `json:"expected_revision"`
		Paused           *bool  `json:"paused"`
		Reason           string `json:"reason"`
		RequestID        string `json:"request_id"`
	}
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&body); err != nil || decoder.Decode(new(any)) != io.EOF {
		writeError(w, http.StatusBadRequest, "无效的好友房入座操作")
		return
	}
	generation, validGeneration := parseMahjongRoomGeneration(body.RoomGeneration)
	requestID, idErr := uuid.Parse(body.RequestID)
	reason := strings.TrimSpace(body.Reason)
	if !validGeneration || body.ExpectedRevision == nil || *body.ExpectedRevision < 0 || body.Paused == nil ||
		idErr != nil || len(body.RequestID) != 36 || requestID == uuid.Nil ||
		reason == "" || utf8.RuneCountInString(reason) > 160 || strings.ContainsRune(reason, 0) {
		writeError(w, http.StatusBadRequest, "无效的好友房入座操作")
		return
	}
	change := mahjongrooms.AdmissionChange{
		RequestID: requestID, RoomID: roomID, RoomGeneration: generation, ExpectedRevision: *body.ExpectedRevision,
		Paused: *body.Paused, Reason: reason, AdminName: principal.Name,
	}
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	operation, changed, err := s.mahjong.setRoomAdmission(ctx, change)
	switch {
	case err == nil:
		if changed {
			s.mahjong.publishLobby(roomID)
		}
		writeJSON(w, http.StatusOK, struct {
			Operation mahjongrooms.AdmissionOperation `json:"operation"`
		}{operation})
	case errors.Is(err, matchmaking.ErrMahjongRoomNotFound):
		writeError(w, http.StatusNotFound, err.Error())
	case errors.Is(err, matchmaking.ErrMahjongRoomAdmissionConflict), errors.Is(err, mahjongrooms.ErrConflict):
		writeError(w, http.StatusConflict, err.Error())
	default:
		writeError(w, http.StatusServiceUnavailable, errMahjongAdmissionUnavailable.Error())
	}
}

func (s *Server) adminMahjongRoomOperations(w http.ResponseWriter, r *http.Request) {
	roomID := r.PathValue("id")
	if !validAdminMahjongRoomID(roomID) {
		writeError(w, http.StatusNotFound, matchmaking.ErrMahjongRoomNotFound.Error())
		return
	}
	generation, ok := parseMahjongRoomGeneration(r.URL.Query().Get("room_generation"))
	if !ok {
		writeError(w, http.StatusBadRequest, "无效的好友房代次")
		return
	}
	store, ok := s.mahjong.friendStore.(mahjongAdmissionStore)
	if !ok {
		writeError(w, http.StatusServiceUnavailable, errMahjongAdmissionUnavailable.Error())
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	items, err := store.ListAdmissionOperations(ctx, roomID, generation)
	if err != nil {
		writeError(w, http.StatusServiceUnavailable, errMahjongAdmissionUnavailable.Error())
		return
	}
	writeJSON(w, http.StatusOK, struct {
		Items []mahjongrooms.AdmissionOperation `json:"items"`
	}{items})
}

func (h *mahjongHub) setRoomAdmission(ctx context.Context, change mahjongrooms.AdmissionChange) (mahjongrooms.AdmissionOperation, bool, error) {
	h.mu.Lock()
	defer h.mu.Unlock()
	store, ok := h.friendStore.(mahjongAdmissionStore)
	if !ok || h.stopping.Load() {
		return mahjongrooms.AdmissionOperation{}, false, errMahjongAdmissionUnavailable
	}
	operation, lookupErr := store.FindAdmissionOperation(ctx, change.RequestID)
	prior := h.friendHead(change.RoomID)
	if lookupErr == nil {
		if !operation.Matches(change) {
			return mahjongrooms.AdmissionOperation{}, false, mahjongrooms.ErrConflict
		}
		changed, err := h.replayRoomAdmissionLocked(ctx, change, prior)
		return operation, changed, err
	}
	if !errors.Is(lookupErr, pgx.ErrNoRows) {
		return mahjongrooms.AdmissionOperation{}, false, lookupErr
	}

	unconfirmed := false
	err := h.applyRoomAdmissionLocked(change, prior, func(next mahjongrooms.Snapshot) error {
		var err error
		operation, err = store.CommitAdmission(ctx, change, next)
		if err == nil || errors.Is(err, mahjongrooms.ErrConflict) {
			return err
		}
		readCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 2*time.Second)
		defer cancel()
		saved, readErr := store.FindAdmissionOperation(readCtx, change.RequestID)
		if readErr == nil {
			if !saved.Matches(change) {
				return mahjongrooms.ErrConflict
			}
			operation = saved
			return nil
		}
		unconfirmed = true
		return err
	})
	if err != nil {
		if unconfirmed {
			h.confirmRoomAdmissionLater(store, change, prior, 0)
		}
		return mahjongrooms.AdmissionOperation{}, false, err
	}
	return operation, true, nil
}

func precedesRoomAdmission(prior *mahjongFriendHead, change mahjongrooms.AdmissionChange) bool {
	return prior != nil && prior.row.CreatedAt.Equal(change.RoomGeneration) &&
		prior.image.Assignment.Settings.AdmissionRevision == change.ExpectedRevision
}

func (h *mahjongHub) applyRoomAdmissionLocked(change mahjongrooms.AdmissionChange, prior *mahjongFriendHead, commit func(mahjongrooms.Snapshot) error) error {
	return h.matches.CommitMahjongFriendAdmission(change.RoomID, change.RoomGeneration, change.ExpectedRevision, change.Paused, func(assignment matchmaking.MahjongAssignment) error {
		if !precedesRoomAdmission(prior, change) {
			return errMahjongAdmissionUnavailable
		}
		image := prior.image
		image.Assignment = assignment
		next, err := newMahjongFriendHead(image, prior)
		if err != nil {
			return err
		}
		if err := commit(next.row); err != nil {
			return err
		}
		h.friendHeads.Store(change.RoomID, next)
		return nil
	})
}

func (h *mahjongHub) replayRoomAdmissionLocked(ctx context.Context, change mahjongrooms.AdmissionChange, prior *mahjongFriendHead) (bool, error) {
	if !precedesRoomAdmission(prior, change) {
		return false, nil
	}
	// The live room may still be at the predecessor revision after a lost
	// database reply. Confirm the durable successor before publishing.
	err := h.applyRoomAdmissionLocked(change, prior, func(next mahjongrooms.Snapshot) error {
		row, err := h.friendStore.Load(ctx, change.RoomID)
		if err != nil || !row.CreatedAt.Equal(next.CreatedAt) || row.Revision != next.Revision || !equalMahjongFriendPayload(row.Payload, next.Payload) {
			return errMahjongAdmissionUnavailable
		}
		return nil
	})
	if err != nil {
		return false, errMahjongAdmissionUnavailable
	}
	return true, nil
}

// An ambiguous database reply can outlive the request. A bounded readback
// retries confirmation of that write while the live head is still its
// predecessor. It never submits a second change.
func (h *mahjongHub) confirmRoomAdmissionLater(store mahjongAdmissionStore, change mahjongrooms.AdmissionChange, prior *mahjongFriendHead, attempt int) {
	time.AfterFunc(time.Second<<attempt, func() {
		h.mu.Lock()
		if h.stopping.Load() || h.friendHead(change.RoomID) != prior {
			h.mu.Unlock()
			return
		}
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		operation, err := store.FindAdmissionOperation(ctx, change.RequestID)
		changed := false
		if err == nil && operation.Matches(change) {
			changed, err = h.replayRoomAdmissionLocked(ctx, change, prior)
		}
		cancel()
		h.mu.Unlock()
		if changed {
			h.publishLobby(change.RoomID)
		}
		if err != nil && attempt < 4 {
			h.confirmRoomAdmissionLater(store, change, prior, attempt+1)
		}
	})
}
