extends RefCounted


static func share_text(value: String) -> String:
	var summary := value.strip_edges().replace("\r\n", "\n")
	if summary.is_empty():
		return "本局暂无可分享的战绩"
	if OS.has_feature("android") and _open_android_share_sheet(summary):
		return "已打开系统分享面板"
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		return "当前设备无法分享或复制战绩"
	DisplayServer.clipboard_set(summary)
	if DisplayServer.clipboard_get().replace("\r\n", "\n") == summary:
		return "战绩已复制，可粘贴分享"
	return "复制战绩失败，请重试"


static func _open_android_share_sheet(summary: String) -> bool:
	if not Engine.has_singleton("AndroidRuntime") or not Engine.has_singleton("JavaClassWrapper"):
		return false
	var runtime = Engine.get_singleton("AndroidRuntime")
	var java = Engine.get_singleton("JavaClassWrapper")
	var activity = runtime.getActivity()
	var intent_class = java.wrap("android.content.Intent")
	if activity == null or intent_class == null:
		return false
	var send = intent_class.Intent(intent_class.ACTION_SEND)
	if send == null or send.setType("text/plain") == null:
		return false
	if send.putExtra(intent_class.EXTRA_TEXT, summary) == null:
		return false
	var chooser = intent_class.createChooser(send, "分享战绩")
	if chooser == null:
		return false
	activity.startActivity(chooser)
	return java.get_exception() == null
