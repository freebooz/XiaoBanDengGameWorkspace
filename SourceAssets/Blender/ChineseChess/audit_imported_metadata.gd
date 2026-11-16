extends SceneTree
func _initialize() -> void:
	var model = load('res://modules/games/chinese_chess/assets/models/chess_pieces.glb').instantiate()
	for node in model.get_children():
		print('IMPORT_METADATA ',node.name,' ',node.get_meta_list())
		for key in node.get_meta_list():
			print(key,'=',node.get_meta(key))
		break
	model.free()
	quit()
