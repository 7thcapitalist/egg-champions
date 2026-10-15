--!strict
--[[
	PetsView: what the pets and index screen shows, worked out with no engine
	calls so the headless tests can check it.

	- My pets: one tile per owned pet, from the profile the server sent. Each
	  tile carries its rarity (for the stripe), its variant (for the marker),
	  its Click Power with the variant multiplier, and whether it is equipped.
	  Tiles sort and filter by rarity, Click Power, type and egg. The default
	  sort is highest Click Power first.
	- Index: every pet in config, one tile each, with normal, shiny and golden
	  seen states tracked separately (PetIndex). Per egg, the completion count
	  and the coin bonus a completed egg gives (constants.index_egg_bonus).
	- Fruit Edition: the pets whose config edition is set. It is a collection
	  tag only, so it never changes a stat.
	- Detail: a pet's stats with its variant multipliers applied the way the
	  rule modules apply them (Coins.clickPowerOf for Click Power,
	  Battle.playerMultiplier with no rebirths for HP and Attack), its type,
	  rarity and role, and both moves with their real numbers from config
	  (specialText).

	Nothing here decides an equip. The server does, and reasonText only turns
	its refusal into words. Nothing here changes the state it is given.
]]

local Config = require(script.Parent.Parent.Config)
local Coins = require(script.Parent.Parent.rules.Coins)
local Battle = require(script.Parent.Parent.rules.Battle)
local PetIndex = require(script.Parent.Parent.rules.PetIndex)
local Format = require(script.Parent.Format)

export type OwnedPet = {
	uid: string,
	petId: string,
	variant: string?,
}

export type SortKey = "power" | "rarity" | "type" | "egg"

export type Filter = {
	rarity: string?,
	type: string?,
	egg: string?,
}

export type Tile = {
	uid: string,
	petId: string,
	name: string,
	rarity: string,
	rarityName: string,
	type: string,
	typeName: string,
	egg: string,
	variant: string?,
	variantName: string?,
	clickPower: number,
	clickPowerText: string,
	equipped: boolean,
}

export type Seen = {
	normal: boolean,
	shiny: boolean,
	golden: boolean,
}

export type IndexTile = {
	petId: string,
	name: string,
	rarity: string,
	rarityName: string,
	type: string,
	egg: string,
	edition: string?,
	seen: Seen,
	seenAny: boolean,
}

export type EggProgress = {
	eggId: string,
	name: string,
	seen: number,
	total: number,
	complete: boolean,
	bonus: number,
	bonusText: string,
	tiles: { IndexTile },
}

export type Move = {
	name: string,
	kind: string,
	text: string,
}

export type Detail = {
	petId: string,
	name: string,
	variant: string?,
	variantName: string?,
	typeName: string,
	rarityName: string,
	roleName: string,
	editionName: string?,
	clickPower: number,
	hp: number,
	attack: number,
	speed: number,
	stats: { { label: string, value: string } },
	moves: { Move },
}

local PetsView = {}

PetsView.DEFAULT_SORT = "power" :: SortKey

-- The sort choices, in the order the sort button cycles through them.
PetsView.SORTS = table.freeze({ "power", "rarity", "type", "egg" } :: { SortKey })

PetsView.SORT_NAMES = table.freeze({
	power = "Click Power",
	rarity = "Rarity",
	type = "Type",
	egg = "Egg",
} :: { [string]: string })

-- How the Fruit Edition tag reads on screen, by config edition value.
local EDITION_NAMES: { [string]: string } = {
	fruit = "Fruit Edition",
}

function PetsView.editionName(edition: string): string
	return EDITION_NAMES[edition]
		or (string.upper(string.sub(edition, 1, 1)) .. string.sub(edition, 2) .. " Edition")
end

-- Readable messages for the reasons the server can refuse an equip.
local REASONS: { [string]: string } = {
	team_full = string.format(
		"Your team is full (%d of %d). Unequip a pet first.",
		Config.constants.team_size,
		Config.constants.team_size
	),
	already_equipped = "That pet is already on your team.",
	not_equipped = "That pet is not on your team.",
	not_owned = "You do not own that pet.",
	rate_limited = "Slow down a little and try again.",
	no_profile = "Your save is still loading. Try again in a moment.",
	server_error = "Something went wrong on the server. Try again.",
	bad_choice = "The server did not understand that request.",
}

function PetsView.reasonText(reason: any): string
	if type(reason) == "string" and REASONS[reason] ~= nil then
		return REASONS[reason]
	end
	return "The server refused: " .. tostring(reason)
end

-- A number with at most two decimals and no trailing zeros: 2 -> "2", 2.4 -> "2.4".
function PetsView.number(value: number): string
	local hundredths = math.floor(value * 100 + 0.5)
	if hundredths % 100 == 0 then
		return Format.commas(hundredths // 100)
	end
	local text = string.format("%.2f", hundredths / 100)
	text = string.gsub(text, "0$", "")
	return text
end

-- A whole number, rounded, with thousands separators: 37.5 -> "38".
function PetsView.whole(value: number): string
	return Format.commas(math.floor(value + 0.5))
end

-- Below this many owned pets the screen stays simple: no sort and filter
-- row, and no Index or Fruit Edition tabs. A size of the interface, not a
-- game number.
PetsView.FULL_SCREEN_PETS = 4

-- The parts of the pets screen a player with petCount pets sees: the sort
-- and filter row, and the tabs in order.
function PetsView.screenParts(petCount: number): { filters: boolean, tabs: { string } }
	if petCount < PetsView.FULL_SCREEN_PETS then
		return { filters = false, tabs = { "pets" } }
	end
	return { filters = true, tabs = { "pets", "index", "fruit" } }
end

-- True when the pets screen shows its beginner detail: while the tutorial
-- runs or while the player owns fewer than FULL_SCREEN_PETS pets.
function PetsView.beginner(petCount: number, tutorialActive: boolean): boolean
	return tutorialActive or petCount < PetsView.FULL_SCREEN_PETS
end

-- The label of the toggle that shows or hides battle stats and moves.
PetsView.BATTLE_TOGGLE = table.freeze({ closed = "Battle stats", open = "Hide battle stats" })

export type DetailParts = {
	-- The second line under the name.
	typeLine: string,
	stats: { { label: string, value: string } },
	moves: boolean,
	-- The toggle label, or nil when there is no toggle.
	toggle: string?,
}

-- What the detail panel shows of info. A beginner sees name, rarity, type
-- and Click Power, with battle stats and moves behind the toggle
-- (battleOpen). Everyone else sees everything and no toggle.
function PetsView.detailParts(info: Detail, beginner: boolean, battleOpen: boolean): DetailParts
	if not beginner then
		local editionName = info.editionName
		return {
			typeLine = info.typeName .. "  " .. info.roleName .. (if editionName ~= nil
				then "  " .. editionName
				else ""),
			stats = info.stats,
			moves = true,
			toggle = nil,
		}
	end
	local stats = {}
	for _, stat in info.stats do
		if battleOpen or stat.label == "Click Power" then
			table.insert(stats, stat)
		end
	end
	return {
		typeLine = info.typeName,
		stats = stats,
		moves = battleOpen,
		toggle = if battleOpen then PetsView.BATTLE_TOGGLE.open else PetsView.BATTLE_TOGGLE.closed,
	}
end

-- A tile's Click Power line: "Click +3".
function PetsView.clickText(power: number): string
	return "Click +" .. PetsView.number(power)
end

-- A fraction as a whole-number-ish percent: 0.3 -> "30%".
local function percent(fraction: number): string
	return PetsView.number(fraction * 100) .. "%"
end

-- What a special move does, with its real numbers from config/specials.json
-- (and the basic move power and cooldown from constants), worded the way
-- shared/rules/Battle applies them. offTypeName is the pet's off-type name
-- for an off-type move.
function PetsView.specialText(
	special: Config.Special,
	typeName: string,
	offTypeName: string?
): string
	local basic = Config.constants.basic_move_power
	local text: string
	if special.kind == "attack" then
		text = string.format(
			"%s attack with %s power (basic is %s)",
			typeName,
			PetsView.number(special.power),
			PetsView.number(basic)
		)
	elseif special.kind == "drain" then
		text = string.format(
			"%s attack with %s power that heals %s of the damage dealt",
			typeName,
			PetsView.number(special.power),
			percent(special.value)
		)
	elseif special.kind == "heal" then
		text = string.format("restores %s of max HP", percent(special.value))
	elseif special.kind == "guard" then
		text = string.format("the next hit taken does %s of its damage", percent(special.value))
	elseif special.kind == "speed" then
		text = string.format(
			"raises own Speed by %s for the rest of the battle",
			percent(special.value)
		)
	elseif special.kind == "offtype" then
		text = string.format(
			"%s attack with %s power",
			offTypeName or "Off-type",
			PetsView.number(special.power)
		)
	else
		text = special.effect
	end
	return string.format(
		"%s. Ready again after %d turns",
		text,
		Config.constants.special_cooldown_turns
	)
end

local function knownPet(petId: any): Config.Pet?
	if type(petId) ~= "string" then
		return nil
	end
	local ok, pet = pcall(function(): Config.Pet
		return Config.petById[petId]
	end)
	return if ok then pet else nil
end

local function knownVariant(variant: any): Config.Variant?
	if type(variant) ~= "string" then
		return nil
	end
	local ok, row = pcall(function(): Config.Variant
		return Config.variantById[variant]
	end)
	return if ok then row else nil
end

-- One tile per owned pet the client recognises, in profile order.
function PetsView.tiles(pets: any, team: any): { Tile }
	local equipped: { [string]: boolean } = {}
	if type(team) == "table" then
		for _, uid in team do
			if type(uid) == "string" then
				equipped[uid] = true
			end
		end
	end
	local tiles: { Tile } = {}
	if type(pets) ~= "table" then
		return tiles
	end
	for _, owned in pets do
		if type(owned) == "table" and type(owned.uid) == "string" then
			local pet = knownPet(owned.petId)
			if pet ~= nil then
				local variant = knownVariant(owned.variant)
				local power = Coins.clickPowerOf({
					petId = pet.id,
					variant = if variant ~= nil then variant.id else nil,
				})
				table.insert(tiles, {
					uid = owned.uid,
					petId = pet.id,
					name = pet.name,
					rarity = pet.rarity,
					rarityName = Config.rarityById[pet.rarity].name,
					type = pet.type,
					typeName = Config.typeById[pet.type].name,
					egg = pet.egg,
					variant = if variant ~= nil then variant.id else nil,
					variantName = if variant ~= nil then variant.name else nil,
					clickPower = power,
					clickPowerText = PetsView.clickText(power),
					equipped = equipped[owned.uid] == true,
				})
			end
		end
	end
	return tiles
end

local function positionIn<T>(list: { T }, matches: (T) -> boolean): number
	for position, item in list do
		if matches(item) then
			return position
		end
	end
	return math.huge
end

local function typeRank(typeId: string): number
	return positionIn(Config.types, function(row: Config.PetType): boolean
		return row.id == typeId
	end)
end

local function eggRank(eggId: string): number
	return positionIn(Config.eggs, function(row: Config.Egg): boolean
		return row.id == eggId
	end)
end

local function rarityOrder(rarityId: string): number
	return Config.rarityById[rarityId].order
end

-- The tiles that pass the filter, sorted. Never changes its input.
-- Ties fall back to higher Click Power, then rarer, then name, then uid, so
-- the order is stable from one push to the next.
function PetsView.arrange(tiles: { Tile }, sortKey: SortKey?, filter: Filter?): { Tile }
	local key = sortKey or PetsView.DEFAULT_SORT
	local kept: { Tile } = {}
	for _, tile in tiles do
		local keep = filter == nil
			or (
				(filter.rarity == nil or tile.rarity == filter.rarity)
				and (filter.type == nil or tile.type == filter.type)
				and (filter.egg == nil or tile.egg == filter.egg)
			)
		if keep then
			table.insert(kept, tile)
		end
	end
	local function tieBreak(a: Tile, b: Tile): boolean
		if a.clickPower ~= b.clickPower then
			return a.clickPower > b.clickPower
		end
		local ra, rb = rarityOrder(a.rarity), rarityOrder(b.rarity)
		if ra ~= rb then
			return ra > rb
		end
		if a.name ~= b.name then
			return a.name < b.name
		end
		return a.uid < b.uid
	end
	table.sort(kept, function(a: Tile, b: Tile): boolean
		if key == "rarity" then
			local ra, rb = rarityOrder(a.rarity), rarityOrder(b.rarity)
			if ra ~= rb then
				return ra > rb
			end
		elseif key == "type" then
			local ta, tb = typeRank(a.type), typeRank(b.type)
			if ta ~= tb then
				return ta < tb
			end
		elseif key == "egg" then
			local ea, eb = eggRank(a.egg), eggRank(b.egg)
			if ea ~= eb then
				return ea < eb
			end
		end
		return tieBreak(a, b)
	end)
	return kept
end

-- The next sort in the cycle.
function PetsView.nextSort(current: SortKey): SortKey
	local position = table.find(PetsView.SORTS, current) or 0
	return PetsView.SORTS[position % #PetsView.SORTS + 1]
end

-- The filter values of one kind, in config order. nil is "all".
function PetsView.filterChoices(kind: "rarity" | "type" | "egg"): { string }
	local choices: { string } = {}
	if kind == "rarity" then
		local ordered = table.clone(Config.rarities)
		table.sort(ordered, function(a, b)
			return a.order < b.order
		end)
		for _, row in ordered do
			table.insert(choices, row.id)
		end
	elseif kind == "type" then
		for _, row in Config.types do
			table.insert(choices, row.id)
		end
	else
		for _, row in Config.eggs do
			table.insert(choices, row.id)
		end
	end
	return choices
end

-- The next filter value after current: all, then each choice, then all again.
function PetsView.nextFilter(kind: "rarity" | "type" | "egg", current: string?): string?
	local choices = PetsView.filterChoices(kind)
	if current == nil then
		return choices[1]
	end
	local position = table.find(choices, current)
	if position == nil or position >= #choices then
		return nil
	end
	return choices[position + 1]
end

-- The display name of a filter value, or "All".
function PetsView.filterName(kind: "rarity" | "type" | "egg", value: string?): string
	if value == nil then
		return "All"
	elseif kind == "rarity" then
		return Config.rarityById[value].name
	elseif kind == "type" then
		return Config.typeById[value].name
	end
	return Config.eggById[value].name
end

local function seenOf(index: any, petId: string): Seen
	local safe: PetIndex.Index = if type(index) == "table" then index else {}
	return {
		normal = PetIndex.hasSeen(safe, petId, nil),
		shiny = knownVariant("shiny") ~= nil and PetIndex.hasSeen(safe, petId, "shiny"),
		golden = knownVariant("golden") ~= nil and PetIndex.hasSeen(safe, petId, "golden"),
	}
end

local function indexTile(index: any, pet: Config.Pet): IndexTile
	local seen = seenOf(index, pet.id)
	return {
		petId = pet.id,
		name = pet.name,
		rarity = pet.rarity,
		rarityName = Config.rarityById[pet.rarity].name,
		type = pet.type,
		egg = pet.egg,
		edition = pet.edition,
		seen = seen,
		seenAny = seen.normal or seen.shiny or seen.golden,
	}
end

-- Every pet in config, one tile each, in config order.
function PetsView.indexTiles(index: any): { IndexTile }
	local tiles: { IndexTile } = {}
	for _, pet in Config.pets do
		table.insert(tiles, indexTile(index, pet))
	end
	return tiles
end

-- The Fruit Edition page: the pets whose config edition is set.
function PetsView.fruitTiles(index: any): { IndexTile }
	local tiles: { IndexTile } = {}
	for _, pet in Config.pets do
		if pet.edition ~= nil then
			table.insert(tiles, indexTile(index, pet))
		end
	end
	return tiles
end

-- Per egg, in config order: how many of its pets are seen as normal hatches
-- (the count that completes it) and the coin bonus a completed egg gives.
function PetsView.eggProgress(index: any): { EggProgress }
	local safe: PetIndex.Index = if type(index) == "table" then index else {}
	local bonus = Config.constants.index_egg_bonus
	local rows: { EggProgress } = {}
	for _, egg in Config.eggs do
		local tiles: { IndexTile } = {}
		local seen = 0
		for _, pet in Config.pets do
			if pet.egg == egg.id then
				local tile = indexTile(safe, pet)
				table.insert(tiles, tile)
				if tile.seen.normal then
					seen += 1
				end
			end
		end
		table.insert(rows, {
			eggId = egg.id,
			name = egg.name,
			seen = seen,
			total = Config.constants.pets_per_egg,
			complete = PetIndex.isEggComplete(safe, egg.id),
			bonus = bonus,
			bonusText = string.format("+%s%% coins", PetsView.number(bonus * 100)),
			tiles = tiles,
		})
	end
	return rows
end

-- The counts on the tab labels: owned pets, index pets seen, fruit pets seen.
function PetsView.tabCounts(
	pets: any,
	index: any
): {
	owned: number,
	seen: number,
	total: number,
	fruitSeen: number,
	fruitTotal: number,
}
	local seen = 0
	for _, tile in PetsView.indexTiles(index) do
		if tile.seenAny then
			seen += 1
		end
	end
	local fruit = PetsView.fruitTiles(index)
	local fruitSeen = 0
	for _, tile in fruit do
		if tile.seenAny then
			fruitSeen += 1
		end
	end
	return {
		owned = #PetsView.tiles(pets, {}),
		seen = seen,
		total = #Config.pets,
		fruitSeen = fruitSeen,
		fruitTotal = #fruit,
	}
end

-- The detail panel of one pet, with its variant's multipliers applied.
function PetsView.detail(petId: string, variant: string?): Detail
	local pet = Config.petById[petId]
	local variantRow = if variant ~= nil then Config.variantById[variant] else nil
	local variantId = if variantRow ~= nil then variantRow.id else nil
	local clickPower = Coins.clickPowerOf({ petId = pet.id, variant = variantId })
	local battleMult = Battle.playerMultiplier(0, variantId)
	local hp = pet.hp * battleMult
	local attack = pet.attack * battleMult
	local petType = Config.typeById[pet.type]
	local special = Config.specialById[pet.special]
	local offType = pet.special_off_type
	local specialText = PetsView.specialText(
		special,
		petType.name,
		if offType ~= nil then Config.typeById[offType].name else nil
	)
	return {
		petId = pet.id,
		name = pet.name,
		variant = variantId,
		variantName = if variantRow ~= nil then variantRow.name else nil,
		typeName = petType.name,
		rarityName = Config.rarityById[pet.rarity].name,
		roleName = Config.roleById[pet.role].name,
		editionName = if pet.edition ~= nil then PetsView.editionName(pet.edition) else nil,
		clickPower = clickPower,
		hp = hp,
		attack = attack,
		speed = pet.speed,
		stats = {
			{ label = "Click Power", value = PetsView.number(clickPower) },
			{ label = "HP", value = PetsView.whole(hp) },
			{ label = "Attack", value = PetsView.whole(attack) },
			{ label = "Speed", value = PetsView.number(pet.speed) },
		},
		moves = {
			{
				name = petType.name .. " Strike",
				kind = "basic",
				text = string.format(
					"basic %s attack with %s power, every turn",
					petType.name,
					PetsView.number(Config.constants.basic_move_power)
				),
			},
			{
				name = special.name,
				kind = "special",
				text = specialText,
			},
		},
	}
end

return PetsView
