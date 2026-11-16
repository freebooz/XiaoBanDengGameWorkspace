extends Node
## Polls only WebSocket I/O. Views receive connection and packet events.

signal opened
signal connection_lost(reason: String)
signal packet_received(raw: String)
signal session_expired
signal seat_replaced

const GUEST_SESSIONS := preload("res://modules/games/mahjong/guiyang/mahjong_guest_sessions.gd")
const HEARTBEAT_SECONDS := 3.0

var _peer := WebSocketPeer.new()
var _retry: Timer
var _connect_deadline: Timer
var _url := ""
var _session_token := ""
var _wanted := false
var _open_reported := false
var _generation := 0

func _ready() -> void:
	set_process(false)
	_retry = Timer.new()
	_retry.one_shot = true
	_retry.timeout.connect(_dial)
	add_child(_retry)
	_connect_deadline = Timer.new()
	_connect_deadline.one_shot = true
	_connect_deadline.timeout.connect(func(): _lose("连接超时"))
	add_child(_connect_deadline)

static func endpoint(server: String) -> String:
	if server.begins_with("https://"):
		return "wss://" + server.trim_prefix("https://") + "/api/v1/mahjong/ws"
	if server.begins_with("http://"):
		return "ws://" + server.trim_prefix("http://") + "/api/v1/mahjong/ws"
	return ""

func start(url: String, session_token: String) -> void:
	stop()
	if not GUEST_SESSIONS.valid_token(session_token) or not url.ends_with("/api/v1/mahjong/ws"):
		connection_lost.emit("缺少有效的游客会话，请重新登录")
		return
	_url = url
	_session_token = session_token
	_wanted = true
	_dial()

func stop() -> void:
	_wanted = false
	_generation += 1
	_open_reported = false
	_session_token = ""
	set_process(false)
	if is_instance_valid(_retry): _retry.stop()
	if is_instance_valid(_connect_deadline): _connect_deadline.stop()
	_peer.close()
	_peer = WebSocketPeer.new()

func is_open() -> bool:
	return _wanted and _peer.get_ready_state() == WebSocketPeer.STATE_OPEN

func send(packet: Dictionary) -> Error:
	if not is_open(): return ERR_CONNECTION_ERROR
	return _peer.send_text(JSON.stringify(packet))

func _dial() -> void:
	if not _wanted: return
	_generation += 1
	_open_reported = false
	_peer = WebSocketPeer.new()
	_peer.inbound_buffer_size = 262144
	_peer.outbound_buffer_size = 262144
	_peer.heartbeat_interval = HEARTBEAT_SECONDS
	_peer.handshake_headers = PackedStringArray(["Authorization: Bearer " + _session_token])
	var error := _peer.connect_to_url(_url)
	if error != OK:
		_lose("连接失败（%d）" % error)
		return
	_connect_deadline.start(7.0)
	set_process(true)

func _lose(reason: String) -> void:
	if not _wanted: return
	_generation += 1
	_open_reported = false
	set_process(false)
	_connect_deadline.stop()
	_peer.close()
	_peer = WebSocketPeer.new()
	_retry.start(2.0)
	connection_lost.emit(reason)

func _process(_delta: float) -> void:
	var generation := _generation
	_peer.poll()
	match _peer.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _open_reported:
				_open_reported = true
				_connect_deadline.stop()
				opened.emit()
			while generation == _generation and _peer.get_available_packet_count() > 0:
				packet_received.emit(_peer.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			if generation != _generation: return
			if _peer.get_close_code() == 1008:
				match _peer.get_close_reason():
					"session_expired":
						stop()
						session_expired.emit()
						return
					"seat_replaced":
						stop()
						seat_replaced.emit()
						return
			_lose("连接已断开")

func _exit_tree() -> void:
	stop()
