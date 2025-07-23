extends Node

@onready var label: Label = $Label
@onready var trail_display: Line2D = $TrailDisplay

func _ready() -> void:
	MotionTracker.motion_detected.connect(_on_motion_detected)
	MotionTracker.gesture_completed.connect(_on_gesture_completed)

	if trail_display:
		trail_display.width = 3.0
		trail_display.default_color = Color.PALE_VIOLET_RED

	if label:
		label.text = "Draw with left mouse button to detect gestures!"

func _on_motion_detected(motion_type: String, data: Dictionary) -> void:
	print("Motion detected: ", motion_type)
	print("Velocity: ", data.velocity)
	print("Position: ", data.position)

	if label:
		label.text = "Current Motion: " + motion_type

func _on_gesture_completed(gesture: String, confidence: float):
	# Handle completed gesture recognition
	print("Gesture completed: ", gesture, " (confidence: ", confidence, ")")

	# Update label with completed gesture
	if label:
		label.text = "Gesture: " + gesture + " (" + str(int(confidence * 100)) + "% confidence)"

	# You can add specific responses to different gestures
	match gesture:
		"CIRCLE_CLOCKWISE":
			print("Clockwise circle detected!")
			# Add your logic here
		"CIRCLE_COUNTER_CLOCKWISE":
			print("Counter-clockwise circle detected!")
			# Add your logic here
		"SCOOP_UP":
			print("Scoop up gesture!")
			# Add your logic here
		"ZIGZAG":
			print("Zigzag pattern detected!")
			# Add your logic here
		_:
			print("Other gesture: ", gesture)

func _process(_delta):
	# Update trail visualization
	if trail_display and MotionTracker.is_currently_tracking():
		var trail = MotionTracker.get_current_trail()
		trail_display.clear_points()
		for point in trail:
			trail_display.add_point(point)

func _input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_T:
				MotionTracker.tracking_enabled = !MotionTracker.tracking_enabled
				print("Tracking ", "enabled" if MotionTracker.tracking_enabled else "disabled")
			KEY_C:
				MotionTracker.clear_trail()
				print("Trail cleared")
			KEY_S:
				# Adjust sensitivity
				var current = MotionTracker.min_movement_threshold
				MotionTracker.set_sensitivity(current + 1.0 if current < 10.0 else 1.0)
				print("Sensitivity set to: ", MotionTracker.min_movement_threshold)
