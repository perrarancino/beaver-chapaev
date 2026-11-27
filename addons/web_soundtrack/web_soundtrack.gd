@tool
extends EditorPlugin

class SoundtrackExport extends EditorExportPlugin:
	var output_directory := ""

	func _get_name() -> String:
		return "WebSoundtrack"

	func _export_begin(features: PackedStringArray, _debug: bool, path: String, _flags: int) -> void:
		output_directory = ""
		if "web" in features and path.get_extension().to_lower() == "html":
			var absolute_path := path if path.is_absolute_path() else "res://".path_join(path)
			output_directory = ProjectSettings.globalize_path(absolute_path).get_base_dir()

	func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
		if output_directory.is_empty() or not path.begins_with("res://assets/music/") or path.get_extension() != "mp3":
			return
		var source := ProjectSettings.globalize_path(path)
		var destination := output_directory.path_join(path.trim_prefix("res://"))
		var error := DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
		if error == OK:
			error = DirAccess.copy_absolute(source, destination)
		if error == OK:
			skip()
		else:
			push_warning("Keeping soundtrack in the Web pack: " + path)


var soundtrack_export := SoundtrackExport.new()


func _enter_tree() -> void:
	add_export_plugin(soundtrack_export)


func _exit_tree() -> void:
	remove_export_plugin(soundtrack_export)
