#!/usr/bin/env python3
"""Economy simulator and gym tuner (factory agent 2).

Usage:
    python factory/tools/simulate_economy.py <game-dir>/config <game-dir>/tuning
                                             [--players N] [--seed S]
                                             [--proposal FILE] [--max-hours H]

Reads <config>/*.json only. Writes <out>/gyms.json and <out>/report.md.
If <out>/proposal.json exists (or --proposal is given) the proposed numbers
are applied in memory and simulated too. Config files are never changed.
Standard library only. Same seed, same output.
"""
import argparse
import copy
import json
import os
import random
import sys

# Numbers the spec does not define. Each one is listed in the report.
SIM = {
    "leader_speed": None,          # None = midpoint of speed_min and speed_max
    "leader_special": "smash",
    "tune_target_win_rate": 0.80,
    "tune_battles": 1500,
    "measure_battles": 3000,
    "click_rates": [4, 2, 8],      # first one is the main run
    "hatch_seconds": 3,            # no clicking while an egg hatches
    "turn_seconds": 6,             # no clicking during a battle
    "payback_seconds": 300,        # buy an egg if it pays itself back in this time
    "losses_before_stuck": 3,
    "train_hatch_cap": 25,
    "heal_below_hp": 0.6,
    "max_turns": 300,
}

ASSUMPTIONS = [
    "Leader tuning first calibrates the reference team to the baseline win-rate target, then multiplies that power by the spec's cohort_power_factor (default 1). Reported reference win rates measure the final adjusted leaders, not the baseline. Cohort pacing and rebirth targets remain unchanged.",
    "Leader pets: base HP and Attack of the world's most expensive egg, times the strength rarity battle multiplier, times the tuned power. HP and Attack are rounded.",
    "Leader pets have Speed {leader_speed} (midpoint of speed_min and speed_max) and the Smash special. All pets of a leader team are identical. Leaders get no rebirth or variant bonus.",
    "Every special is ready on turn 1. After use it is locked for special_cooldown_turns turns, so it comes back on the third turn after.",
    "Turn order is fixed at the start of a turn from current Speed. A pet that faints before acting loses its action. The replacement acts from the next turn. Cooldowns only tick for the active pet.",
    "Guard halves the next hit taken, whenever it comes. Rush can stack if used again, but the player policy uses it once.",
    "Drain heals from damage dealt, capped at max HP. Heal is capped at max HP.",
    "Off-type uses the listed type for the type bonus. Same type against same type is neutral (1.0).",
    "Player battle policy: use an attack special (Smash, Drain) when ready. Use Off-type when it beats the basic move after type bonus. Use Heal when ready and HP is under {heal_pct}%. Use Guard on the turn before the leader's Smash lands. Use Rush once, only when slower than the active leader pet. Otherwise basic attack. Team order is strongest matchup first.",
    "Reference team: the 3 distinct Rare pets hatchable by that world with the best matchup score (HP x Attack x own type bonus / leader type bonus). If fewer than 3 distinct Rare pets exist, copies of the best one fill the team. No variants.",
    "Clicks are continuous: coins arrive at clicks per second x coins per click. The index bonus multiplies coins per click: x (1 + index_egg_bonus x completed eggs). An egg is complete when all 5 normal pets were hatched. World/full normal collection factors are included when configured. The index survives rebirth. Optional wild focus wins, their coin rewards/temporary boosts and captures are excluded: this is a passive-training baseline, not a forecast for active minigame players.",
    "Shiny and Golden are exclusive rolls on each hatch. Their click and battle multipliers apply on top of rarity and role.",
    "Hatching takes {hatch_seconds} s and a battle takes {turn_seconds} s per turn. Legacy clicking pauses during both. Configured training with no hatch pause continues earning during the reveal, using the equipped team before that hatch, and excludes hatch opportunity cost from purchase decisions. Battles still pause income. Gym retry waits earn normally.",
    "No game passes. Inventory retains up to team_size copies of each pet/variant (extra identical copies cannot improve a team). Inventory-relative power floors are retired (zero in current config); all pet powers are fixed by pet and variant. Farm teams reselect the best effective coin pets after hatches. Battle training still uses a greedy replacement policy.",
    "Greedy player policy, farm mode: buy the unlocked egg with the best expected click gain per coin, as long as the expected gain pays back the price plus the coins lost while hatching within {payback_seconds} s, or within the time it would take to save the gym fee if that is longer. A hatch replaces the lowest Click Power pet if it is better.",
    "Greedy player policy, gym: when no egg is worth buying, save for the gym fee, pay it, and fight. After {losses_before_stuck} losses in a row the player is stuck.",
    "Greedy player policy, stuck: rebirth if affordable. Otherwise buy the egg with the best expected battle gain per coin and replace the weakest battler. Each team change gives {losses_before_stuck} more gym tries. After {train_hatch_cap} such hatches in one stuck spell, or if that egg costs as much as the rebirth, save for the rebirth instead. Players only rebirth when stuck.",
    "Rebirth k costs rebirth_first_cost x rebirth_cost_growth^(k-1). It resets coins, gym progress and paid fees. Pets and the index stay. Eggs of locked worlds cannot be bought.",
    "Target check for 'rebirths at gym' uses the median player. Pacing checks use the median at {main_cps} clicks per second.",
]


# ---------------------------------------------------------------- loading

def load_config(cfg_dir):
    names = ["constants", "rarities", "roles", "variants", "types", "specials", "eggs", "worlds", "pets"]
    cfg = {}
    for n in names:
        with open(os.path.join(cfg_dir, n + ".json"), encoding="utf-8") as f:
            cfg[n] = json.load(f)
    return cfg


def apply_proposal(cfg, prop):
    """Return a changed copy of cfg. prop keys: constants, eggs, worlds."""
    c = copy.deepcopy(cfg)
    for k, v in prop.get("constants", {}).items():
        c["constants"][k] = v
    for egg in c["eggs"]:
        for k, v in prop.get("eggs", {}).get(egg["id"], {}).items():
            egg[k] = v
    for w in c["worlds"]:
        for k, v in prop.get("worlds", {}).get(w["id"], {}).items():
            w["gym"][k] = v
    return c


def diff_rows(cfg, new):
    rows = []
    for k, v in new["constants"].items():
        if cfg["constants"].get(k) != v:
            rows.append(("Constants: " + k, cfg["constants"].get(k), v))
    for a, b in zip(cfg["eggs"], new["eggs"]):
        for k in a:
            if a[k] != b[k]:
                rows.append(("%s: %s" % (a["name"], k), a[k], b[k]))
    for a, b in zip(cfg["worlds"], new["worlds"]):
        for k in a["gym"]:
            if a["gym"][k] != b["gym"][k]:
                rows.append(("%s gym: %s" % (a["name"], k), a["gym"][k], b["gym"][k]))
    return rows


class Game:
    """Config turned into lookup tables. Pet stats are recomputed from egg base stats."""

    def __init__(self, cfg):
        self.C = cfg["constants"]
        self.cfg = cfg
        rar = {r["id"]: r for r in cfg["rarities"]}
        rol = {r["id"]: r for r in cfg["roles"]}
        self.rar = rar
        self.eggs = {e["id"]: e for e in cfg["eggs"]}
        self.types = {t["id"]: t for t in cfg["types"]}
        self.specials = {s["id"]: s for s in cfg["specials"]}
        self.worlds = sorted(cfg["worlds"], key=lambda w: w["index"])
        self.world_index = {w["id"]: i for i, w in enumerate(self.worlds)}
        self.pets = {}
        for p in cfg["pets"]:
            e, r, ro = self.eggs[p["egg"]], rar[p["rarity"]], rol[p["role"]]
            q = dict(p)
            q["click_power"] = e["base_click_power"] * r["click_mult"] * ro["click_mult"]
            q["hp"] = round(e["base_hp"] * r["battle_mult"] * ro["battle_mult"])
            q["attack"] = round(e["base_attack"] * r["battle_mult"] * ro["battle_mult"])
            self.pets[p["id"]] = q
        self.variants = [("normal", 1.0, 1.0, None)]
        for v in cfg["variants"]:
            self.variants.append((v["id"], v["click_mult"], v["battle_mult"], v["hatch_chance"]))
        self.leader_speed = SIM["leader_speed"] or round((self.C["speed_min"] + self.C["speed_max"]) / 2)
        # hatch outcomes per egg: list of (probability, instance)
        self.outcomes = {}
        vp = [(v[0], v[1], v[2], v[3]) for v in self.variants[1:]]
        p_normal = 1.0 - sum(v[3] for v in vp)
        for eid in self.eggs:
            out = []
            for p in self.pets.values():
                if p["egg"] != eid:
                    continue
                pr = rar[p["rarity"]]["hatch_chance"]
                out.append((pr * p_normal, self.instance(p["id"], 0)))
                for i, v in enumerate(vp):
                    out.append((pr * v[3], self.instance(p["id"], i + 1)))
            self.outcomes[eid] = out

    def instance(self, pet_id, variant_i):
        p = self.pets[pet_id]
        v = self.variants[variant_i]
        return {"pet": pet_id, "variant": v[0], "click": p["click_power"] * v[1],
                "hp": p["hp"] * v[2], "attack": p["attack"] * v[2], "speed": p["speed"],
                "type": p["type"], "special": p["special"], "off": p.get("special_off_type")}

    def bonus(self, move_type, target_type):
        t = self.types[move_type]
        if t["strong_against"] == target_type:
            return self.C["type_bonus_strong"]
        if t["weak_against"] == target_type:
            return self.C["type_bonus_weak"]
        return 1.0

    def matchup(self, inst, leader_type):
        return inst["hp"] * inst["attack"] * self.bonus(inst["type"], leader_type) / self.bonus(leader_type, inst["type"])

    def rebirth_cost(self, done):
        return self.C["rebirth_first_cost"] * self.C["rebirth_cost_growth"] ** done

    def leader_team(self, world, power):
        g = world["gym"]
        egg = max((self.eggs[e] for e in world["eggs"]), key=lambda e: e["price"])
        m = self.rar[g["leader_strength"]]["battle_mult"] * power
        pet = {"pet": "leader", "variant": "normal", "click": 0, "hp": round(egg["base_hp"] * m),
               "attack": round(egg["base_attack"] * m), "speed": self.leader_speed,
               "type": g["leader_type"], "special": SIM["leader_special"], "off": None}
        return [pet] * g["leader_count"], egg["id"]

    def reference_team(self, world):
        wi = self.world_index[world["id"]]
        lt = world["gym"]["leader_type"]
        rares = [self.instance(p["id"], 0) for p in self.pets.values()
                 if p["rarity"] == "rare" and self.world_index[p["world"]] <= wi]
        rares.sort(key=lambda i: -self.matchup(i, lt))
        team = rares[:self.C["team_size"]]
        while len(team) < self.C["team_size"]:
            team.append(rares[0])
        team.sort(key=lambda i: -self.matchup(i, lt))
        return team


# ---------------------------------------------------------------- battle

class Fighter:
    __slots__ = ("hp", "maxhp", "atk", "spd", "type", "kind", "power", "value", "off", "cd", "guard", "rushed")

    def __init__(self, game, inst, mult):
        s = game.specials[inst["special"]]
        self.hp = self.maxhp = inst["hp"] * mult
        self.atk = inst["attack"] * mult
        self.spd = inst["speed"]
        self.type = inst["type"]
        self.kind, self.power, self.value = s["kind"], s["power"], s["value"]
        self.off = inst["off"]
        self.cd = 0
        self.guard = None
        self.rushed = False


def player_wants_special(game, p, l, heal_below):
    if p.cd > 0:
        return False
    k = p.kind
    if k in ("attack", "drain"):
        return True
    if k == "offtype":
        return p.power * game.bonus(p.off, l.type) > game.C["basic_move_power"] * game.bonus(p.type, l.type)
    if k == "heal":
        return p.hp < heal_below * p.maxhp
    if k == "guard":
        if p.guard is not None:
            return False
        return l.cd == 0 if p.spd >= l.spd else l.cd == 1
    if k == "speed":
        return (not p.rushed) and p.spd < l.spd
    return False


def act(game, rng, a, d, special):
    """One action. Returns True if the special was used."""
    C = game.C
    if special:
        k = a.kind
        if k == "heal":
            a.hp = min(a.maxhp, a.hp + a.value * a.maxhp)
            return True
        if k == "guard":
            a.guard = a.value
            return True
        if k == "speed":
            a.spd = a.spd * (1 + a.value)
            a.rushed = True
            return True
        power = a.power
        mtype = a.off if k == "offtype" else a.type
    else:
        power, mtype = C["basic_move_power"], a.type
    dmg = a.atk * power / C["basic_move_power"] * game.bonus(mtype, d.type) \
        * rng.uniform(C["damage_random_min"], C["damage_random_max"])
    if d.guard is not None:
        dmg *= d.guard
        d.guard = None
    d.hp -= dmg
    if special and a.kind == "drain":
        a.hp = min(a.maxhp, a.hp + a.value * dmg)
    return special


def battle(game, rng, team, leaders, rebirths):
    """Returns (player_won, turns)."""
    mult = 1 + game.C["rebirth_battle_bonus"] * rebirths
    P = [Fighter(game, i, mult) for i in team]
    L = [Fighter(game, i, 1.0) for i in leaders]
    cdn = game.C["special_cooldown_turns"]
    pi = li = turns = 0
    hb = SIM["heal_below_hp"]
    while pi < len(P) and li < len(L) and turns < SIM["max_turns"]:
        turns += 1
        p, l = P[pi], L[li]
        ps = player_wants_special(game, p, l, hb)
        ls = l.cd == 0
        if p.spd >= l.spd:
            pu = act(game, rng, p, l, ps)
            lu = act(game, rng, l, p, ls) if l.hp > 0 else None
        else:
            lu = act(game, rng, l, p, ls)
            pu = act(game, rng, p, l, ps) if p.hp > 0 else None
        if pu:
            p.cd = cdn
        elif p.cd > 0:
            p.cd -= 1
        if lu:
            l.cd = cdn
        elif l.cd > 0:
            l.cd -= 1
        if p.hp <= 0:
            pi += 1
        if l.hp <= 0:
            li += 1
    return (li >= len(L) and pi < len(P)), turns


def win_rate(game, team, leaders, rebirths, n, seed):
    rng = random.Random(seed)
    return sum(battle(game, rng, team, leaders, rebirths)[0] for _ in range(n)) / n


def tune_gyms(game, seed):
    """Calibrate reference power, then apply the spec's cohort margin."""
    out = []
    for wi, w in enumerate(game.worlds):
        g = w["gym"]
        factor = g.get("cohort_power_factor", 1)
        if type(factor) not in (int, float) or not 0 < factor <= 1:
            raise ValueError("cohort_power_factor must be finite and in (0, 1]")
        ref = game.reference_team(w)
        lo, hi = 0.02, 50.0
        for _ in range(26):
            mid = (lo * hi) ** 0.5
            leaders, _ = game.leader_team(w, mid)
            if win_rate(game, ref, leaders, g["target_rebirths"], SIM["tune_battles"], seed + wi) >= SIM["tune_target_win_rate"]:
                lo = mid
            else:
                hi = mid
        reference_power = round(lo, 3)
        power = round(reference_power * factor, 3)
        leaders, egg_id = game.leader_team(w, power)
        rates = {}
        for r in range(0, g["target_rebirths"] + 3):
            rates[str(r)] = round(win_rate(game, ref, leaders, r, SIM["measure_battles"], seed + 1000 + wi * 50 + r), 3)
        out.append({
            "world": w["id"], "world_name": w["name"], "fee": g["fee"],
            "target_rebirths": g["target_rebirths"], "power": power,
            "reference_power": reference_power, "cohort_power_factor": factor,
            "leader_base_egg": egg_id, "leader_strength": g["leader_strength"],
            "leader_team": [{"type": l["type"], "hp": l["hp"], "attack": l["attack"], "speed": l["speed"],
                             "special": l["special"]} for l in leaders],
            "reference_team": [{"pet": i["pet"], "type": i["type"], "hp": i["hp"], "attack": i["attack"],
                                "speed": i["speed"], "special": i["special"]} for i in ref],
            "reference_win_rate_at_target": rates[str(g["target_rebirths"])],
            "reference_win_rate_by_rebirths": rates,
        })
    return out


# ---------------------------------------------------------------- progression

def simulate_player(game, gyms, cps, rng, max_seconds, reuse_calculations=True):
    C = game.C
    nw = len(game.worlds)
    leaders = [game.leader_team(w, gyms[i]["power"])[0] for i, w in enumerate(game.worlds)]
    size = C["team_size"]
    t = 0.0
    coins = 0.0
    team = []
    r = 0
    beaten = 0
    fee_paid = False
    losses = 0
    train = False
    train_hatches = 0
    seen = {e: set() for e in game.eggs}
    done_eggs = 0
    owned = {}
    legacy_anchor = 0.0
    farm_gain_cache = {}
    farm_team_valid = False
    res = {"first_hatch": None, "gym": [None] * nw, "gym_rebirths": [None] * nw, "rebirths": [], "hatches": 0, "battles": 0}

    def effective_click(inst):
        rarity = game.pets[inst["pet"]]["rarity"]
        floor = C.get("legacy_" + rarity + "_floor", 0)
        return max(inst["click"], legacy_anchor * floor)

    def rate():
        completed_worlds = sum(all(len(seen[eid]) == C["pets_per_egg"] for eid in w["eggs"]) for w in game.worlds)
        full = done_eggs == len(game.eggs)
        extra = 1 + completed_worlds * C.get("index_world_bonus", 0) + (C.get("index_full_bonus", 0) if full else 0)
        return (1 + sum(effective_click(i) for i in team)) * (1 + C["rebirth_coin_bonus"] * r) * (1 + C["index_egg_bonus"] * done_eggs) * extra * cps

    def roll(egg_id):
        x = rng.random()
        acc = 0.0
        out = game.outcomes[egg_id]
        for pr, inst in out:
            acc += pr
            if x < acc:
                return inst
        return out[-1][1]

    def choose(key):
        """Egg with the best expected gain per coin for the given score."""
        if len(team) < size:
            floor = 0.0
        else:
            floor = min(key(i) for i in team)
        best = None
        for w in game.worlds[:min(beaten, nw - 1) + 1]:
            for eid in w["eggs"]:
                gain = sum(pr * max(0.0, key(inst) - floor) for pr, inst in game.outcomes[eid])
                price = game.eggs[eid]["price"]
                if gain > 0 and (best is None or gain / price > best[1] / best[2]):
                    best = (eid, gain, price)
        return best

    def choose_farm():
        """Best gain per coin among eggs that pay back in time."""
        floor = 0.0 if len(team) < size else min(effective_click(i) for i in team)
        income = rate()
        mult = income / (1 + sum(effective_click(i) for i in team))
        horizon = SIM["payback_seconds"]
        if not fee_paid:
            horizon = max(horizon, (game.worlds[beaten]["gym"]["fee"] - coins) / income)
        best = None
        for w in game.worlds[:min(beaten, nw - 1) + 1]:
            for eid in w["eggs"]:
                cache_key = (eid, floor, legacy_anchor)
                gain = farm_gain_cache.get(cache_key) if reuse_calculations else None
                if gain is None:
                    gain = sum(pr * max(0.0, effective_click(inst) - floor) for pr, inst in game.outcomes[eid])
                    if reuse_calculations:
                        farm_gain_cache[cache_key] = gain
                # Legacy clicking stops during the reveal; training keeps earning.
                price = game.eggs[eid]["price"] + (0 if training_during_hatch(game) else income * SIM["hatch_seconds"])
                if gain * mult * horizon >= price and (best is None or gain / price > best[1] / best[2]):
                    best = (eid, gain, price)
        return best

    while t < max_seconds:
        lt = game.worlds[beaten]["gym"]["leader_type"]
        stuck = train and losses >= SIM["losses_before_stuck"]
        pick = None
        key = None
        if not train:
            # A player who can pay the fee goes and fights; they do not keep
            # hatching until no egg pays back any more.
            if fee_paid or coins < game.worlds[beaten]["gym"]["fee"]:
                pick = choose_farm()
            key = effective_click
        elif stuck:
            cost = game.rebirth_cost(r)
            if coins < cost and train_hatches < SIM["train_hatch_cap"]:
                key = lambda i: game.matchup(i, lt)
                pick = choose(key)
                if pick is not None and pick[2] >= cost:
                    pick = None
            if pick is None:
                if coins < cost:
                    t += (cost - coins) / rate()
                    if t >= max_seconds:
                        break
                r += 1
                res["rebirths"].append(t)
                coins, beaten, fee_paid, losses, train = 0.0, 0, False, 0, False
                farm_team_valid = False
                continue
        if pick is not None:
            eid = pick[0]
            price = game.eggs[eid]["price"]
            if coins < price:
                t += (price - coins) / rate()
                coins = price
            coins -= price
            if training_during_hatch(game):
                coins += rate() * SIM["hatch_seconds"]
            t += SIM["hatch_seconds"]
            inst = roll(eid)
            prior_anchor = legacy_anchor
            legacy_anchor = max(legacy_anchor, inst["click"])
            inventory_key = (inst["pet"], inst["variant"])
            copies = owned.setdefault(inventory_key, [])
            new_copy = len(copies) < size
            if new_copy:
                copies.append(inst)
            res["hatches"] += 1
            if res["first_hatch"] is None:
                res["first_hatch"] = t
            if inst["variant"] == "normal" and inst["pet"] not in seen[eid]:
                seen[eid].add(inst["pet"])
                if len(seen[eid]) == C["pets_per_egg"]:
                    done_eggs += 1
            changed = False
            if len(team) < size:
                team.append(inst)
                changed = True
            else:
                j = min(range(size), key=lambda x: key(team[x]))
                if key(inst) > key(team[j]):
                    team[j] = inst
                    changed = True
            if not train and (not reuse_calculations or not farm_team_valid or new_copy or changed or legacy_anchor != prior_anchor):
                team = sorted((p for copies in owned.values() for p in copies), key=effective_click, reverse=True)[:size]
                farm_team_valid = True
            if train:
                farm_team_valid = False
                train_hatches += 1
                if changed:
                    losses = 0
            continue
        # gym
        if not fee_paid:
            fee = game.worlds[beaten]["gym"]["fee"]
            if coins < fee:
                t += (fee - coins) / rate()
                coins = fee
                if t >= max_seconds:
                    break
            coins -= fee
            fee_paid = True
        order = sorted(team, key=lambda i: -game.matchup(i, lt))
        won, turns = battle(game, rng, order, leaders[beaten], r)
        res["battles"] += 1
        t += turns * SIM["turn_seconds"]
        if won:
            if res["gym"][beaten] is None:
                res["gym"][beaten] = t
                res["gym_rebirths"][beaten] = r
            beaten += 1
            fee_paid, losses, train = False, 0, False
            if beaten == nw:
                break
        else:
            losses += 1
            coins += rate() * C["gym_retry_seconds"]
            t += C["gym_retry_seconds"]
            if losses >= SIM["losses_before_stuck"] and not train:
                train = True
                train_hatches = 0
    return res


def pct(vals, q):
    if not vals:
        return None
    s = sorted(vals)
    x = (len(s) - 1) * q
    i = int(x)
    j = min(i + 1, len(s) - 1)
    return s[i] + (s[j] - s[i]) * (x - i)


INF = float("inf")


def summarize(vals, n, pad=True):
    """Percentiles over all players. A player who never got there counts as infinitely late."""
    v = [x for x in vals if x is not None]
    share = len(v) / n if n else 0
    if pad:
        v = v + [INF] * (n - len(v))

    def q(x):
        if not v:
            return None
        s = sorted(v)
        hi = s[min(len(s) - 1, int((len(s) - 1) * x) + 1)]
        return INF if hi == INF else pct(v, x)
    return {"p10": q(0.1), "p50": q(0.5), "p90": q(0.9), "share": share}


def training_during_hatch(game):
    return ("training_tick_seconds" in game.C
            and game.C.get("training_hatch_pause_seconds", 0) == 0)


def training_rates(game):
    constants = game.C
    if "training_hits_per_tick" in constants:
        rate = constants["training_hits_per_tick"] / constants["training_tick_seconds"]
        return [rate, rate / 2]
    return list(SIM["click_rates"])


def run_progression(game, gyms, players, seed, max_hours):
    runs = {}
    nw = len(game.worlds)
    for cps in training_rates(game):
        rng = random.Random(seed * 1000003 + cps)
        rs = [simulate_player(game, gyms, cps, rng, max_hours * 3600) for _ in range(players)]
        max_r = max(len(x["rebirths"]) for x in rs)
        runs[cps] = {
            "first_hatch": summarize([x["first_hatch"] for x in rs], players),
            "gym": [summarize([x["gym"][i] for x in rs], players) for i in range(nw)],
            "gym_rebirths": [summarize([x["gym_rebirths"][i] for x in rs], players, pad=False) for i in range(nw)],
            "rebirths": [summarize([x["rebirths"][k] if len(x["rebirths"]) > k else None for x in rs], players, pad=False)
                         for k in range(max_r)],
            "hatches": pct([x["hatches"] for x in rs], 0.5),
            "battles": pct([x["battles"] for x in rs], 0.5),
        }
    return runs


# ---------------------------------------------------------------- report

def ft(sec):
    if sec is None:
        return "n/a"
    if sec == INF:
        return "not reached"
    if sec < 120:
        return "%.0f s" % sec
    if sec < 7200:
        return "%.1f min" % (sec / 60)
    return "%.2f h" % (sec / 3600)


def fn(x):
    if isinstance(x, float) and x != int(x):
        return ("%.3f" % x).rstrip("0").rstrip(".")
    return "{:,}".format(int(x)) if isinstance(x, (int, float)) else str(x)


def trio(s, f=ft):
    return "%s (%s to %s)" % (f(s["p50"]), f(s["p10"]), f(s["p90"]))


def verdicts(game, run):
    """Rows of (target, wanted, measured median, verdict)."""
    C = game.C
    rows = []
    fh = run["first_hatch"]["p50"]
    lim = C["pacing_first_hatch_minutes"] * 60
    rows.append(("First hatch", "within %s" % ft(lim), ft(fh),
                 "MET" if fh is not None and fh <= lim else "MISSED"))

    def band(name, val, lo, hi):
        if val is None or val == INF:
            return (name, "%s to %s" % (ft(lo), ft(hi)), "n/a", "MISSED, most players never get there")
        if val < lo:
            v = "MISSED, %s too fast (%.1fx)" % (ft(lo - val), lo / val)
        elif val > hi:
            v = "MISSED, %s too slow (%.1fx)" % (ft(val - hi), val / hi)
        else:
            v = "MET"
        return (name, "%s to %s" % (ft(lo), ft(hi)), ft(val), v)

    g = run["gym"]
    rows.append(band("Gym 1 beaten", g[0]["p50"],
                     C["pacing_gym1_minutes_min"] * 60, C["pacing_gym1_minutes_max"] * 60))
    rows.append(band("Final gym beaten", g[-1]["p50"],
                     C["pacing_final_gym_hours_min"] * 3600, C["pacing_final_gym_hours_max"] * 3600))
    for i, w in enumerate(game.worlds):
        tr = w["gym"]["target_rebirths"]
        m = run["gym_rebirths"][i]["p50"]
        if m is None:
            v, ms = "MISSED, never beaten", "n/a"
        else:
            ms = fn(round(m, 1))
            d = m - tr
            v = "MET" if abs(d) < 0.5 else "MISSED, %s %s" % (fn(round(abs(d), 1)), "too many" if d > 0 else "too few")
        rows.append(("Rebirths at gym %d" % (i + 1), str(tr), ms, v))
    return rows


def table(head, rows):
    out = ["| " + " | ".join(head) + " |", "| " + " | ".join("---" for _ in head) + " |"]
    for r in rows:
        out.append("| " + " | ".join(str(c) for c in r) + " |")
    return out


def section_results(game, gyms, runs, players, max_hours):
    main = training_rates(game)[0]
    L = []
    L += table(["Target", "Wanted", "Median at %d cps" % main, "Verdict"], verdicts(game, runs[main]))
    L.append("")
    L.append("Medians with 10th to 90th percentile in brackets. %d players per click rate. Runs stop at %d hours." % (players, max_hours))
    L.append("")
    rows = []
    for cps in sorted(runs):
        r = runs[cps]
        rows.append(["%d cps" % cps, trio(r["first_hatch"])] + [trio(g) for g in r["gym"]]
                    + ["%.0f%%" % (100 * r["gym"][-1]["share"])])
    L += table(["Click rate", "First hatch"] + ["Gym %d" % (i + 1) for i in range(len(game.worlds))] + ["Finished"], rows)
    L.append("")
    r = runs[main]
    rows = [["Gym %d" % (i + 1), w["gym"]["target_rebirths"],
             trio(r["gym_rebirths"][i], lambda x: "n/a" if x is None else fn(round(x, 1)))]
            for i, w in enumerate(game.worlds)]
    L += table(["Gym", "Target rebirths", "Rebirths when first beaten at %d cps" % main], rows)
    L.append("")
    rows = [["Rebirth %d" % (k + 1), fn(game.rebirth_cost(k)), trio(s), "%.0f%%" % (100 * s["share"])]
            for k, s in enumerate(r["rebirths"]) if s["share"] >= 0.05]
    if rows:
        L += table(["Rebirth", "Cost", "Time at %d cps, among players who did it" % main, "Players who did it"], rows)
    else:
        L.append("No rebirth was done by 5% of players or more.")
    L.append("")
    L.append("Median player at %d cps: %s hatches, %s gym battles." % (main, fn(r["hatches"]), fn(r["battles"])))
    L.append("")
    rows = []
    for g in gyms:
        l = g["leader_team"][0]
        rows.append([g["world_name"], g["power"], "%d x %s HP %s, Attack %s" % (len(g["leader_team"]), l["type"], fn(l["hp"]), fn(l["attack"])),
                     ", ".join(p["pet"] for p in g["reference_team"]),
                     " ".join("%s:%.0f%%" % (k, 100 * v) for k, v in g["reference_win_rate_by_rebirths"].items())])
    L += table(["Gym", "Tuned power", "Leader team", "Reference team", "Reference win rate by rebirths"], rows)
    L += table(["Gym", "Reference baseline power", "Spec cohort factor", "Final power"],
               [[g["world_name"], g["reference_power"], g["cohort_power_factor"], g["power"]]
                for g in gyms])
    return L


def gaps(game, gyms):
    out = []
    for g in gyms:
        t = g["target_rebirths"]
        if t > 0 and g["reference_win_rate_by_rebirths"][str(t - 1)] < 0.05:
            out.append("%s: the gym is a hard wall. The reference team wins %.0f%% one rebirth below the target and %.0f%% at the target. Damage only varies by the damage roll, so there is almost no luck in a battle."
                       % (g["world_name"], 100 * g["reference_win_rate_by_rebirths"][str(t - 1)], 100 * g["reference_win_rate_at_target"]))
    for w in game.worlds:
        wi = game.world_index[w["id"]]
        g = w["gym"]
        rares = [p for p in game.pets.values() if p["rarity"] == "rare" and game.world_index[p["world"]] <= wi]
        if len(rares) < game.C["team_size"]:
            out.append("%s: only %d distinct Rare pets can be hatched by this world. The reference team repeats the best one." % (w["name"], len(rares)))
        if not any(p["type"] == g["counter_type"] for p in rares):
            out.append("%s: no Rare pet of the counter type (%s) exists by this world. The reference team has no type advantage, so this gym is tuned weaker than the design intends."
                       % (w["name"], g["counter_type"]))
    roles = set(p["role"] for p in game.pets.values() if p["rarity"] == "rare")
    if roles == {"fighter"}:
        out.append("Every Rare pet is a Fighter. Rare teams earn half the Click Power budget, and the gyms are tuned against the best battle role.")
    return out


def write_report(path, game, gyms, runs, players, seed, max_hours, prop, prop_rows, game2, gyms2, runs2):
    main = training_rates(game)[0]
    L = ["# Economy tuning report: %s" % game.C["game_name"], "",
         "Generated by `factory/tools/simulate_economy.py`. Seed %d. Do not edit by hand." % seed, "",
         "## Current numbers against the targets", ""]
    L += section_results(game, gyms, runs, players, max_hours)
    L += ["", "## Design gaps found", ""]
    L += ["- " + g for g in gaps(game, gyms)] or ["None."]
    L += ["", "## Proposed changes", ""]
    if not prop:
        hint = os.path.join(os.path.dirname(path) or ".", "proposal.json").replace(os.sep, "/")
        L.append("No proposal file was given. Write `%s` and rerun." % hint)
    else:
        L.append("Proposals only. The spec and config were not changed.")
        L.append("")
        notes = prop.get("notes", {})
        L += table(["Spec value", "Current", "Proposed"], [[a, fn(b), fn(c)] for a, b, c in prop_rows])
        L.append("")
        for k, v in notes.items():
            L.append("- %s: %s" % (k, v))
        L += ["", "## Predicted result with the proposed changes", "",
              "Gyms were tuned again with the proposed numbers, then the same players were simulated.", ""]
        L += section_results(game2, gyms2, runs2, players, max_hours)
    L += ["", "## Assumptions the spec does not define", ""]
    fmt = dict(SIM)
    fmt.update(leader_speed=game.leader_speed, heal_pct=int(SIM["heal_below_hp"] * 100), main_cps=main)
    L += ["%d. %s" % (i + 1, a.format(**fmt)) for i, a in enumerate(ASSUMPTIONS)]
    L.append("")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(L))


# ---------------------------------------------------------------- main

def main(argv=None):
    ap = argparse.ArgumentParser(description="Economy simulator and gym tuner")
    ap.add_argument("config")
    ap.add_argument("out")
    ap.add_argument("--players", type=int, default=300)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--proposal", default=None)
    ap.add_argument("--max-hours", type=int, default=40)
    a = ap.parse_args(argv)

    cfg = load_config(a.config)
    os.makedirs(a.out, exist_ok=True)
    game = Game(cfg)
    for p in cfg["pets"]:
        q = game.pets[p["id"]]
        if (p["hp"], p["attack"]) != (q["hp"], q["attack"]) or abs(p["click_power"] - q["click_power"]) > 1e-9:
            print("TUNER ERROR: pets.json stats for %s do not match eggs x rarity x role" % p["id"])
            return 1

    gyms = tune_gyms(game, a.seed)
    runs = run_progression(game, gyms, a.players, a.seed, a.max_hours)

    prop_path = a.proposal or os.path.join(a.out, "proposal.json")
    prop = prop_rows = game2 = gyms2 = runs2 = None
    if os.path.exists(prop_path):
        with open(prop_path, encoding="utf-8") as f:
            prop = json.load(f)
        cfg2 = apply_proposal(cfg, prop)
        prop_rows = diff_rows(cfg, cfg2)
        if cfg2 == cfg:
            # A notes-only proposal has exactly the same seeded results.
            game2, gyms2, runs2 = game, gyms, runs
        else:
            game2 = Game(cfg2)
            gyms2 = tune_gyms(game2, a.seed)
            runs2 = run_progression(game2, gyms2, a.players, a.seed, a.max_hours)

    out = {"generated_by": "factory/tools/simulate_economy.py", "seed": a.seed,
           "target_win_rate": SIM["tune_target_win_rate"], "leader_speed": game.leader_speed,
           "target_win_rate_applies_to": "reference_power before the configured cohort factor",
           "gyms": gyms}
    if gyms2:
        out["gyms_with_proposal"] = gyms2
    with open(os.path.join(a.out, "gyms.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)
        f.write("\n")
    write_report(os.path.join(a.out, "report.md"), game, gyms, runs, a.players, a.seed, a.max_hours,
                 prop, prop_rows, game2, gyms2, runs2)

    main_cps = training_rates(game)[0]
    for label, g, gy, ru in (("current", game, gyms, runs), ("proposed", game2, gyms2, runs2)):
        if not g:
            continue
        print("[%s] gym powers: %s" % (label, ", ".join("%s %.3f" % (x["world"], x["power"]) for x in gy)))
        for row in verdicts(g, ru[main_cps]):
            print("[%s] %-20s wanted %-22s got %-10s %s" % ((label,) + row))
    print("Wrote %s and %s" % (os.path.join(a.out, "gyms.json"), os.path.join(a.out, "report.md")))
    if "training_hits_per_tick" in cfg["constants"]:
        with open(os.path.join(a.out, "report.md"), "a", encoding="utf-8") as report:
            report.write("\nTraining uses configured hits/tick for the main cohort and 50% uptime for the slower cohort. Historical clicks/sec labels mean training hits/sec. Travel, idle time and offline income are excluded from this active-session baseline.\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
