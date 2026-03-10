extends CharacterBody3D

@export var walk_speed: float = 6.0
@export var mouse_sensitivity: float = 0.002
@export var gravity: float = 20.0
@export var ship_path: NodePath

var ship: Node3D
var held_interactable: Object = null

@onready var camera: Camera3D = $Camera3D
@onready var interact_ray: RayCast3D = get_node_or_null("Camera3D/InteractRay") as RayCast3D

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	ship = get_node_or_null(ship_path) as Node3D

	if interact_ray != null:
		interact_ray.add_exception(self)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-85), deg_to_rad(85))

	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _physics_process(delta: float) -> void:
	handle_interaction()
	handle_walk_mode(delta)

func handle_walk_mode(delta: float) -> void:
	var input_dir: Vector2 = Vector2.ZERO

	if Input.is_action_pressed("move_forward"):
		input_dir.y += 1.0
	if Input.is_action_pressed("move_back"):
		input_dir.y -= 1.0
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1.0
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1.0

	input_dir = input_dir.normalized()

	var ship_up: Vector3 = Vector3.UP
	if ship != null:
		ship_up = ship.global_transform.basis.y.normalized()

	var forward: Vector3 = -camera.global_transform.basis.z
	var right: Vector3 = camera.global_transform.basis.x

	# Project movement onto the plane of the ship floor
	forward = forward - ship_up * forward.dot(ship_up)
	right = right - ship_up * right.dot(ship_up)

	if forward.length_squared() > 0.0001:
		forward = forward.normalized()
	if right.length_squared() > 0.0001:
		right = right.normalized()

	var move_dir: Vector3 = (right * input_dir.x) + (forward * input_dir.y)

	# Keep velocity aligned to ship-local axes rather than world Y assumptions
	var vertical_speed: float = velocity.dot(ship_up)
	var horizontal_velocity: Vector3 = move_dir * walk_speed

	velocity = horizontal_velocity + ship_up * vertical_speed

	# Artificial gravity toward the ship floor
	var gravity_dir: Vector3 = -ship_up
	velocity += gravity_dir * gravity * delta

	# Tell CharacterBody what "up" means
	up_direction = ship_up

	move_and_slide()

func handle_interaction() -> void:
	if interact_ray == null:
		return

	var interact_pressed: bool = Input.is_action_pressed("interact")

	if interact_pressed:
		var new_interactable: Object = null

		if interact_ray.is_colliding():
			new_interactable = interact_ray.get_collider()

		if held_interactable != null and held_interactable != new_interactable:
			if held_interactable.has_method("release"):
				held_interactable.release()
			held_interactable = null

		if new_interactable != null:
			if held_interactable == null:
				if new_interactable.has_method("press"):
					new_interactable.press()
					held_interactable = new_interactable
	else:
		if held_interactable != null:
			if held_interactable.has_method("release"):
				held_interactable.release()
			held_interactable = null
