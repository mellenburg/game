extends SceneTree
## One-shot smoke screenshot of the Saturn stage. Run with:
##
##   xvfb-run godot --path godot --script res://tests/smoke_saturn.gd
##
## Selects the Saturn stage on PlayerLoadout, loads the main scene,
## advances a few physics ticks so the camera positions itself and the
## sun shader binds, then captures a viewport screenshot to
## /tmp/saturn_smoke.png and exits. Lives under tests/ because it
## reuses the headless test harness convention; not part of `make test`
## (it boots the full scene, which the CI test path explicitly avoids).

const STAGE_PATH := "res://scenes/main.tscn"
const OUT_PATH := "/tmp/saturn_smoke.png"


func _init() -> void:
	# Wait one process frame so the autoload nodes (PlayerLoadout etc.)
	# have been added to the root before we configure them — _init
	# fires before the autoload tree is materialised.
	await process_frame
	var loadout: Node = root.get_node_or_null("PlayerLoadout")
	if loadout == null:
		push_error("smoke_saturn: PlayerLoadout autoload missing")
		quit(1)
		return
	loadout.selected_stage_id = "saturn"
	loadout.launched = false  # avoid scheduling waves; we just want a still frame
	change_scene_to_file(STAGE_PATH)
	# Wait a few process frames so the scene is fully entered + the
	# rings / camera are ready, then ask for a screenshot.
	for _i in range(60):
		await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		push_error("smoke_saturn: viewport image was null")
		quit(1)
		return
	img.save_png(OUT_PATH)
	print("smoke_saturn: wrote ", OUT_PATH, " (", img.get_size(), ")")
	quit()
