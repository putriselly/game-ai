class_name CharacterSprite
extends Sprite2D
## Frame-based animator for the Ninja Adventure sprite sheets.
##
## Point it at an actor folder (e.g. [code]res://assets/Actor/Character/Knight[/code])
## and it figures out which sheets exist:
## [br]- Characters have a [code]SeparateAnim[/code] folder with Idle / Walk /
##   Attack / Dead sheets.
## [br]- Monsters only have a 4x4 [code]SpriteSheet.png[/code] (walk cycle).
## [br]In every sheet the column is the facing direction (down, up, left, right)
## and the row is the frame of the animation.

signal animation_finished(anim: StringName)

enum Dir { DOWN = 0, UP = 1, LEFT = 2, RIGHT = 3 }

const ANIM_IDLE := &"idle"
const ANIM_WALK := &"walk"
const ANIM_ATTACK := &"attack"
const ANIM_DEAD := &"dead"

## Folder holding the sheets for this actor.
@export_dir var sprite_folder: String = "res://assets/Actor/Character/NinjaGreen":
	set(value):
		sprite_folder = value
		if is_inside_tree():
			_load_sheets()

@export var frames_per_second: float = 8.0

var direction: Dir = Dir.DOWN:
	set(value):
		direction = value
		_apply_frame()

var current_animation: StringName = ANIM_IDLE
var _frame_index: int = 0
var _time: float = 0.0
var _sheets: Dictionary = {}  # anim -> {texture, hframes, vframes, loop, directional}


func _ready() -> void:
	centered = true
	_load_sheets()
	play(ANIM_IDLE)


func _load_sheets() -> void:
	_sheets.clear()
	var sep := sprite_folder.path_join("SeparateAnim")
	if ResourceLoader.exists(sep.path_join("Walk.png")):
		_add_sheet(ANIM_WALK, sep.path_join("Walk.png"), true, true)
		if ResourceLoader.exists(sep.path_join("Idle.png")):
			_add_sheet(ANIM_IDLE, sep.path_join("Idle.png"), true, true)
		else:
			# Some characters (NinjaFire, NinjaThunder) ship without Idle.png.
			_sheets[ANIM_IDLE] = _sheets[ANIM_WALK].duplicate()
			_sheets[ANIM_IDLE]["single_frame"] = true
		_add_sheet(ANIM_ATTACK, sep.path_join("Attack.png"), false, true)
		_add_sheet(ANIM_DEAD, sep.path_join("Dead.png"), false, false)
	else:
		# Monster: one 4x4 sheet, columns = direction, rows = walk frames.
		var sheet := sprite_folder.path_join("SpriteSheet.png")
		_add_sheet(ANIM_WALK, sheet, true, true)
		_sheets[ANIM_IDLE] = _sheets[ANIM_WALK].duplicate()
		_sheets[ANIM_IDLE]["single_frame"] = true
		# No dedicated attack / death frames: reuse the walk sheet, the
		# character code adds a lunge tween / fade so it still reads well.
		_sheets[ANIM_ATTACK] = _sheets[ANIM_WALK].duplicate()
		_sheets[ANIM_ATTACK]["loop"] = false
		_sheets[ANIM_DEAD] = _sheets[ANIM_IDLE].duplicate()
	_apply_frame()


func _add_sheet(anim: StringName, path: String, loop: bool, directional: bool) -> void:
	if not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	var cols := maxi(1, int(tex.get_width() / 16))
	var rows := maxi(1, int(tex.get_height() / 16))
	_sheets[anim] = {
		"texture": tex, "hframes": cols, "vframes": rows,
		"loop": loop, "directional": directional and cols >= 4, "single_frame": false,
	}


## Starts an animation. Looping animations restart only if they are not
## already playing, so calling play(walk) every frame is fine.
func play(anim: StringName) -> void:
	if not _sheets.has(anim):
		anim = ANIM_IDLE
	if anim == current_animation and _sheets[anim]["loop"]:
		return
	current_animation = anim
	_frame_index = 0
	_time = 0.0
	_apply_frame()


func face(dir_vector: Vector2) -> void:
	if dir_vector == Vector2.ZERO:
		return
	if absf(dir_vector.x) > absf(dir_vector.y):
		direction = Dir.RIGHT if dir_vector.x > 0 else Dir.LEFT
	else:
		direction = Dir.DOWN if dir_vector.y > 0 else Dir.UP


func _process(delta: float) -> void:
	if not _sheets.has(current_animation):
		return
	var sheet: Dictionary = _sheets[current_animation]
	var frame_count: int = 1 if sheet["single_frame"] else sheet["vframes"]
	if not sheet["directional"]:
		frame_count = sheet["hframes"] * sheet["vframes"]
	if frame_count <= 1:
		return
	_time += delta
	var step := 1.0 / frames_per_second
	while _time >= step:
		_time -= step
		_frame_index += 1
		if _frame_index >= frame_count:
			if sheet["loop"]:
				_frame_index = 0
			else:
				_frame_index = frame_count - 1
				animation_finished.emit(current_animation)
		_apply_frame()


func _apply_frame() -> void:
	if not _sheets.has(current_animation):
		return
	var sheet: Dictionary = _sheets[current_animation]
	texture = sheet["texture"]
	hframes = sheet["hframes"]
	vframes = sheet["vframes"]
	if sheet["directional"]:
		var row := 0 if sheet["single_frame"] else _frame_index
		frame = row * hframes + int(direction)
	else:
		frame = _frame_index
