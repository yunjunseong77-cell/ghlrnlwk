extends SceneTree

# Exercises the native-dialog result contract without opening a blocking OS dialog.
# Real Hangul IME composition still needs a manual Windows keyboard check.
class NameFixture extends "res://scripts/main_menu.gd":
	var requested_native_dialog := 0
	var story_start := -1
	func _edit_native_nickname() -> void:
		requested_native_dialog += 1
	func _start_story(at: int) -> void:
		story_start = at
		state = "story"

const Store := preload("res://scripts/training_progress.gd")
var game: Control
var errors: Array[String] = []
var prefix := "res://.godot/native-name-%d" % Time.get_ticks_usec()

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.godot")
	DirAccess.make_dir_recursive_absolute("res://docs/previews")
	var store := Store.new(prefix + "-profile.cfg")
	game = NameFixture.new()
	game.progress_path = prefix + "-story.cfg"
	game.camp_progress_path = prefix + "-camp.cfg"
	game.training_progress = store
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(game)
	await create_timer(2.5).timeout
	check(game.training_progress == store, "Main initialization replaced the isolated account store")
	check(DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_INPUT), "Windows native text input unavailable; run this test with the Windows display server")
	game._name_entry()
	await process_frame
	check(game.requested_native_dialog == 1, "Normal entry did not request native input")
	var form_id: int = game.nickname_form.get_instance_id()
	for value in ["윤", "윤준", "윤준성", "윤민준성", "준성123", "가나다라마바사아자차카타"]:
		game._receive_native_nickname(value, form_id)
		check(game.nickname_preview.text == value and game.nickname_draft == value, "Complete native value was truncated: " + value)
	game._receive_native_nickname("가나다라마바사아자차카타파", form_id)
	game._confirm_nickname()
	check(game.story_start == -1, "Overlong nickname started story")
	game._receive_native_nickname("   ", form_id)
	game._confirm_nickname()
	check(game.story_start == -1, "Empty nickname started story")
	game._receive_native_nickname("윤준성", form_id)
	game._receive_native_nickname("무효", form_id + 1)
	check(game.nickname_draft == "윤준성", "Stale native callback overwrote current name")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/previews/16-native-name-confirmation.png")
	game._confirm_nickname()
	check(game.player_name == "윤준성" and game.story_start == 0, "Native name did not reach game start")
	check(game._names("[name] / [given]") == "윤준성 / 준성", "Story name substitution changed")
	var saved := ConfigFile.new()
	check(saved.load(game.progress_path) == OK, "Nickname did not save to the isolated story profile")
	check(saved.get_value("player", "name", "") == "윤준성", "Full Hangul name not saved")
	game.state = "title"
	game._name_entry()
	await process_frame
	var new_form_id: int = game.nickname_form.get_instance_id()
	check(new_form_id != form_id, "Nickname form identity did not change")
	game._receive_native_nickname("이전입력", form_id)
	check(game.nickname_draft == "윤준성", "Previous dialog affected new form")
	game._close_overlay()
	game._receive_native_nickname("닫힌입력", new_form_id)
	game.queue_free()
	await process_frame
	for suffix in ["-story.cfg", "-camp.cfg", "-profile.cfg", "-profile.cfg.tmp"]:
		if FileAccess.file_exists(prefix + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(prefix + suffix))
	for error in errors:
		push_error(error)
	print("NATIVE_NAME_FLOW ", "PASS" if errors.is_empty() else "FAIL", " — isolated saves, native-result validation, stale callbacks, start and full Hangul name persistence")
	print("Native Windows IME composition requires an interactive keyboard check.")
	quit(0 if errors.is_empty() else 1)
