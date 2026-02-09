@tool
extends EditorPlugin

var editor_script_list:ItemList
var script_list_cache = {}
var editor_script_file_popup:PopupMenu

var editor_tab_bar:TabBar
var new_scene_button:Button

var selected_callable
var hovered_callable
var rearranged_callable
var button_pressed_callable
var tab_close_callable
var gui_input_callable

var preview_panel:Control
var popup:PopupMenu

var replace_tab_bar:= TabBar.new()

var tab_data = {}
var current_tab
var new_scene_flag:=false
var building_tabs_flag:= false

var _last_open_tab_titles_hash:int
var _last_script_titles_hash:int


func _enter_tree() -> void:
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_fs_changed, 1)
	EditorInterface.get_script_editor().editor_script_changed.connect(_on_script_opened, 1)
	var tree = EditorInterface.get_file_system_dock().find_children("*", "Tree", true, false)[0] as Tree
	tree.item_activated.connect(_on_filesystem_file_activated, 1)
	var fs_list = EditorInterface.get_file_system_dock().find_children("*", "FileSystemList", true, false)[0] as ItemList
	fs_list.item_activated.connect(_on_filesystem_file_activated, 1)
	
	
	scene_changed.connect(_on_scene_changed)
	main_screen_changed.connect(_on_main_screen_changed)
	
	_set_editor_elements()
	
	for data in editor_tab_bar.get_signal_list():
		var sig = data.name
		#print(editor_tab_bar.get_signal_connection_list(sig))
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
	
	
	replace_tab_bar.tab_changed.connect(_on_replace_tab_bar_pressed)
	replace_tab_bar.tab_hovered.connect(_on_replace_tab_bar_hovered)
	replace_tab_bar.active_tab_rearranged.connect(_on_replace_tab_rearranged)
	replace_tab_bar.tab_close_pressed.connect(_on_replace_tab_closed)
	replace_tab_bar.tab_button_pressed.connect(_on_replace_tab_button_pressed)
	replace_tab_bar.gui_input.connect(_replace_gui_input)
	
	replace_tab_bar.mouse_exited.connect(_on_replace_tab_mouse_exited)
	
	new_scene_button = editor_tab_bar.get_child(0)
	new_scene_button.pressed.connect(_on_new_scene_button_pressed)
	
	editor_tab_bar.replace_by(replace_tab_bar)
	replace_tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	replace_tab_bar.drag_to_rearrange_enabled = true
	replace_tab_bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ACTIVE_ONLY
	
	_refresh_replace_bar()

func _exit_tree() -> void:
	if is_instance_valid(replace_tab_bar):
		replace_tab_bar.replace_by(editor_tab_bar)
	
	new_scene_button.pressed.disconnect(_on_new_scene_button_pressed)
	
	editor_tab_bar.tab_changed.connect(selected_callable)
	editor_tab_bar.tab_hovered.connect(hovered_callable)
	editor_tab_bar.active_tab_rearranged.connect(rearranged_callable)
	editor_tab_bar.tab_button_pressed.connect(button_pressed_callable)
	editor_tab_bar.tab_close_pressed.connect(tab_close_callable)
	editor_tab_bar.gui_input.connect(gui_input_callable)


#region refresh

func _process(delta: float) -> void:
	var editor_tab_names = _get_scene_tab_hash_array()
	var scene_hash = editor_tab_names.hash()
	var script_list_names = _get_script_list_hash_array()
	var _script_hash = script_list_names.hash()
	var refreshing = false
	if scene_hash != _last_open_tab_titles_hash or _script_hash != _last_script_titles_hash:
		refreshing = true
		_refresh_replace_bar()
	_last_open_tab_titles_hash = scene_hash
	_last_script_titles_hash = _script_hash
	if not refreshing and new_scene_button.get_rect().intersects(replace_tab_bar.get_tab_rect(replace_tab_bar.tab_count - 1)):
		_move_new_button()

func _get_scene_tab_hash_array():
	var titles = []
	for i in range(editor_tab_bar.tab_count):
		titles.append(editor_tab_bar.get_tab_title(i))
	titles.append(editor_tab_bar.current_tab)
	return titles

func _get_script_list_hash_array():
	var names = []
	for i in range(editor_script_list.item_count):
		names.append(editor_script_list.get_item_text(i))
	names.append_array(editor_script_list.get_selected_items())
	return names

func _on_main_screen_changed(new_screen):
	_refresh_replace_bar()

func _on_filesystem_file_activated():
	var selected = EditorInterface.get_selected_paths()
	if selected.is_empty():return
	if selected[0].ends_with(".tscn"):
		_swap_to_scene_editor()

func _on_fs_changed():
	_build_replace_bar()

#endregion


#region Replace Tab Bar Signals

func _on_replace_tab_bar_pressed(idx:int):
	if building_tabs_flag:return
	#print("PRESSED: %s" % idx)
	current_tab = idx
	if is_valid_scene_tab(idx):
		selected_callable.call(_get_editor_tab_mirror(idx))
		_swap_to_scene_editor.call_deferred()
		return
	
	var metadata = replace_tab_bar.get_tab_metadata(idx)
	if metadata == null:
		return
	
	var title = replace_tab_bar.get_tab_title(idx)
	_open_script_by_name(title)
	EditorInterface.set_main_screen_editor("Script")

func _on_replace_tab_bar_hovered(idx:int):
	if is_valid_scene_tab(idx):
		hovered_callable.call(_get_editor_tab_mirror(idx))
		_move_preview(idx)

func _on_replace_tab_rearranged(to_idx:int):
	_index_tabs()
	#_refresh_replace_bar()

func _on_replace_tab_closed(idx:int):
	if is_valid_scene_tab(idx):
		tab_close_callable.call(_get_editor_tab_mirror(idx))
	else:
		var title = replace_tab_bar.get_tab_title(idx)
		_close_script(title)
	#_refresh_replace_bar()

func _on_replace_tab_button_pressed(idx:int):
	printerr("IS THIS EVER CALLED? - UnifiedTabBar - _on_replace_tab_button_pressed")
	pass

func _replace_gui_input(event:InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if is_valid_scene_tab(replace_tab_bar.current_tab):
				add_child(editor_tab_bar)
				gui_input_callable.call(event)
				popup.position = DisplayServer.mouse_get_position()
				remove_child(editor_tab_bar)

func _on_replace_tab_mouse_exited():
	editor_tab_bar.mouse_exited.emit()

#endregion


#region obsolete

func _on_scene_changed(new_root:Node): # this should be able to go
	#_swap_to_scene_editor() 
	pass

func _on_script_opened(script): # this should be able to go
	return
	#if not is_instance_valid(script):
		#return
	#if _script_opened_in_replace_bar(script):
		#return
	#_new_script_tab(script)
	#_refresh_replace_bar()

#func _script_opened_in_replace_bar(script):
	#for i in range(replace_tab_bar.tab_count):
		#var meta = replace_tab_bar.get_tab_metadata(i)
		#if meta and meta == script.resource_path:
			#return true
	#return false

#func get_scene_path(idx:int):
	#var adjusted_idx = _get_adjusted_idx(idx)
	#if adjusted_idx == -1:
		#return
	#var _name = editor_tab_bar.get_tab_title(adjusted_idx)
	#var current_open_scenes = EditorInterface.get_open_scenes()
	#for path in current_open_scenes:
		#if path.get_basename().ends_with(_name):
			#return path

#func _get_adjusted_idx(idx:int):
	#var adjusted_idx = -1
	#for i in range(editor_tab_bar.tab_count):
		#if editor_tab_bar.get_tab_metadata(i) == null:
			#adjusted_idx += 1
		#if i == idx:
			#return i
	#return -1

#func _new_script_tab(title):
	#var cache_data = script_list_cache.get(title)
	#if cache_data == null:
		#return
	#cache_data = script_list_cache.get(title)
	#var icon = cache_data.get("icon", EditorInterface.get_editor_theme().get_icon("GDScript", "EditorIcons"))
	#var path = cache_data.get("path")
	#replace_tab_bar.add_tab(title,  icon)
	#replace_tab_bar.set_tab_metadata(replace_tab_bar.tab_count - 1, path)

#endregion


#region Tab Build

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


func _refresh_replace_bar():
	_build_replace_bar.call_deferred()
	#print("refresh")

func _build_replace_bar():
	#tab_data.clear()
	
	current_tab = replace_tab_bar.current_tab
	building_tabs_flag = true
	replace_tab_bar.clear_tabs()

	var current_tab_name = _get_current_editor_tab_name()
	populate_script_list_cache()
	var open_scripts = script_list_cache.keys()
	var open_scene_titles = get_current_editor_tab_titles()
	
	var current = {}
	if not tab_data.is_empty():
		for i in range(tab_data.size()):
			var data = tab_data[i]
			var title = data.title
			var meta = data.get("meta")
			if meta != null:
				var clear_data = _can_clear_tab(title, open_scripts)
				if clear_data.get("clear"):
					tab_data.erase(i)
					continue
				title = clear_data.get("title")
			else:
				var clear_data = _can_clear_tab(title, open_scene_titles)
				if clear_data.get("clear"):
					tab_data.erase(i)
					continue
				title = clear_data.get("title")
			
			if title == current_tab_name:
				current_tab = replace_tab_bar.tab_count
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
		if title == current_tab_name:
			current_tab = i
		replace_tab_bar.add_tab(title, editor_tab_bar.get_tab_icon(i))
	
	
	for title in open_scripts:
		var cache_data = script_list_cache.get(title)
		if cache_data == null:
			continue
		if title in current:
			replace_tab_bar.set_tab_metadata(current[title], cache_data.get("path"))
			continue
		if title == current_tab_name:
			current_tab = replace_tab_bar.tab_count
		
		var icon = cache_data.get("icon", EditorInterface.get_editor_theme().get_icon("GDScript", "EditorIcons"))
		var path = cache_data.get("path")
		replace_tab_bar.add_tab(title,  icon)
		replace_tab_bar.set_tab_metadata(replace_tab_bar.tab_count - 1, path)
	
	
	if current_tab is int:
		current_tab = min(current_tab, replace_tab_bar.tab_count - 1)
		replace_tab_bar.current_tab = current_tab
	
	if new_scene_flag:
		_handle_new_scene.call_deferred()
	
	_index_tabs()
	_move_new_button.call_deferred()
	building_tabs_flag = false


func _get_current_editor_tab_name():
	var current_main_screen
	for child in EditorInterface.get_editor_main_screen().get_children():
		if child.visible:
			current_main_screen = child
			break
	var main_screen_class = current_main_screen.get_class()
	if main_screen_class == "CanvasItemEditor" or main_screen_class == "Node3DEditor":
		return editor_tab_bar.get_tab_title(editor_tab_bar.current_tab)
	elif main_screen_class == "WindowWrapper":
		var content = current_main_screen.get_child(1)
		if content == EditorInterface.get_script_editor():
			var sel_items = editor_script_list.get_selected_items()
			if not sel_items.is_empty():
				return editor_script_list.get_item_text(sel_items[0])
	return ""

func _can_clear_tab(title, titles_array):
	var clear_tab = true
	if title == "[empty]":
		if "[unsaved](*)" in titles_array:
			return {"clear":false, "title":"[unsaved](*)"}
	var raw_title = title
	var unsaved_title = title
	if title.ends_with("(*)"):
		raw_title = raw_title.trim_suffix("(*)")
	else:
		unsaved_title = title + "(*)"
	if raw_title in titles_array:
		title = raw_title
		clear_tab = false
	if title in titles_array:
		clear_tab = false
	if unsaved_title in titles_array:
		title = unsaved_title
		clear_tab = false
	return {"clear":clear_tab, "title":title}

func _move_new_button():
	var tab_button = replace_tab_bar.get_child(0)
	var rect = replace_tab_bar.get_tab_rect(replace_tab_bar.tab_count - 1)
	tab_button.position.x = rect.size.x + rect.position.x

func _on_new_scene_button_pressed():
	new_scene_flag = true

func _handle_new_scene():
	new_scene_flag = false
	replace_tab_bar.current_tab = replace_tab_bar.tab_count - 1
	EditorInterface.set_main_screen_editor.call_deferred("2D")

#endregion


#region Editor Tab Utils

func is_valid_scene_tab(idx:int):
	return replace_tab_bar.get_tab_metadata(idx) == null

func _get_editor_tab_mirror(idx:int):
	return _get_editor_tab_index(_get_tab_name(idx))

func _get_tab_name(idx:int):
	return replace_tab_bar.get_tab_title(idx)

func _get_editor_tab_index(_name):
	for i in range(editor_tab_bar.tab_count):
		if editor_tab_bar.get_tab_title(i) == _name:
			return i
	return -1

func get_current_editor_tab_titles():
	var titles = []
	for i in range(editor_tab_bar.tab_count):
		titles.append(editor_tab_bar.get_tab_title(i))
	return titles

#endregion


#region Misc Editor

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


func _set_editor_elements():
	var scene_tabs = EditorInterface.get_base_control().find_children("*", "EditorSceneTabs",true, false)[0]
	editor_tab_bar = scene_tabs.get_child(0).get_child(0).get_child(0) as TabBar
	preview_panel = scene_tabs.get_child(1)
	popup = scene_tabs.get_child(0).get_child(0).get_child(1)
	
	var lists = EditorInterface.get_script_editor().find_children("*", "ItemList", true, false)
	editor_script_list = lists[0]
	editor_script_file_popup = EditorInterface.get_script_editor().get_child(0).get_child(0).get_child(0).get_child(0, true)

#endregion


#region Script List Utils

func populate_script_list_cache():
	script_list_cache = {}
	var paths = []
	for i in range(editor_script_list.item_count):
		var title = editor_script_list.get_item_text(i)
		var icon = editor_script_list.get_item_icon(i)
		var path = editor_script_list.get_item_tooltip(i)
		script_list_cache[title] = {"path": path, "icon": icon}
		paths.append(path)
	
	return paths
	for script in EditorInterface.get_script_editor().get_open_scripts():
		paths.append(script.resource_path)
	return paths

func _open_script_by_name(_name):
	var target_i = _get_script_item_idx(_name)
	if target_i != -1:
		editor_script_list.select(target_i)
		editor_script_list.item_selected.emit(target_i)

func _close_script(_name):
	var version = Engine.get_version_info()
	var id = 10
	if version.minor < 6:
		id = 10
	elif version.minor == 6:
		id = 15
	
	var target_i = _get_script_item_idx(_name)
	if target_i != -1:
		editor_script_list.select(target_i)
		if editor_script_file_popup.item_count == 0:
			editor_script_file_popup.popup()
		editor_script_file_popup.id_pressed.emit(id)
		editor_script_file_popup.hide()

func _get_script_item_idx(_name):
	for i in range(editor_script_list.item_count):
		if editor_script_list.get_item_text(i) == _name:
			return i
	return -1

#endregion
