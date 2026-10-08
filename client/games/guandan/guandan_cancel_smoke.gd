extends SceneTree

class CancelProbe extends "res://scripts/main.gd":
	var posted := false
	var exited_started_room := false
	func _ready() -> void:
		_screen = Control.new()
		add_child(_screen)
		_http = HTTPRequest.new()
		add_child(_http)
		_timer = Timer.new()
		add_child(_timer)
		_status = Label.new()
		_screen.add_child(_status)
		_api = API_SCRIPT.new()
		_state = "matching"
	func _post(_url: String, _payload: Dictionary) -> void:
		posted = true
	func _enter_game(exit_after_join: bool = false) -> void:
		exited_started_room = exit_after_join or _cancel_requested

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var app := CancelProbe.new()
	root.add_child(app)
	app._request_kind = "match"
	if app._http.request(app._api.health_url()) != OK:
		quit(1)
		return
	app._cancel()
	if app._request_kind != "match" or not app._cancel_pending or app.posted:
		push_error("Cancel overwrote the in-flight match response")
		quit(2)
		return
	app._http.cancel_request()
	app._on_response(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),'{"start":false}'.to_utf8_buffer())
	await process_frame
	if not app.posted or app._request_kind != "cancel" or not app._cancel_requested:
		quit(3)
		return
	app._on_response(HTTPRequest.RESULT_SUCCESS,400,PackedStringArray(),'{"error":"对局已经开始，不能退出匹配房间"}'.to_utf8_buffer())
	if not app.exited_started_room:
		push_error("Cancel intent was lost when readiness raced cancellation")
		quit(4)
		return
	app._show_lobby()
	if app._cancel_requested or app._cancel_pending:
		quit(5)
		return
	print("GUANDAN_CANCEL_SMOKE_OK busy_request=true readiness_race=true intent_cleared_in_lobby=true")
	quit()
