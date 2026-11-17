extends RefCounted
## Per-server guest credentials in the application's private user data directory.

const DIRECTORY := "user://mahjong_guest_sessions"
const API_CLIENT := preload("res://modules/foundation/network/api_client.gd")

var directory: String


func _init(path: String = DIRECTORY) -> void:
	directory = ProjectSettings.globalize_path(path)


static func valid_token(token: String) -> bool:
	return API_CLIENT.valid_session_token(token)


func _path(server: String) -> String:
	return directory.path_join(server.sha256_text() + ".session")


func read(server: String) -> String:
	var path := _path(server)
	if server.is_empty() or not FileAccess.file_exists(path): return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() != 43: return ""
	var token := file.get_buffer(43).get_string_from_ascii()
	return token if valid_token(token) else ""


func save(server: String, token: String) -> Error:
	if server.is_empty() or not valid_token(token): return ERR_INVALID_PARAMETER
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK: return error
	var path := _path(server)
	var temporary := "%s.%d.%d.tmp" % [path, OS.get_process_id(), Time.get_ticks_usec()]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	if OS.has_feature("linux") or OS.has_feature("macos") or OS.has_feature("android"):
		error = FileAccess.set_unix_permissions(temporary, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER)
	if error == OK:
		file.store_string(token)
		file.flush()
		error = file.get_error()
	file.close()
	if error == OK: error = DirAccess.rename_absolute(temporary, path)
	if error != OK: DirAccess.remove_absolute(temporary)
	return error


func remove(server: String, token: String) -> Error:
	if token.is_empty() or read(server) != token: return OK
	return DirAccess.remove_absolute(_path(server))
