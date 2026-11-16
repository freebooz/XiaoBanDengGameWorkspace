package game

import (
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/domain"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
)

// Catalog（游戏目录）保存一期稳定的产品/游戏/规则集描述。
func Catalog() []domain.GameDescriptor {
	catalog := []domain.GameDescriptor{
		{ProductID: domain.ProductChineseChess, Category: domain.CategoryBoard, GameID: domain.GameChineseChess, RuleSetID: domain.RuleChineseChessStandard, RuleVersion: "1.0.0", Name: "小板凳象棋", Enabled: true},
	}
	for _, rule := range guiyang.RuleDescriptors() {
		catalog = append(catalog, domain.GameDescriptor{ProductID: domain.ProductMahjong, Category: domain.CategoryTile, GameID: domain.GameMahjong, RuleSetID: domain.RuleSetID(rule.ID), RuleVersion: domain.RuleVersion(rule.Version), Name: "小板凳麻将·" + rule.Name, Enabled: true})
	}
	return append(catalog,
		domain.GameDescriptor{ProductID: domain.ProductLandlord, Category: domain.CategoryCard, GameID: domain.GameLandlord, RuleSetID: domain.RuleLandlordClassic, RuleVersion: "1.0.0", Name: "小板凳斗地主", Enabled: true},
		domain.GameDescriptor{ProductID: domain.ProductGuandan, Category: domain.CategoryCard, GameID: domain.GameGuandan, RuleSetID: domain.RuleGuandanClassic, RuleVersion: "1.0.0", Name: "小板凳掼蛋", Enabled: true},
	)
}
