package ai

// Capability（AI能力）描述前端可显示但由后台FeatureFlag控制的智能能力。
type Capability struct {
	Key string `json:"key"`
	Name string `json:"name"`
	Description string `json:"description"`
	Enabled bool `json:"enabled"`
}

// Provider（AI提供者接口）隔离规则AI、搜索AI、强化学习模型和LLM。
type Provider interface {
	ID() string
	Suggest(context GameContext) (Suggestion,error)
}

// GameContext（AI游戏上下文）只保存当前玩家合法可见的信息。
type GameContext struct {
	GameID string `json:"game_id"`
	RuleSetID string `json:"rule_set_id"`
	RuleVersion string `json:"rule_version"`
	PublicState map[string]any `json:"public_state"`
	PrivateState map[string]any `json:"private_state"`
	LegalActions []map[string]any `json:"legal_actions"`
}

// Suggestion（AI结构化建议）由Godot具体游戏适配器决定如何展示。
type Suggestion struct {
	Action map[string]any `json:"action"`
	Confidence float64 `json:"confidence"`
	ReasonCode string `json:"reason_code"`
	Explanation string `json:"explanation"`
}

// Service（AI服务）一期只暴露能力清单和标准接口。
type Service struct{}

// NewService（创建AI服务）。
func NewService() *Service { return &Service{} }

// Capabilities（能力清单）默认关闭真实AI功能，由后台灰度开启。
func (s *Service) Capabilities() []Capability {
	return []Capability{
		{Key:"ai.bot.enabled",Name:"人机陪练",Description:"AI对手与难度配置",Enabled:false},
		{Key:"ai.tutorial.enabled",Name:"新手教学",Description:"结构化教学步骤",Enabled:false},
		{Key:"ai.hint.enabled",Name:"智能提示",Description:"返回合法动作中的推荐项",Enabled:false},
		{Key:"ai.coach.enabled",Name:"AI教练",Description:"解释推荐动作",Enabled:false},
		{Key:"ai.puzzle.enabled",Name:"残局训练",Description:"从标准快照加载训练局面",Enabled:false},
		{Key:"ai.replay_analysis.enabled",Name:"AI复盘",Description:"在事件时间轴上生成分析标记",Enabled:false},
	}
}