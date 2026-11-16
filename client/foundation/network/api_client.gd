extends RefCounted
class_name XbdApiClient
## XbdApiClient（小板凳API客户端）
## 只连接“小板凳”业务服务端，不允许直接访问外部AI或支付平台密钥接口。

var base_url: String = "http://127.0.0.1:8080"
const SERVER_FILE := "user://xbd_server_url.txt"


func _init(url: String = "") -> void:
	var chosen := url.strip_edges()
	if chosen == "":
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--server-url="):
				chosen = arg.trim_prefix("--server-url=")
				break
	if chosen == "":
		chosen = OS.get_environment("XBD_SERVER_URL").strip_edges()
	if chosen == "" and FileAccess.file_exists(SERVER_FILE):
		chosen = FileAccess.get_file_as_string(SERVER_FILE).strip_edges()
	if chosen == "":
		chosen = str(ProjectSettings.get_setting("xiaobandeng/network/default_server_url", "")).strip_edges()
	if chosen != "":
		set_base_url(chosen, false)


func set_base_url(url: String, persist: bool = true) -> bool:
	var cleaned := url.strip_edges().trim_suffix("/")
	if not (cleaned.begins_with("http://") or cleaned.begins_with("https://")):
		return false
	base_url = cleaned
	if persist:
		var file := FileAccess.open(SERVER_FILE, FileAccess.WRITE)
		if file != null:
			file.store_string(base_url)
	return true


func health_url() -> String:
	return base_url + "/health"


func catalog_url() -> String:
	return base_url + "/api/v1/catalog"


func guest_login_url() -> String:
	return base_url + "/api/v1/auth/guest"


func quick_match_url() -> String:
	return base_url + "/api/v1/matchmaking/quick"


func room_ready_url() -> String:
	return base_url + "/api/v1/matchmaking/ready"


func cancel_match_url() -> String:
	return base_url + "/api/v1/matchmaking/cancel"


func websocket_url() -> String:
	if base_url.begins_with("https://"):
		return "wss://" + base_url.trim_prefix("https://") + "/ws"
	return "ws://" + base_url.trim_prefix("http://") + "/ws"
