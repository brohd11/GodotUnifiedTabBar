@tool
extends EditorPlugin



var editor_tab_bar:TabBar
var selected_callable
var hovered_callable
var rearranged_callable
var button_pressed_callable
var tab_close_callable
var gui_input_callable

var preview_panel:Control
var popup:PopupMenu

var replace_tab_bar:=TabBar.new()

var tab_data = {}
var current_tab

var _last_open_tab_titles_hash:int

var building_tabs = false

func _enter_tree() -> void:
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_fs_changed, 1)
	EditorInterface.get_script_editor().editor_script_changed.connect(_on_script_opened)
	
	_set_editor_elements()
	
	for data in editor_tab_bar.get_signal_list():
		var sig = data.name
		print(editor_tab_bar.get_signal_connection_list(sig))
		var con_list = editor_tab_bar.get_signal_connection_list(sig)
		for con_data in con_list:
			
			var callable = con_data.callable as Callable
			var method = callable.get_method()
			if method == "EditorSceneTabs::_scene_tab_changed":
				selected_callable = callable
				editor_tab_bar.tab_changed.disconnect(selected_callable)
			elif method == "EditorSceneTabs::_scene_tab_hovered":
				hovered_callable = callable
				editor_tab_bar.tab_hovered.disconnect(hovered_callable)
			elif method == "EditorSceneTabs::_scene_tab_closed":
				tab_close_callable = callable
				editor_tab_bar.tab_close_pressed.disconnect(callable)
			elif method == "EditorSceneTabs::_reposition_active_tab":
				rearranged_callable = callable
				editor_tab_bar.active_tab_rearranged.disconnect(callable)
			elif method == "EditorSceneTabs::_scene_tab_script_edited":
				button_pressed_callable = callable
				editor_tab_bar.tab_button_pressed.disconnect(callable)
			elif method == "EditorSceneTabs::_scene_tab_input":
				gui_input_callable = callable
				editor_tab_bar.gui_input.disconnect(callable)
	
	#editor_tab_bar.tab_changed.connect(_on_editor_tab_bar_pressed)
	#editor_tab_bar.tab_hovered.connect(_on_editor_tab_bar_hovered)
	#editor_tab_bar.active_tab_rearranged.connect(_on_editor_tab_rearranged)
	#editor_tab_bar.tab_close_pressed.connect(_on_editor_tab_closed)
	#editor_tab_bar.tab_button_pressed.connect(_on_editor_tab_button_pressed)
	#editor_tab_bar.gui_input.connect(_on_editor_gui_input)
	
	replace_tab_bar.tab_changed.connect(_on_replace_tab_bar_pressed)
	replace_tab_bar.tab_hovered.connect(_on_replace_tab_bar_hovered)
	replace_tab_bar.active_tab_rearranged.connect(_on_replace_tab_rearranged)
	replace_tab_bar.tab_close_pressed.connect(_on_replace_tab_closed)
	replace_tab_bar.tab_button_pressed.connect(_on_replace_tab_button_pressed)
	replace_tab_bar.gui_input.connect(_replace_gui_input)
	
	editor_tab_bar.draw.connect(_on_redraw)
	
	
	editor_tab_bar.get_parent_control().draw.connect(_on_redraw)
	
	
	editor_tab_bar.replace_by(replace_tab_bar)
	
	replace_tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	replace_tab_bar.drag_to_rearrange_enabled = true
	replace_tab_bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ACTIVE_ONLY
	
	_refresh_replace_bar()

func _exit_tree() -> void:
	if is_instance_valid(replace_tab_bar):
		replace_tab_bar.replace_by(editor_tab_bar)
	
	#editor_tab_bar.tab_changed.disconnect(_on_editor_tab_bar_pressed)
	#editor_tab_bar.tab_hovered.disconnect(_on_editor_tab_bar_hovered)
	#editor_tab_bar.active_tab_rearranged.disconnect(_on_editor_tab_rearranged)
	#editor_tab_bar.tab_close_pressed.disconnect(_on_editor_tab_closed)
	#editor_tab_bar.tab_button_pressed.disconnect(_on_editor_tab_button_pressed)
	#editor_tab_bar.gui_input.disconnect(_on_editor_gui_input)
	
	editor_tab_bar.tab_changed.connect(selected_callable)
	editor_tab_bar.tab_hovered.connect(hovered_callable)
	editor_tab_bar.active_tab_rearranged.connect(rearranged_callable)
	editor_tab_bar.tab_button_pressed.connect(button_pressed_callable)
	editor_tab_bar.tab_close_pressed.connect(tab_close_callable)
	editor_tab_bar.gui_input.connect(gui_input_callable)
	

func _process(delta: float) -> void:
	var editor_tab_names = get_current_tab_titles()
	var _hash = editor_tab_names.hash()
	if _hash != _last_open_tab_titles_hash:
		_refresh_replace_bar()
	_last_open_tab_titles_hash = _hash
	pass


func _on_replace_tab_bar_pressed(idx:int):
	if building_tabs:return
	print("PRESSED: %s" % idx)
	current_tab = idx
	if is_valid_scene_tab(idx):
		selected_callable.call(_get_editor_tab_mirror(idx))
		_swap_to_scene_editor.call_deferred()
		return

	var metadata = replace_tab_bar.get_tab_metadata(idx)
	if metadata == null:
		return
	
	EditorInterface.set_main_screen_editor("Script")
	EditorInterface.edit_script(load(metadata))
	_refresh_replace_bar()


func _on_replace_tab_bar_hovered(idx:int):
	if is_valid_scene_tab(idx):
		hovered_callable.call(_get_editor_tab_mirror(idx))
		_move_preview(idx)



func _on_replace_tab_rearranged(to_idx:int):
	_index_tabs()
	_refresh_replace_bar()

func _on_replace_tab_closed(idx:int):
	if is_valid_scene_tab(idx):
		print("DELETE: ", _get_editor_tab_mirror(idx))
		tab_close_callable.call(_get_editor_tab_mirror(idx))
	else:
		replace_tab_bar.remove_tab(idx)
	_refresh_replace_bar()

func _on_replace_tab_button_pressed(idx:int):
	print("TAB BUTTON PRESSED REPLACE")
	pass



func _replace_gui_input(event:InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if is_valid_scene_tab(replace_tab_bar.current_tab):
				add_child(editor_tab_bar)
				gui_input_callable.call(event)
				popup.position = DisplayServer.mouse_get_position()
				remove_child(editor_tab_bar)

func _on_editor_tab_bar_pressed(idx:int):
	print("EDITOR PRESSED")


func _on_editor_tab_bar_hovered(idx:int):
	print("EDITOR HOVERED")



func _on_editor_tab_rearranged(to_idx:int):
	print("EDITOR REARRANGED")

func _on_editor_tab_closed(idx:int):
	print("EDITOR CLOSED")

func _on_editor_tab_button_pressed(idx:int):
	print("EDITOR BUTTON PRESSED")
	pass



func _on_editor_gui_input(event:InputEvent):
	print("EDITOR GUI")



func _on_script_opened(script):
	if not is_instance_valid(script):
		return
	if _script_opened_in_replace_bar(script):
		return
	_new_tab_replace(script)
	_refresh_replace_bar()

func _index_tabs():
	current_tab = replace_tab_bar.current_tab
	tab_data.clear()
	for i in range(replace_tab_bar.tab_count):
		tab_data[i] = {
			"title":replace_tab_bar.get_tab_title(i),
			"icon":replace_tab_bar.get_tab_icon(i)
		}
		var meta = replace_tab_bar.get_tab_metadata(i)
		if meta != null:
			tab_data[i]["meta"] = meta


func _on_fs_changed():
	_build_replace_bar()

func _editor_tab_bar_event(a=null, b=null, c=null):
	_refresh_replace_bar()
	pass

func _on_redraw():
	print("REDRAW")
	_refresh_replace_bar()

func _refresh_replace_bar():
	print("refresh")
	#if _build_replace_bar != null and _build_replace_bar.is_valid():
	_build_replace_bar.call_deferred()
	


func _build_replace_bar():
	#tab_data.clear()
	
	building_tabs = true
	
	#print(tab_data)
	
	replace_tab_bar.clear_tabs()
	
	var open_scripts = get_current_open_script_paths()
	var open_scene_titles = get_current_tab_titles()
	
	var current = {}
	if not tab_data.is_empty():
		for i in range(tab_data.size()):
			var data = tab_data[i]
			var title = data.title
			var meta = data.get("meta")
			if meta != null:
				if not meta in open_scripts:
					tab_data.erase(i)
					continue
			else:
				var clear_tab = true
				var raw_title = title
				var unsaved_title = title
				if title.ends_with("(*)"):
					raw_title = raw_title.trim_suffix("(*)")
				else:
					unsaved_title = title + "(*)"
				if raw_title in open_scene_titles:
					title = raw_title
					clear_tab = false
				if title in open_scene_titles:
					clear_tab = false
				if unsaved_title in open_scene_titles:
					title = unsaved_title
					clear_tab = false
				if clear_tab:
					print("CLEAR: ", title)
					tab_data.erase(i)
					continue
			
			replace_tab_bar.add_tab(title)
			var new_idx = replace_tab_bar.tab_count - 1
			replace_tab_bar.set_tab_icon(new_idx, data.icon)
			if meta != null:
				replace_tab_bar.set_tab_metadata(new_idx, meta)
			current[title] = new_idx
	
	
	for i in range(editor_tab_bar.tab_count):
		var title = editor_tab_bar.get_tab_title(i)
		if title in current:
			continue
		_new_tab_scene(title, editor_tab_bar.get_tab_icon(i))
	
	
	for script in EditorInterface.get_script_editor().get_open_scripts():
		var title = script.resource_path.get_file()
		if title in current:
			replace_tab_bar.set_tab_metadata(current[title], script.resource_path)
			continue
		_new_tab_replace(script)
	
	#for i in range(replace_tab_bar.tab_count):
		#var title = replace_tab_bar.get_tab_title(i)
		#var tab_idx = tab_data.get(title)
		#if tab_idx != null:
			#editor_tab_bar.move_tab(i, tab_idx)
	
	if current_tab is int:
		current_tab = min(current_tab, replace_tab_bar.tab_count - 1)
		replace_tab_bar.current_tab = current_tab
	
	_index_tabs()
	_move_new_button.call_deferred()
	building_tabs = false

func _move_new_button():
	var tab_button = replace_tab_bar.get_child(0)
	var rect = replace_tab_bar.get_tab_rect(replace_tab_bar.tab_count - 1)
	tab_button.position.x = rect.size.x + rect.position.x


func _new_tab_replace(script):
	var script_path = script.resource_path
	
	replace_tab_bar.add_tab(script.resource_path.get_file(), EditorInterface.get_editor_theme().get_icon("GDScript", "EditorIcons"))
	replace_tab_bar.set_tab_metadata(replace_tab_bar.tab_count - 1, script_path)

func _new_tab_scene(title, icon=null):
	replace_tab_bar.add_tab(title, icon)


func is_valid_scene_tab(idx:int):
	return replace_tab_bar.get_tab_metadata(idx) == null

func _get_adjusted_idx(idx:int):
	var adjusted_idx = -1
	for i in range(editor_tab_bar.tab_count):
		if editor_tab_bar.get_tab_metadata(i) == null:
			adjusted_idx += 1
		if i == idx:
			return i
	return -1

func _get_editor_tab_mirror(idx:int):
	return _get_editor_tab_index(_get_tab_name(idx))

func _get_tab_name(idx:int):
	return replace_tab_bar.get_tab_title(idx)

func _get_editor_tab_index(_name):
	for i in range(editor_tab_bar.tab_count):
		if editor_tab_bar.get_tab_title(i) == _name:
			return i
	return -1


func _script_opened_in_replace_bar(script):
	for i in range(replace_tab_bar.tab_count):
		var meta = replace_tab_bar.get_tab_metadata(i)
		if meta and meta == script.resource_path:
			return true
	return false


func get_current_open_script_paths():
	var paths = []
	for script in EditorInterface.get_script_editor().get_open_scripts():
		paths.append(script.resource_path)
	return paths

func get_current_tab_titles():
	var titles = []
	for i in range(editor_tab_bar.tab_count):
		titles.append(editor_tab_bar.get_tab_title(i))
	return titles

func _move_preview(idx:int):
	preview_panel.position = Vector2.ZERO
	var tab_rect = replace_tab_bar.get_tab_rect(idx)
	var new_position = tab_rect.position
	new_position.y += tab_rect.size.y
	preview_panel.get_child(0).position = new_position

func _swap_to_scene_editor():
	var scene_root = EditorInterface.get_edited_scene_root()
	if scene_root is Node3D:
		EditorInterface.set_main_screen_editor("3D")
	elif scene_root is Control or scene_root is Node2D:
		EditorInterface.set_main_screen_editor("2D")
	else: # handles node, not sure which would be appropriate
		EditorInterface.set_main_screen_editor("2D")
	_refresh_replace_bar()

func get_scene_path(idx:int):
	var adjusted_idx = _get_adjusted_idx(idx)
	if adjusted_idx == -1:
		return
	var _name = editor_tab_bar.get_tab_title(adjusted_idx)
	var current_open_scenes = EditorInterface.get_open_scenes()
	for path in current_open_scenes:
		if path.get_basename().ends_with(_name):
			return path

func _set_editor_elements():
	var scene_tabs = EditorInterface.get_base_control().find_children("*", "EditorSceneTabs",true, false)[0]
	editor_tab_bar = scene_tabs.get_child(0).get_child(0).get_child(0) as TabBar
	preview_panel = scene_tabs.get_child(1)
	popup = scene_tabs.get_child(0).get_child(0).get_child(1)
