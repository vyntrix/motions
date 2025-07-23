@tool
extends EditorPlugin

func _enter_tree() -> void:
	add_autoload_singleton("MotionTracker", "res://addons/motions/motion_tracker.gd")

func _exit_tree() -> void:
	remove_autoload_singleton("MotionTracker")
