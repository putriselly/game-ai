class_name BattleEvaluator
extends RefCounted
## EVALUATION FUNCTIONS: estimate how good a non-terminal state is for a side.
## All of them return a value inside (-WIN_SCORE, WIN_SCORE) so terminal
## utilities always dominate.
##
## Personalities are weight sets that scale the components, which lets the
## same evaluation produce aggressive or defensive NPCs.

const EVALUATIONS: Array[String] = ["hp_diff", "hp_ratio", "tactical", "threat"]
const PERSONALITIES: Array[String] = ["balanced", "aggressive", "defensive"]


static func personality(name: String) -> Dictionary:
	match name:
		"aggressive":
			return {"own_hp": 0.4, "enemy_hp": 2.0, "own_status": 0.4, "enemy_status": 2.0}
		"defensive":
			return {"own_hp": 2.0, "enemy_hp": 0.4, "own_status": 2.0, "enemy_status": 0.4}
	return {"own_hp": 1.0, "enemy_hp": 1.0, "own_status": 1.0, "enemy_status": 1.0}


static func evaluate(sim: BattleSim, side: int, eval_name: String, weights: Dictionary = {}) -> float:
	if weights.is_empty():
		weights = personality("balanced")
	match eval_name:
		"hp_diff":
			return eval_hp_diff(sim, side, weights)
		"hp_ratio":
			return eval_hp_ratio(sim, side, weights)
		"tactical":
			return eval_tactical(sim, side, weights)
		"threat":
			return eval_threat(sim, side, weights)
	push_error("Unknown evaluation: " + eval_name)
	return 0.0


## E1: raw hit-point difference. own_hp * my HP - enemy_hp * their HP.
static func eval_hp_diff(sim: BattleSim, side: int, w: Dictionary) -> float:
	var foe := BattleSim.other(side)
	return w["own_hp"] * sim.total_hp(side) - w["enemy_hp"] * sim.total_hp(foe)


## E2: HP as a fraction of the maximum plus a bonus per living unit, so
## killing a unit is worth more than spreading the same damage around.
static func eval_hp_ratio(sim: BattleSim, side: int, w: Dictionary) -> float:
	var foe := BattleSim.other(side)
	var own := float(sim.total_hp(side)) / float(sim.total_max_hp(side))
	var theirs := float(sim.total_hp(foe)) / float(sim.total_max_hp(foe))
	var alive_diff := sim.alive_units(side).size() - sim.alive_units(foe).size()
	return 200.0 * (w["own_hp"] * own - w["enemy_hp"] * theirs) + 30.0 * alive_diff


## E3: hp_ratio plus the tactical situation: shields, burns, stuns, ultimate
## charge and potions in stock, each valued in "HP equivalents".
static func eval_tactical(sim: BattleSim, side: int, w: Dictionary) -> float:
	var score := eval_hp_ratio(sim, side, w)
	var foe := BattleSim.other(side)
	score += 4.0 * (w["own_status"] * sim.potions[side] - w["enemy_status"] * sim.potions[foe])
	for u in sim.units:
		if not u.is_alive():
			continue
		var value := 0.0
		value += 0.8 * u.shield                      # shield ~ HP
		value -= BattleSim.BURN_DAMAGE * u.burn      # burn = HP that will be lost
		value -= 6.0 * u.stun                        # a lost turn
		value += 0.04 * u.ult                        # a full bar is worth ~4 HP
		if u.side == side:
			score += w["own_status"] * value
		else:
			score -= w["enemy_status"] * value
	return score


## E4: tactical plus the THREAT each living unit still poses (see
## [method BattleSim.threat_of]). Removing a dangerous opponent is worth more
## than removing a harmless one, even when both cost the same damage, and
## keeping one's own damage dealers alive is rewarded the same way.
const THREAT_WEIGHT := 3.0

static func eval_threat(sim: BattleSim, side: int, w: Dictionary) -> float:
	var score := eval_tactical(sim, side, w)
	for u in sim.units:
		if not u.is_alive():
			continue
		var t := THREAT_WEIGHT * sim.threat_of(u)
		if u.side == side:
			score += w["own_status"] * t
		else:
			score -= w["enemy_status"] * t
	return score
