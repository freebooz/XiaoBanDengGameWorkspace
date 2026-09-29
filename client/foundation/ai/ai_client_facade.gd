extends RefCounted
class_name XbdAiClientFacade
## XbdAiClientFacade（AI客户端统一门面）
## 负责UI与小板凳服务端AI Gateway之间的协议边界，客户端禁止直连外部模型。

enum ExperienceState {
	DISABLED,
	IDLE,
	REQUESTING,
	THINKING,
	SUGGESTION_READY,
	EXPLAINING,
	TRAINING,
	ERROR,
	COOLDOWN,
}

var state: ExperienceState = ExperienceState.DISABLED


func describe_phase1() -> String:
	return "AI一期预留：人机陪练 / 新手教学 / 智能提示 / AI教练 / 残局训练 / AI复盘。当前Feature Flag默认关闭。"


func can_use_ai(session_mode: String) -> bool:
	# 排位等正式竞技模式默认不允许AI提示，防止变相外挂。
	return session_mode in ["vs_ai", "tutorial", "training", "puzzle", "replay_analysis"]