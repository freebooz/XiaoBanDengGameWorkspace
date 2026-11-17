package httpapi

import (
	"bytes"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"os"
	"regexp"
	"slices"
	"strings"
)

const (
	adminPlatformRead       = "platform:read"
	adminMahjongReview      = "mahjong:review"
	adminMahjongManageRooms = "mahjong:manage_rooms"
	adminGrantEggs          = "wallet:grant_eggs"
)

type adminPrincipal struct {
	Name         string   `json:"admin_name"`
	Capabilities []string `json:"capabilities"`
	digest       [sha256.Size]byte
}

var adminNamePattern = regexp.MustCompile(`^[A-Za-z0-9._@-]{1,128}$`)

func loadAdminCredentials(path string) ([]adminPrincipal, error) {
	if path == "" {
		return nil, nil
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, errors.New("无法读取管理员凭据配置")
	}
	defer file.Close()
	const maxSize = 64 << 10
	data, err := io.ReadAll(io.LimitReader(file, maxSize+1))
	if err != nil || len(data) > maxSize {
		return nil, errors.New("管理员凭据配置无法读取或超出大小限制")
	}
	var entries []struct {
		Name         string   `json:"name"`
		TokenHash    string   `json:"token_sha256"`
		Capabilities []string `json:"capabilities"`
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&entries); err != nil || len(entries) == 0 || decoder.Decode(new(any)) != io.EOF {
		return nil, errors.New("管理员凭据配置格式无效")
	}
	principals := make([]adminPrincipal, 0, len(entries))
	names := make(map[string]bool, len(entries))
	digests := make(map[[sha256.Size]byte]bool, len(entries))
	for _, entry := range entries {
		var digest [sha256.Size]byte
		n, err := hex.Decode(digest[:], []byte(entry.TokenHash))
		if !adminNamePattern.MatchString(entry.Name) || names[entry.Name] || len(entry.TokenHash) != hex.EncodedLen(sha256.Size) || err != nil || n != sha256.Size || digests[digest] {
			return nil, errors.New("管理员凭据配置包含无效或重复的标识")
		}
		caps := []string{}
		for _, cap := range entry.Capabilities {
			if (cap != adminPlatformRead && cap != adminMahjongReview && cap != adminMahjongManageRooms && cap != adminGrantEggs) || slices.Contains(caps, cap) {
				return nil, errors.New("管理员凭据配置包含无效或重复的权限")
			}
			caps = append(caps, cap)
		}
		if len(caps) == 0 {
			return nil, errors.New("管理员凭据至少需要一项权限")
		}
		names[entry.Name], digests[digest] = true, true
		principals = append(principals, adminPrincipal{Name: entry.Name, Capabilities: caps, digest: digest})
	}
	return principals, nil
}

func (s *Server) requireAdmin(w http.ResponseWriter, r *http.Request, capability string) (adminPrincipal, bool) {
	w.Header().Set("Cache-Control", "no-store")
	values := r.Header.Values("Authorization")
	if len(values) != 1 {
		return unauthorizedAdmin(w)
	}
	fields := strings.Fields(values[0])
	if len(fields) != 2 || !strings.EqualFold(fields[0], "Bearer") || len(fields[1]) != base64.RawURLEncoding.EncodedLen(32) {
		return unauthorizedAdmin(w)
	}
	if _, err := base64.RawURLEncoding.Strict().DecodeString(fields[1]); err != nil {
		return unauthorizedAdmin(w)
	}
	digest := sha256.Sum256([]byte(fields[1]))
	var principal adminPrincipal
	for _, credential := range s.adminPrincipals {
		if subtle.ConstantTimeCompare(digest[:], credential.digest[:]) == 1 {
			principal = credential
		}
	}
	if principal.Name == "" {
		return unauthorizedAdmin(w)
	}
	if capability != "" && !slices.Contains(principal.Capabilities, capability) {
		writeError(w, http.StatusForbidden, "当前管理员没有此操作权限")
		return adminPrincipal{}, false
	}
	return principal, true
}

func unauthorizedAdmin(w http.ResponseWriter) (adminPrincipal, bool) {
	w.Header().Set("WWW-Authenticate", `Bearer realm="小板凳运营"`)
	writeError(w, http.StatusUnauthorized, "请提供有效的管理员凭据")
	return adminPrincipal{}, false
}

func (s *Server) adminSession(w http.ResponseWriter, r *http.Request) {
	if !requireGET(w, r) {
		return
	}
	if principal, ok := s.requireAdmin(w, r, ""); ok {
		writeJSON(w, http.StatusOK, principal)
	}
}

func (s *Server) adminRead(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if _, ok := s.requireAdmin(w, r, adminPlatformRead); ok {
			next(w, r)
		}
	}
}
