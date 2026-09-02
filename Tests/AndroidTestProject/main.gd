extends Node

func _ready() -> void:
	if not ClassDB.class_exists("AndroidRuntimeProbe"):
		fail("AndroidRuntimeProbe is not registered")
		return

	var probe = ClassDB.instantiate("AndroidRuntimeProbe")
	if probe == null or not probe.has_method("probe"):
		fail("AndroidRuntimeProbe could not be instantiated")
		return

	var result = probe.call("probe")
	if not str(result).begins_with("SWIFTGODOT_ANDROID_OK:"):
		fail("unexpected probe result: %s" % result)
		return

	print(result)
	get_tree().quit(0)

func fail(message: String) -> void:
	printerr("SWIFTGODOT_ANDROID_FAIL: " + message)
	get_tree().quit(1)
