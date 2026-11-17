package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/wallet"
)

func (s *Server) wallet(w http.ResponseWriter, r *http.Request) {
	if !requireGET(w, r) {
		return
	}
	session, ok := s.requireSession(w, r)
	if !ok {
		return
	}
	if requested := r.URL.Query().Get("account_id"); requested != "" && requested != session.AccountID {
		writeError(w, http.StatusForbidden, "只能查看自己的鸡蛋余额")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	balance, err := s.wallets.GetFamilyBalance(ctx, session.AccountID)
	if err != nil {
		writeError(w, http.StatusServiceUnavailable, "钱包暂时不可用，请稍后重试")
		return
	}
	writeJSON(w, http.StatusOK, balance)
}

func (s *Server) lookupAdminEggPlayer(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r, adminGrantEggs); !ok {
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	player, err := s.wallets.LookupEggPlayer(ctx, r.URL.Query().Get("display_name"))
	if err != nil {
		writeAdminEggError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, player)
}

func (s *Server) grantAdminEggs(w http.ResponseWriter, r *http.Request) {
	principal, ok := s.requireAdmin(w, r, adminGrantEggs)
	if !ok {
		return
	}
	var request wallet.EggGrant
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096))
	decoder.DisallowUnknownFields()
	if decoder.Decode(&request) != nil || decoder.Decode(new(any)) != io.EOF {
		writeError(w, http.StatusBadRequest, "请填写有效的玩家昵称、加蛋数量和请求编号")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 4*time.Second)
	defer cancel()
	receipt, err := s.wallets.GrantEggs(ctx, principal.Name, request)
	if err != nil {
		writeAdminEggError(w, err)
		return
	}
	s.mahjong.publishWalletChange(receipt.AccountID)
	go s.mahjong.refreshWalletForPlayer(receipt.AccountID)
	writeJSON(w, http.StatusOK, receipt)
}

func writeAdminEggError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, wallet.ErrInvalidEggGrant), errors.Is(err, wallet.ErrInvalidEggPlayer):
		writeError(w, http.StatusBadRequest, err.Error())
	case errors.Is(err, wallet.ErrPlayerNotFound):
		writeError(w, http.StatusNotFound, err.Error())
	case errors.Is(err, wallet.ErrAmbiguousPlayer), errors.Is(err, wallet.ErrEggGrantConflict), errors.Is(err, wallet.ErrEggGrantTargetChanged):
		writeError(w, http.StatusConflict, err.Error())
	default:
		writeError(w, http.StatusServiceUnavailable, "钱包暂时不可用，请稍后重试")
	}
}
