extends Node

const HOP_FRAME_BUDGET := 60

var probe
var hop_frames := 0

func _ready() -> void:
	if not ClassDB.class_exists("AndroidRuntimeProbe"):
		fail("AndroidRuntimeProbe is not registered")
		return

	probe = ClassDB.instantiate("AndroidRuntimeProbe")
	if probe == null or not probe.has_method("probe"):
		fail("AndroidRuntimeProbe could not be instantiated")
		return
	print("SWIFTGODOT_ANDROID_CONSTRUCTED")

	for method in ["probe_node_api", "start_main_actor_hop", "is_main_actor_hop_completed"]:
		if not probe.has_method(method):
			fail("AndroidRuntimeProbe has no method %s" % method)
			return

	var node_result = probe.call("probe_node_api")
	if str(node_result) != "SWIFTGODOT_ANDROID_NODE_API_OK":
		fail("unexpected node API result: %s" % node_result)
		return
	print(node_result)

	probe.call("start_main_actor_hop")
	set_process(true)

func _process(_delta: float) -> void:
	if probe.call("is_main_actor_hop_completed"):
		set_process(false)
		print("SWIFTGODOT_ANDROID_MAIN_ACTOR_HOP_OK")
		finish()
		return
	hop_frames += 1
	if hop_frames >= HOP_FRAME_BUDGET:
		set_process(false)
		fail("main actor hop did not complete within %d frames" % HOP_FRAME_BUDGET)

func finish() -> void:
	var result = probe.call("probe")
	if not str(result).begins_with("SWIFTGODOT_ANDROID_OK:"):
		fail("unexpected probe result: %s" % result)
		return

	print(result)
	get_tree().quit(0)

func fail(message: String) -> void:
	printerr("SWIFTGODOT_ANDROID_FAIL: " + message)
	get_tree().quit(1)
