--!strict
--[[
	Config: the single read point for every generated game number.

	The tables under ReplicatedStorage.GameConfig are produced by
	factory/tools/parse_spec.py and factory/tools/simulate_economy.py. Nothing
	here invents a number; this module only reshapes the generated data into
	typed lists and id lookups, and refuses to load if an id does not resolve.

	Every lookup table errors on an unknown key instead of returning nil, so a
	typo in a pet or world id fails at the call site rather than much later.
]]

-- Shared and GameConfig both sit in ReplicatedStorage (see default.project.json).
-- Reaching GameConfig through the script tree instead of game:GetService keeps
-- this module free of engine globals, so rule modules can require it and the
-- headless test runner, which mounts the same JSON at the same place, can load it.
local ReplicatedStorage = (script.Parent :: Instance).Parent :: Instance

local GameConfig = ReplicatedStorage:WaitForChild("GameConfig")

export type Constants = {
	game_name: string,
	roblox_title: string,
	team_size: number,
	pets_per_egg: number,
	character_walk_speed: number,
	legacy_epic_floor: number,
	legacy_legendary_floor: number,
	basic_move_power: number,
	special_cooldown_turns: number,
	type_bonus_strong: number,
	type_bonus_weak: number,
	damage_random_min: number,
	damage_random_max: number,
	gym_retry_seconds: number,
	rebirth_first_cost: number,
	rebirth_cost_growth: number,
	rebirth_coin_bonus: number,
	rebirth_battle_bonus: number,
	index_egg_bonus: number,
	speed_min: number,
	speed_max: number,
	pacing_first_hatch_minutes: number,
	pacing_gym1_minutes_min: number,
	pacing_gym1_minutes_max: number,
	pacing_final_gym_hours_min: number,
	pacing_final_gym_hours_max: number,
}

export type Rarity = {
	id: string,
	name: string,
	order: number,
	hatch_chance: number,
	click_mult: number,
	battle_mult: number,
}

export type Role = {
	id: string,
	name: string,
	click_mult: number,
	battle_mult: number,
}

export type Variant = {
	id: string,
	name: string,
	hatch_chance: number,
	click_mult: number,
	battle_mult: number,
	look: string,
}

export type PetType = {
	id: string,
	name: string,
	strong_against: string,
	weak_against: string,
}

export type Special = {
	id: string,
	name: string,
	kind: string,
	power: number,
	value: number,
	effect: string,
}

export type Pass = {
	id: string,
	name: string,
	effect: string,
}

export type Egg = {
	id: string,
	name: string,
	base_click_power: number,
	base_hp: number,
	base_attack: number,
	price: number,
	world: string,
}

export type WorldGym = {
	fee: number,
	leader_count: number,
	leader_type: string,
	leader_strength: string,
	counter_type: string,
	target_rebirths: number,
}

export type World = {
	index: number,
	id: string,
	name: string,
	environment: string,
	eggs: { string },
	gym: WorldGym,
}

export type Pet = {
	id: string,
	name: string,
	looks_like: string,
	edition: string?,
	egg: string,
	world: string,
	rarity: string,
	type: string,
	role: string,
	special: string,
	special_off_type: string?,
	speed: number,
	click_power: number,
	hp: number,
	attack: number,
}

export type GymLeaderPet = {
	type: string,
	hp: number,
	attack: number,
	speed: number,
	special: string,
}

export type GymReferencePet = {
	pet: string,
	type: string,
	hp: number,
	attack: number,
	speed: number,
	special: string,
}

export type Gym = {
	world: string,
	world_name: string,
	fee: number,
	target_rebirths: number,
	power: number,
	leader_base_egg: string,
	leader_strength: string,
	leader_team: { GymLeaderPet },
	reference_team: { GymReferencePet },
	reference_win_rate_at_target: number,
	reference_win_rate_by_rebirths: { [string]: number },
}

export type Manifest = {
	spec: string,
	spec_sha256: string,
	counts: { [string]: number },
}

export type GymsFile = {
	generated_by: string,
	seed: number,
	target_win_rate: number,
	leader_speed: number,
	gyms: { Gym },
}

-- Loading
--
-- Rojo turns each generated .json file into a ModuleScript that returns a
-- plain table, so these requires are the only place the raw data is read.

local constants: Constants = require(GameConfig:WaitForChild("constants"))
local rarities: { Rarity } = require(GameConfig:WaitForChild("rarities"))
local roles: { Role } = require(GameConfig:WaitForChild("roles"))
local variants: { Variant } = require(GameConfig:WaitForChild("variants"))
local types: { PetType } = require(GameConfig:WaitForChild("types"))
local specials: { Special } = require(GameConfig:WaitForChild("specials"))
local passes: { Pass } = require(GameConfig:WaitForChild("passes"))
local eggs: { Egg } = require(GameConfig:WaitForChild("eggs"))
local worlds: { World } = require(GameConfig:WaitForChild("worlds"))
local pets: { Pet } = require(GameConfig:WaitForChild("pets"))
local manifest: Manifest = require(GameConfig:WaitForChild("manifest"))
local gymsFile: GymsFile = require(GameConfig:WaitForChild("gyms"))
local gyms: { Gym } = gymsFile.gyms

-- Lookups

-- Builds a key to record map and rejects duplicate keys. The map stays plain at
-- this point so the referential checks below can probe it for missing ids.
local function indexBy<K, V>(label: string, list: { V }, keyOf: (V) -> K): { [K]: V }
	local map: { [K]: V } = {}
	for _, item in list do
		local key = keyOf(item)
		if map[key] ~= nil then
			error(string.format("config %s has two entries for %s", label, tostring(key)))
		end
		map[key] = item
	end
	return map
end

-- Turns the nil result of an unknown key into an error that names the lookup.
local function guard<K, V>(label: string, map: { [K]: V }): { [K]: V }
	local guarded = setmetatable(map :: any, {
		__index = function(_self: any, key: any)
			error(string.format("Config.%s has no entry for %s", label, tostring(key)), 2)
		end,
		__newindex = function(_self: any, key: any)
			error(
				string.format("Config.%s is read only (tried to set %s)", label, tostring(key)),
				2
			)
		end,
	})
	return (guarded :: any) :: { [K]: V }
end

local function idOf(record: { id: string }): string
	return record.id
end

local petById = indexBy("pets", pets, idOf)
local eggById = indexBy("eggs", eggs, idOf)
local worldById = indexBy("worlds", worlds, idOf)
local rarityById = indexBy("rarities", rarities, idOf)
local roleById = indexBy("roles", roles, idOf)
local variantById = indexBy("variants", variants, idOf)
local typeById = indexBy("types", types, idOf)
local specialById = indexBy("specials", specials, idOf)
local passById = indexBy("passes", passes, idOf)

local worldByIndex = indexBy("worlds", worlds, function(world: World): number
	return world.index
end)

local gymByWorld = indexBy("gyms", gyms, function(gym: Gym): string
	return gym.world
end)

-- Referential checks.
--
-- These run while the maps are still plain, so a missing id reports its own
-- owner and field instead of surfacing much later from inside a lookup.

local function requireId<V>(map: { [string]: V }, id: string, owner: string, field: string): ()
	if map[id] == nil then
		error(string.format("%s.%s refers to the unknown id %q", owner, field, id))
	end
end

for _, petType in types do
	requireId(typeById, petType.strong_against, "type " .. petType.id, "strong_against")
	requireId(typeById, petType.weak_against, "type " .. petType.id, "weak_against")
end

for _, egg in eggs do
	requireId(worldById, egg.world, "egg " .. egg.id, "world")
end

for _, world in worlds do
	local owner = "world " .. world.id
	for position, eggId in world.eggs do
		requireId(eggById, eggId, owner, string.format("eggs[%d]", position))
	end
	requireId(typeById, world.gym.leader_type, owner, "gym.leader_type")
	requireId(typeById, world.gym.counter_type, owner, "gym.counter_type")
	requireId(rarityById, world.gym.leader_strength, owner, "gym.leader_strength")
	requireId(gymByWorld, world.id, owner, "gym stats from tuning/gyms.json")
end

for _, pet in pets do
	local owner = "pet " .. pet.id
	requireId(eggById, pet.egg, owner, "egg")
	requireId(worldById, pet.world, owner, "world")
	requireId(rarityById, pet.rarity, owner, "rarity")
	requireId(typeById, pet.type, owner, "type")
	requireId(roleById, pet.role, owner, "role")
	requireId(specialById, pet.special, owner, "special")
	local offType = pet.special_off_type
	if offType ~= nil then
		requireId(typeById, offType, owner, "special_off_type")
	end
end

for _, gym in gyms do
	local owner = "gym " .. gym.world
	requireId(worldById, gym.world, owner, "world")
	requireId(eggById, gym.leader_base_egg, owner, "leader_base_egg")
	requireId(rarityById, gym.leader_strength, owner, "leader_strength")
	for position, leader in gym.leader_team do
		requireId(typeById, leader.type, owner, string.format("leader_team[%d].type", position))
		requireId(
			specialById,
			leader.special,
			owner,
			string.format("leader_team[%d].special", position)
		)
	end
	for position, reference in gym.reference_team do
		requireId(petById, reference.pet, owner, string.format("reference_team[%d].pet", position))
	end
end

-- Public surface

local Config = {
	constants = constants,

	pets = pets,
	eggs = eggs,
	worlds = worlds,
	rarities = rarities,
	roles = roles,
	variants = variants,
	types = types,
	specials = specials,
	passes = passes,
	gyms = gyms,
	manifest = manifest,

	petById = guard("petById", petById),
	eggById = guard("eggById", eggById),
	worldById = guard("worldById", worldById),
	worldByIndex = guard("worldByIndex", worldByIndex),
	rarityById = guard("rarityById", rarityById),
	roleById = guard("roleById", roleById),
	variantById = guard("variantById", variantById),
	typeById = guard("typeById", typeById),
	specialById = guard("specialById", specialById),
	passById = guard("passById", passById),
	gymByWorld = guard("gymByWorld", gymByWorld),
}

return Config
