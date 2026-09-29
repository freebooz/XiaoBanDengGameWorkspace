package domain

import "time"

// ProductID（产品标识）表示独立发布的 App 产品。
type ProductID string
// GameCategory（游戏类别）表示 tile/card/board 等公共游戏家族。
type GameCategory string
// GameID（游戏标识）表示麻将、象棋等具体游戏。
type GameID string
// RuleSetID（规则集标识）表示地方玩法或规则变体。
type RuleSetID string
// RuleVersion（规则版本）必须跟随正式对局持久化，历史版本不可覆盖。
type RuleVersion string

const (
	CategoryBoard GameCategory = "board"
	CategoryTile GameCategory = "tile"
	ProductChineseChess ProductID = "xbd_chinese_chess"
	ProductMahjong ProductID = "xbd_mahjong"
	GameChineseChess GameID = "chinese_chess"
	GameMahjong GameID = "mahjong"
	RuleChineseChessStandard RuleSetID = "standard"
	RuleMahjongGuiyang RuleSetID = "guiyang"
)

// GameDescriptor（游戏描述）用于大厅、后台和客户端统一识别游戏。
type GameDescriptor struct {
	ProductID ProductID `json:"product_id"`
	Category GameCategory `json:"game_category"`
	GameID GameID `json:"game_id"`
	RuleSetID RuleSetID `json:"rule_set_id"`
	RuleVersion RuleVersion `json:"rule_version"`
	Name string `json:"name"`
	Enabled bool `json:"enabled"`
}

// GuestAccount（游客账号）是一期最小可执行登录闭环。
type GuestAccount struct {
	AccountID string `json:"account_id"`
	DisplayName string `json:"display_name"`
	CreatedAt time.Time `json:"created_at"`
}