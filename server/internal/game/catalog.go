package game

import "github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/domain"

// Catalog（游戏目录）保存一期稳定的产品/游戏/规则集描述。
func Catalog() []domain.GameDescriptor {
	return []domain.GameDescriptor{
		{ProductID: domain.ProductChineseChess, Category: domain.CategoryBoard, GameID: domain.GameChineseChess, RuleSetID: domain.RuleChineseChessStandard, RuleVersion: "1.0.0", Name: "小板凳象棋", Enabled: true},
		{ProductID: domain.ProductMahjong, Category: domain.CategoryTile, GameID: domain.GameMahjong, RuleSetID: domain.RuleMahjongGuiyang, RuleVersion: "1.0.0", Name: "小板凳麻将·贵阳麻将", Enabled: true},
	}
}