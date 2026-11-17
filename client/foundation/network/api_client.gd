extends RefCounted
class_name XbdApiClient
## XbdApiClient（小板凳API客户端）
## 只连接“小板凳”业务服务端，不允许直接访问外部AI或支付平台密钥接口。

var base_url: String = "http://127.0.0.1:8080"
const SERVER_FILE := "user://xbd_server_url.txt"
const SESSION_ALPHABET := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"

var _session_token := ""


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
	if cleaned != base_url:
		clear_session()
	base_url = cleaned
	if persist:
		var file := FileAccess.open(SERVER_FILE, FileAccess.WRITE)
		if file != null:
			file.store_string(base_url)
	return true


static func valid_session_token(token: Variant) -> bool:
	if not token is String or token.length() != 43:
		return false
	for character in token:
		if character not in SESSION_ALPHABET:
			return false
	return true


func accept_guest_login(response: Variant) -> Dictionary:
	if not response is Dictionary or not response.get("account_id") is String or response.account_id.is_empty():
		return {}
	if not valid_session_token(response.get("session_token")):
		return {}
	_session_token = response.session_token
	var guest: Dictionary = response.duplicate()
	guest.erase("session_token")
	return guest


func clear_session() -> void:
	_session_token = ""


func authorization_headers() -> PackedStringArray:
	if _session_token.is_empty():
		return PackedStringArray()
	return PackedStringArray(["Authorization: Bearer " + _session_token])


static func socket_session_expired(socket: WebSocketPeer) -> bool:
	return socket.get_close_code() == 1008 and socket.get_close_reason() == "session_expired"


func check_session(owner: Node, expired: Callable) -> HTTPRequest:
	if _session_token.is_empty(): return null
	var request := HTTPRequest.new()
	request.timeout = 6.0
	request.max_redirects = 0
	owner.add_child(request)
	request.request_completed.connect(_on_session_checked.bind(request, base_url, _session_token, expired), CONNECT_ONE_SHOT)
	if request.request(base_url + "/api/v1/auth/session", authorization_headers()) != OK:
		request.queue_free()
		return null
	return request


func _on_session_checked(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, request: HTTPRequest, origin: String, token: String, expired: Callable) -> void:
	request.queue_free()
	if result == HTTPRequest.RESULT_SUCCESS and code == 401 and base_url == origin and _session_token == token and expired.is_valid():
		expired.call()


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
