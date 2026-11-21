class_name Roster
extends RefCounted
## Every character in the game, built from the design document.
## Use [method get_unit] with an id like "ninja" or "evil_bamboo".

## Balance note: heroes deal ~10 per action, enemies 3-7, and only one unit
## acts per turn, so enemies carry the bigger HP pool to make fights even.
## Preferred targets (PER_UNIT rule): Bamboo and Bomber finish the weakest,
## Bear and Thunder Mage hunt the most dangerous hero, Fire Mage burns the
## toughest one so the burn has time to pay off.
const CHAR := "res://assets/Actor/Character/"
const MONSTER := "res://assets/Actor/Monster/"
const BOSS := "res://assets/Actor/Boss/"

const TM := SkillData.TargetMode

# Pembagian elemen untuk setiap karakter
const ELEMENT_BY_ID = {
	"ninja": "Wind",
	"flame": "Fire",
	"knight": "Water",
	"monk": "Water",

	"evil_bamboo": "Wind",
	"bear": "Electric",
	"bomber": "Fire",
	"evil_fire_mage": "Fire",
	"evil_thunder_mage": "Electric",

	"giant_bamboo": "Wind"
}

static func get_unit(id: String) -> UnitData:
	match id:
		# ---------------- Player team ----------------
		"ninja":
			return _unit("ninja", "Ninja", 22, CHAR + "NinjaGreen", [
				_skill({"id": "kunai_strike", "display_name": "Kunai Strike",
					"description": "Deal 10 damage to one enemy.",
					"target_mode": TM.ENEMY, "power": 10}),
				_skill({"id": "shuriken_storm", "display_name": "Shuriken Storm",
					"description": "Deal 5 damage to every enemy.",
					"target_mode": TM.ALL_ENEMIES, "power": 5, "is_ultimate": true}),
			])
		"flame":
			return _unit("flame", "Flame", 20, CHAR + "Flam", [
				_skill({"id": "scorch", "display_name": "Scorch",
					"description": "Deal 5 damage and burn the enemy for 2 turns (does not stack).",
					"target_mode": TM.ENEMY, "power": 5, "burn_turns": 2}),
				_skill({"id": "explode", "display_name": "Explode",
					"description": "Deal 15 damage to a burning enemy, or 7 damage otherwise.",
					"target_mode": TM.ENEMY, "power": 7, "power_if_target_burning": 15,
					"is_ultimate": true}),
			])
		"knight":
			return _unit("knight", "Knight", 32, CHAR + "Knight", [
				_skill({"id": "bump", "display_name": "Bump",
					"description": "Deal 3 damage. If Knight is below 50% HP, the target is also stunned for 1 turn.",
					"target_mode": TM.ENEMY, "power": 3, "stun_turns": 1,
					"stun_only_if_user_hp_below": 0.5}),
				_skill({"id": "guard", "display_name": "Guard",
					"description": "Give 10 shield to one ally.",
					"target_mode": TM.ALLY, "shield": 10, "is_ultimate": true}),
			])
		"monk":
			return _unit("monk", "Monk", 20, CHAR + "Monk", [
				_skill({"id": "heal", "display_name": "Heal",
					"description": "Restore 5 HP to one ally.",
					"target_mode": TM.ALLY, "heal": 5}),
				_skill({"id": "blessing", "display_name": "Blessing",
					"description": "Restore 10 HP to every ally.",
					"target_mode": TM.ALL_ALLIES, "heal": 10, "is_ultimate": true}),
			])
		# ---------------- Enemies ----------------
		"evil_bamboo":
			return _unit("evil_bamboo", "Evil Bamboo", 45, MONSTER + "Bamboo", [
				_skill({"id": "bamboo_bump", "display_name": "Bump",
					"description": "Deal 3 damage to the target.",
					"target_mode": TM.ENEMY, "power": 3}),
				_skill({"id": "harder_bump", "display_name": "Harder Bump",
					"description": "Deal 7 damage to the target.",
					"target_mode": TM.ENEMY, "power": 7, "is_ultimate": true}),
			])
		"bear":
			return _unit("bear", "Bear", 60, MONSTER + "Bear", [
				_skill({"id": "bite", "display_name": "Bite",
					"description": "Deal 5 damage to the target.",
					"target_mode": TM.ENEMY, "power": 5}),
				_skill({"id": "body_slam", "display_name": "Body Slam",
					"description": "Deal 3 damage and stun the target for 1 turn.",
					"target_mode": TM.ENEMY, "power": 3, "stun_turns": 1, "is_ultimate": true}),
			], BattleSim.TargetRule.THREAT)
		"bomber":
			return _unit("bomber", "Bomber", 40, CHAR + "NinjaBomb", [
				_skill({"id": "bomb", "display_name": "Bomb",
					"description": "Deal 3 damage to every opponent.",
					"target_mode": TM.ALL_ENEMIES, "power": 3}),
				_skill({"id": "detonate", "display_name": "Detonate",
					"description": "Throw a huge bomb at the target for 15 damage.",
					"target_mode": TM.ENEMY, "power": 15, "is_ultimate": true}),
			])
		"evil_fire_mage":
			return _unit("evil_fire_mage", "Evil Fire Mage", 45, CHAR + "SorcererOrange", [
				_skill({"id": "burn", "display_name": "Burn",
					"description": "Deal 7 damage to the target.",
					"target_mode": TM.ENEMY, "power": 7}),
				_skill({"id": "light_up", "display_name": "Light Up",
					"description": "Deal 15 damage and burn the target for 3 turns.",
					"target_mode": TM.ENEMY, "power": 15, "burn_turns": 3, "is_ultimate": true}),
			], BattleSim.TargetRule.TOUGHEST)
		"evil_thunder_mage":
			return _unit("evil_thunder_mage", "Evil Thunder Mage", 45, CHAR + "NinjaThunder", [
				_skill({"id": "thunder_shock", "display_name": "Thunder Shock",
					"description": "Deal 3 damage to every opponent.",
					"target_mode": TM.ALL_ENEMIES, "power": 3}),
				_skill({"id": "thunderstorm", "display_name": "Thunderstorm",
					"description": "Deal 10 damage and stun the target for 2 turns.",
					"target_mode": TM.ENEMY, "power": 10, "stun_turns": 2, "is_ultimate": true}),
			], BattleSim.TargetRule.THREAT)
		# ---------------- Boss ----------------
		# Skills carry PRECONDITIONS and EFFECTS (flags), so the boss has to
		# chain actions: Sap Surge -> Bamboo Spear / Thorn Storm. This is the
		# structure the automated planner (Tahap 4) reasons about.
		"giant_bamboo":
			var boss := _unit("giant_bamboo", "Giant Bamboo", 120, BOSS + "GiantBamboo", [
				_skill({"id": "root_slam", "display_name": "Root Slam",
					"description": "Deal 6 damage to the target.",
					"target_mode": TM.ENEMY, "power": 6}),
				_skill({"id": "sap_surge", "display_name": "Sap Surge",
					"description": "Become enraged: the next Bamboo Spear or Thorn Storm is empowered.",
					"target_mode": TM.SELF, "grants": ["enraged"], "forbids": ["enraged"]}),
				_skill({"id": "bamboo_spear", "display_name": "Bamboo Spear",
					"description": "Deal 10 damage, or 24 while enraged (ends the rage).",
					"target_mode": TM.ENEMY, "power": 10, "power_if_user_enraged": 24,
					"consumes": ["enraged"]}),
				_skill({"id": "thorn_storm", "display_name": "Thorn Storm",
					"description": "Phase 2, while enraged: deal 6 damage and burn every hero for 2 turns (ends the rage).",
					"target_mode": TM.ALL_ENEMIES, "power": 6, "burn_turns": 2,
					"requires": ["enraged", "phase2"], "consumes": ["enraged"]}),
				_skill({"id": "harden_bark", "display_name": "Harden Bark",
					"description": "Gain 15 shield (only while unshielded).",
					"target_mode": TM.SELF, "shield": 15, "forbids": ["shielded"]}),
				_skill({"id": "regrow", "display_name": "Regrow",
					"description": "Below 50% HP, once per battle: restore 25 HP (uses a potion).",
					"target_mode": TM.SELF, "heal": 25, "once_per_battle": true,
					"only_if_user_hp_below": 0.5}),
				_skill({"id": "bamboo_fury", "display_name": "Bamboo Fury",
					"description": "Ultimate: deal 8 damage to every hero.",
					"target_mode": TM.ALL_ENEMIES, "power": 8, "is_ultimate": true}),
			], BattleSim.TargetRule.THREAT)
			boss.is_boss = true
			return boss
	push_error("Roster: unknown unit id '%s'" % id)
	return null


static func all_ids() -> Array[String]:
	return ["ninja", "flame", "knight", "monk",
		"evil_bamboo", "bear", "bomber", "evil_fire_mage", "evil_thunder_mage",
		"giant_bamboo"]


static func _unit(id: String, display_name: String, max_hp: int, folder: String,
		skills: Array[SkillData], preferred_target := BattleSim.TargetRule.WEAKEST) -> UnitData:
	var u := UnitData.new()
	u.id = id
	u.display_name = display_name
	u.element = str(ELEMENT_BY_ID.get(id, ""))
	print("Unit: ", u.display_name, " | Element: ", u.element)
	u.max_hp = max_hp
	u.sprite_folder = folder
	u.skills = skills
	u.preferred_target = preferred_target
	return u


static func _skill(values: Dictionary) -> SkillData:
	return SkillData.make(values)
