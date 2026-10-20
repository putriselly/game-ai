extends Node
## Autoload "Game": glue between the overworld and the battle scene.
##
## Keeps the state that must survive a scene change: the player's party and
## HP, where the player was standing, which encounter triggered the battle and
## which encounters have already been beaten.

const WORLD_SCENE := "res://main.tscn"
const BATTLE_SCENE := "res://battle.tscn"

## Unit ids (see [Roster]) that fight for the player, in formation order.
var player_party: Array[String] = ["ninja", "flame", "knight", "monk"]
## Current HP per party unit id; missing entry = full HP.
var party_hp: Dictionary = {}

var pending_enemy_party: Array[String] = []
var pending_encounter_id: String = ""
var defeated_encounters: Dictionary = {}  # encounter id -> true

## Search settings for the NPC. Edited live from the battle debug overlay
## (F1) and kept between battles.
var ai_config: Dictionary = {
	"algorithm": MinimaxAI.Algorithm.ALPHABETA,
	"depth": 4,
	"eval": "tactical",
	"personality": "balanced",
	"ordering": MinimaxAI.Ordering.HEURISTIC,
	"node_limit": 0,
	"hit_chance": 1.0,
	"ultimate_mode": BattleSim.UltimateMode.AUTO,
	"full_targeting": false,
	"target_rule": BattleSim.TargetRule.PER_UNIT,
}

var saved_player_position: Vector2 = Vector2.ZERO
var has_saved_position: bool = false
var last_battle_won: bool = false


func start_battle(encounter_id: String, enemy_party: Array[String], player_position: Vector2) -> void:
	pending_encounter_id = encounter_id
	pending_enemy_party = enemy_party.duplicate()
	saved_player_position = player_position
	has_saved_position = true
	get_tree().call_deferred("change_scene_to_file", BATTLE_SCENE)


## Called by the battle scene when it is over.
## [param surviving_hp] maps unit id -> hp so wounds carry over between fights.
func end_battle(victory: bool, surviving_hp: Dictionary) -> void:
	last_battle_won = victory
	if victory:
		defeated_encounters[pending_encounter_id] = true
		party_hp = surviving_hp
	else:
		# Defeat: the party respawns at full health and the encounter stays.
		party_hp.clear()
	pending_encounter_id = ""
	pending_enemy_party.clear()
	get_tree().call_deferred("change_scene_to_file", WORLD_SCENE)


func is_defeated(encounter_id: String) -> bool:
	return defeated_encounters.has(encounter_id)
