extends Node

signal motion_detected(motion_type: String, data: Dictionary)
signal gesture_completed(gesture: String, confidence: float)

enum MotionType {
	NONE,
	LEFT,
	RIGHT,
	UP,
	DOWN,
	DIAGONAL_UP_LEFT,
	DIAGONAL_UP_RIGHT,
	DIAGONAL_DOWN_LEFT,
	DIAGONAL_DOWN_RIGHT,
	CIRCLE_CLOCKWISE,
	CIRCLE_COUNTER_CLOCKWISE,
	ZIGZAG,
	SCOOP_UP,
	SCOOP_DOWN,
	SPIRAL,
	WAVE,
	TRIANGLE,
	SQUARE
}

# Configuration
@export var tracking_enabled: bool = true
@export var min_movement_threshold: float = 5.0
@export var gesture_timeout: float = 2.0
@export var circle_segments_required: int = 8
@export var smoothing_factor: float = 0.3

# Internal tracking
var mouse_trail: Array[Vector2] = []
var last_mouse_pos: Vector2
var current_gesture_start_time: float
var is_tracking: bool = false
var velocity_history: Array[Vector2] = []
var direction_changes: Array[float] = []

# Gesture recogintion parameters
var max_trail_length: int = 100
var min_gesture_points: int = 5

func _ready() -> void:
	set_process_input(true)

func _input(event: InputEvent) -> void:
	if not tracking_enabled:
		return

	if event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	var current_pos: Vector2 = event.position

	if not is_tracking:
		return

	if mouse_trail.is_empty() or current_pos.distance_to(last_mouse_pos) >= min_movement_threshold:
		mouse_trail.append(current_pos)

		if mouse_trail.size() > 1:
			var velocity = current_pos - last_mouse_pos
			velocity_history.append(velocity)

			if velocity_history.size() > 20:
				velocity_history.pop_front()

		if mouse_trail.size() > max_trail_length:
			mouse_trail.pop_front()
			if velocity_history.size() > 0:
				velocity_history.pop_front()

		last_mouse_pos = current_pos

		_analyze_current_motion()

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_start_tracking()
		else:
			_stop_tracking()

func _start_tracking() -> void:
	is_tracking = true
	mouse_trail.clear()
	velocity_history.clear()
	direction_changes.clear()
	current_gesture_start_time = Time.get_unix_time_from_system()
	last_mouse_pos = get_viewport().get_mouse_position()

func _stop_tracking() -> void:
	if is_tracking and mouse_trail.size() >= min_gesture_points:
		_analyze_complete_gesture()

	is_tracking = false
	mouse_trail.clear()
	velocity_history.clear()
	direction_changes.clear()

func _analyze_current_motion() -> void:
	if velocity_history.size() < 3:
		return

	var recent_velocity = _get_average_velocity(3)
	var motion_type = _classify_direction(recent_velocity)

	var motion_data = {
		"velocity": recent_velocity,
		"position": last_mouse_pos,
		"trail_length": mouse_trail.size()
	}

	motion_detected.emit(MotionType.keys()[motion_type], motion_data)

func _analyze_complete_gesture() -> void:
	if mouse_trail.size() < min_gesture_points:
		return

	var gesture_type = _recognize_gesture()
	var confidence = _calculate_confidence(gesture_type)

	gesture_completed.emit(MotionType.keys()[gesture_type], confidence)

func _recognize_gesture() -> MotionType:
	var circle_result = _detect_circle()
	if circle_result != MotionType.NONE:
		return circle_result

	var shape_result = _detect_shapes()
	if shape_result != MotionType.NONE:
		return shape_result

	var pattern_result = _detect_patterns()
	if pattern_result != MotionType.NONE:
		return pattern_result

	return _analyze_overall_direction()

func _detect_circle() -> MotionType:
	if mouse_trail.size() < circle_segments_required:
		return MotionType.NONE

	var center = _calculate_centroid()
	var angles: Array[float] = []

	# Calculate angles from center
	for point in mouse_trail:
		var angle = center.angle_to_point(point)
		angles.append(angle)

	if angles.size() < circle_segments_required:
		return MotionType.NONE

	# Check for circular motion by analyzing angle progression
	var total_rotation = 0.0
	var consistent_direction = true
	var last_angle = angles[0]

	for i in range(1, angles.size()):
		var angle_diff = _normalize_angle(angles[i] - last_angle)
		total_rotation += angle_diff

		# Check if we maintain consistent direction
		if i > 1 and sign(angle_diff) != sign(total_rotation):
			if abs(angle_diff) > PI / 4: # Allow small direction changes
				consistent_direction = false
				break

		last_angle = angles[i]

	# Determine if it's a complete circle
	if consistent_direction and abs(total_rotation) > PI * 1.5: # At least 3/4 circle
		return MotionType.CIRCLE_CLOCKWISE if total_rotation > 0 else MotionType.CIRCLE_COUNTER_CLOCKWISE

	return MotionType.NONE

func _detect_shapes() -> MotionType:
	if _is_triangle_pattern():
		return MotionType.TRIANGLE

	if _is_square_pattern():
		return MotionType.SQUARE

	return MotionType.NONE

func _detect_patterns() -> MotionType:
	# Zigzag detection
	if _is_zigzag_pattern():
		return MotionType.ZIGZAG

	# Wave detection
	if _is_wave_pattern():
		return MotionType.WAVE

	# Scoop detection
	var scoop_result = _detect_scoop()
	if scoop_result != MotionType.NONE:
		return scoop_result

	# Spiral detection
	if _is_spiral_pattern():
		return MotionType.SPIRAL

	return MotionType.NONE

func _detect_scoop() -> MotionType:
	if mouse_trail.size() < 5:
		return MotionType.NONE

	var start_y = mouse_trail[0].y
	var end_y = mouse_trail[-1].y
	var lowest_y = start_y
	var highest_y = start_y

	for point in mouse_trail:
		lowest_y = min(lowest_y, point.y)
		highest_y = max(highest_y, point.y)

	if start_y > lowest_y and end_y < start_y and (start_y - lowest_y) > 30:
		return MotionType.SCOOP_UP

	if start_y < highest_y and end_y > start_y and (highest_y - start_y) > 30:
		return MotionType.SCOOP_DOWN

	return MotionType.NONE

func _is_triangle_pattern() -> bool:
	if mouse_trail.size() < 6:
		return false

	var corners = _find_corner_points()
	return corners.size() >= 3 and corners.size() <= 4

func _is_square_pattern() -> bool:
	if mouse_trail.size() < 8:
		return false

	var corners = _find_corner_points()
	if corners.size() < 4 or corners.size() > 5:
		return false

	# Check if angles are roughly 90 degrees
	var right_angles = 0
	for i in range(corners.size() - 2):
		var angle = _calculate_corner_angle(corners[i], corners[i + 1], corners[i + 2])
		if abs(angle - PI / 2) < PI / 6: # Within 30 degrees of 90
			right_angles += 1

	return right_angles >= 3


func _is_zigzag_pattern() -> bool:
	if velocity_history.size() < 6:
		return false

	var direction_changes = 0
	var last_direction = sign(velocity_history[0].x)

	for velocity in velocity_history:
		var current_direction = sign(velocity.x)
		if current_direction != last_direction and current_direction != 0:
			direction_changes += 1
			last_direction = current_direction

	return direction_changes >= 3

func _is_wave_pattern() -> bool:
	if mouse_trail.size() < 8:
		return false

	# Look for smooth oscillating Y values with generally horizontal movement
	var y_changes = 0
	var going_up = false
	var last_y = mouse_trail[0].y

	for i in range(1, mouse_trail.size()):
		var current_y = mouse_trail[i].y
		var currently_going_up = current_y < last_y

		if currently_going_up != going_up:
			y_changes += 1
			going_up = currently_going_up

		last_y = current_y

	return y_changes >= 3

func _is_spiral_pattern() -> bool:
	if mouse_trail.size() < 10:
		return false

	var center = _calculate_centroid()
	var distances: Array[float] = []

	for point in mouse_trail:
		distances.append(center.distance_to(point))

	# Check if distance from center generally increases or decreases
	var increasing = 0
	var decreasing = 0

	for i in range(1, distances.size()):
		if distances[i] > distances[i - 1]:
			increasing += 1
		elif distances[i] < distances[i - 1]:
			decreasing += 1

	var total = increasing + decreasing
	return (increasing > total * 0.7) or (decreasing > total * 0.7)

func _analyze_overall_direction() -> MotionType:
	if mouse_trail.size() < 2:
		return MotionType.NONE

	var overall_direction = mouse_trail[-1] - mouse_trail[0]
	return _classify_direction(overall_direction)

func _classify_direction(direction: Vector2) -> MotionType:
	if direction.length() < min_movement_threshold:
		return MotionType.NONE

	var angle = direction.angle()
	var abs_angle = abs(angle)

	# Convert to degrees for easier understanding
	var degrees = rad_to_deg(angle)

	# Classify based on angle ranges
	if abs_angle < PI / 8: # -22.5 to 22.5 degrees
		return MotionType.RIGHT
	elif abs_angle > 7 * PI / 8: # 157.5 to 180 or -157.5 to -180 degrees
		return MotionType.LEFT
	elif angle > 3 * PI / 8 and angle < 5 * PI / 8: # 67.5 to 112.5 degrees
		return MotionType.DOWN
	elif angle < -3 * PI / 8 and angle > -5 * PI / 8: # -67.5 to -112.5 degrees
		return MotionType.UP
	elif angle > PI / 8 and angle < 3 * PI / 8: # 22.5 to 67.5 degrees
		return MotionType.DIAGONAL_DOWN_RIGHT
	elif angle > 5 * PI / 8 and angle < 7 * PI / 8: # 112.5 to 157.5 degrees
		return MotionType.DIAGONAL_DOWN_LEFT
	elif angle < -PI / 8 and angle > -3 * PI / 8: # -22.5 to -67.5 degrees
		return MotionType.DIAGONAL_UP_RIGHT
	elif angle < -5 * PI / 8 and angle > -7 * PI / 8: # -112.5 to -157.5 degrees
		return MotionType.DIAGONAL_UP_LEFT

	return MotionType.NONE

func _get_average_velocity(count: int) -> Vector2:
	var sum = Vector2.ZERO
	var start = max(0, velocity_history.size() - count)

	for i in range(start, velocity_history.size()):
		sum += velocity_history[i]

	return sum / min(count, velocity_history.size())

func _calculate_centroid() -> Vector2:
	var sum = Vector2.ZERO
	for point in mouse_trail:
		sum += point
	return sum / mouse_trail.size()

func _normalize_angle(angle: float) -> float:
	while angle > PI:
		angle -= 2 * PI
	while angle < -PI:
		angle += 2 * PI
	return angle

func _find_corner_points() -> Array[Vector2]:
	var corners: Array[Vector2] = []
	if mouse_trail.size() < 3:
		return corners

	var angle_threshold = PI / 3 # 60 degrees

	for i in range(1, mouse_trail.size() - 1):
		var prev = mouse_trail[i - 1]
		var current = mouse_trail[i]
		var next = mouse_trail[i + 1]

		var angle = _calculate_corner_angle(prev, current, next)
		if angle > angle_threshold:
			corners.append(current)

	return corners

func _calculate_corner_angle(p1: Vector2, p2: Vector2, p3: Vector2) -> float:
	var v1 = (p1 - p2).normalized()
	var v2 = (p3 - p2).normalized()
	return acos(clamp(v1.dot(v2), -1.0, 1.0))

func _calculate_confidence(gesture_type: MotionType) -> float:
	# Basic confidence calculation based on trail consistency
	var base_confidence = 0.5

	# Longer trails generally indicate more intentional gestures
	if mouse_trail.size() > 10:
		base_confidence += 0.2

	# Smooth movements increase confidence
	var smoothness = _calculate_smoothness()
	base_confidence += smoothness * 0.3

	return clamp(base_confidence, 0.0, 1.0)

func _calculate_smoothness() -> float:
	if velocity_history.size() < 3:
		return 0.0

	var total_variance = 0.0
	var avg_velocity = _get_average_velocity(velocity_history.size())

	for velocity in velocity_history:
		total_variance += (velocity - avg_velocity).length_squared()

	var variance = total_variance / velocity_history.size()
	return clamp(1.0 - (variance / 1000.0), 0.0, 1.0)

# Public API
func start_manual_tracking():
	_start_tracking()

func stop_manual_tracking():
	_stop_tracking()

func get_current_trail() -> Array[Vector2]:
	return mouse_trail.duplicate()

func clear_trail():
	mouse_trail.clear()
	velocity_history.clear()

func set_sensitivity(threshold: float):
	min_movement_threshold = threshold

func is_currently_tracking() -> bool:
	return is_tracking
