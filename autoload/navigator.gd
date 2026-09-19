extends Node
## Navigator — minimal push/pop screen stack for the POC.
## The POC has two screens (carousel, failure); this keeps the door open
## for system browser / inspect views without a rewrite.

var _stack: Array = []  # Array[Node]
var _root: Node = null


func attach(root: Node) -> void:
	_root = root


func open(scene_path: String, params: Dictionary = {}) -> Node:
	if _root == null:
		push_error("Navigator: no root attached")
		return null
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("Navigator: cannot load " + scene_path)
		return null
	var inst: Node = packed.instantiate()
	if inst.has_method("setup"):
		inst.call("setup", params)
	_root.add_child(inst)
	_stack.append(inst)
	_update_visibility()
	return inst


func back() -> void:
	if _stack.size() <= 1:
		return
	var top: Node = _stack.pop_back()
	top.queue_free()
	_update_visibility()


func replace(scene_path: String, params: Dictionary = {}) -> Node:
	while not _stack.is_empty():
		var n: Node = _stack.pop_back()
		n.queue_free()
	return open(scene_path, params)


func current() -> Node:
	return _stack.back() if not _stack.is_empty() else null


func _update_visibility() -> void:
	for i: int in _stack.size():
		_stack[i].visible = (i == _stack.size() - 1)
