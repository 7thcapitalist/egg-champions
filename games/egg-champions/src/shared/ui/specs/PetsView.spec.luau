--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local Coins = require(script.Parent.Parent.Parent.rules.Coins)
local Battle = require(script.Parent.Parent.Parent.rules.Battle)
local PetsView = require(script.Parent.Parent.PetsView)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

local function petOf(rarityOrder: number, eggPosition: number): Config.Pet
	local egg = Config.eggs[eggPosition]
	for _, pet in Config.pets do
		if pet.egg == egg.id and Config.rarityById[pet.rarity].order == rarityOrder then
			return pet
		end
	end
	error("no pet for that rarity and egg")
end

local function lowestOrder(): number
	local lowest = math.huge
	for _, rarity in Config.rarities do
		lowest = math.min(lowest, rarity.order)
	end
	return lowest
end

-- A small owned list across eggs, rarities and variants.
local function sampleOwned(): { PetsView.OwnedPet }
	local low = lowestOrder()
	return {
		{ uid = "u1", petId = petOf(low, 1).id },
		{ uid = "u2", petId = petOf(low + 1, 1).id },
		{ uid = "u3", petId = petOf(low + 2, 2).id },
		{ uid = "u4", petId = petOf(low, 1).id, variant = Config.variants[1].id },
		{ uid = "u5", petId = petOf(low + 4, #Config.eggs).id },
		{ uid = "u6", petId = petOf(low + 3, 3).id },
	}
end

return function()
	describe("PetsView", function()
		it("makes one tile per owned pet with rarity, variant and equipped state", function()
			local tiles = PetsView.tiles(sampleOwned(), { "u2" })
			expect(#tiles).toEqual(6)
			for _, tile in tiles do
				expect(tile.equipped).toEqual(tile.uid == "u2")
				expect(tile.rarityName).toEqual(Config.rarityById[tile.rarity].name)
			end
			local shiny = tiles[4]
			expect(shiny.variant).toEqual(Config.variants[1].id)
			expect(shiny.variantName).toEqual(Config.variants[1].name)
			expect(shiny.clickPower).toEqual(Coins.clickPowerOf({
				petId = shiny.petId,
				variant = shiny.variant,
			}))
		end)

		it("skips owned entries the client does not recognise", function()
			local tiles = PetsView.tiles({
				{ uid = "a", petId = "nobody" },
				{ petId = Config.pets[1].id },
				"junk",
				{ uid = "b", petId = Config.pets[1].id, variant = "plaid" },
			}, nil)
			expect(#tiles).toEqual(1)
			expect(tiles[1].uid).toEqual("b")
			expect(tiles[1].variant).toEqual(nil)
			expect(#PetsView.tiles(nil, nil)).toEqual(0)
		end)

		it("sorts by highest Click Power first by default", function()
			local arranged = PetsView.arrange(PetsView.tiles(sampleOwned(), {}))
			expect(#arranged).toEqual(6)
			for position = 2, #arranged do
				expect(arranged[position - 1].clickPower >= arranged[position].clickPower).toBeTrue()
			end
			expect(PetsView.DEFAULT_SORT).toEqual("power")
		end)

		it("sorts by rarity, rarest first", function()
			local arranged = PetsView.arrange(PetsView.tiles(sampleOwned(), {}), "rarity")
			for position = 2, #arranged do
				local before = Config.rarityById[arranged[position - 1].rarity].order
				local after = Config.rarityById[arranged[position].rarity].order
				expect(before >= after).toBeTrue()
			end
		end)

		it("sorts by type and by egg in config order", function()
			local tiles = PetsView.tiles(sampleOwned(), {})
			local function rank(list: { any }, id: string): number
				for position, row in list do
					if row.id == id then
						return position
					end
				end
				return 0
			end
			local byType = PetsView.arrange(tiles, "type")
			for position = 2, #byType do
				expect(
					rank(Config.types, byType[position - 1].type)
						<= rank(Config.types, byType[position].type)
				).toBeTrue()
			end
			local byEgg = PetsView.arrange(tiles, "egg")
			for position = 2, #byEgg do
				expect(
					rank(Config.eggs, byEgg[position - 1].egg)
						<= rank(Config.eggs, byEgg[position].egg)
				).toBeTrue()
			end
		end)

		it("filters by rarity, type and egg, and leaves its input alone", function()
			local tiles = PetsView.tiles(sampleOwned(), {})
			local first = tiles[1]
			local byRarity = PetsView.arrange(tiles, nil, { rarity = first.rarity })
			for _, tile in byRarity do
				expect(tile.rarity).toEqual(first.rarity)
			end
			expect(#byRarity).toEqual(2)
			local byEgg = PetsView.arrange(tiles, nil, { egg = Config.eggs[1].id })
			expect(#byEgg).toEqual(3)
			local byType = PetsView.arrange(tiles, nil, { type = first.type })
			for _, tile in byType do
				expect(tile.type).toEqual(first.type)
			end
			local none =
				PetsView.arrange(tiles, nil, { egg = Config.eggs[1].id, rarity = "nothing" })
			expect(#none).toEqual(0)
			expect(tiles[1].uid).toEqual("u1")
			expect(#tiles).toEqual(6)
		end)

		it("cycles sorts and filters through every choice and back", function()
			local sort: PetsView.SortKey = PetsView.DEFAULT_SORT
			for _ = 1, #PetsView.SORTS do
				sort = PetsView.nextSort(sort)
			end
			expect(sort).toEqual(PetsView.DEFAULT_SORT)
			local value: string? = nil
			local seen = 0
			repeat
				value = PetsView.nextFilter("egg", value)
				if value ~= nil then
					seen += 1
				end
			until value == nil
			expect(seen).toEqual(#Config.eggs)
			expect(PetsView.filterName("rarity", nil)).toEqual("All")
		end)

		it("lists exactly the 30 pets in config on the Index tab", function()
			local tiles = PetsView.indexTiles({})
			expect(#tiles).toEqual(30)
			expect(#tiles).toEqual(#Config.pets)
			local ids: { [string]: boolean } = {}
			for position, tile in tiles do
				expect(tile.petId).toEqual(Config.pets[position].id)
				expect(ids[tile.petId] == nil).toBeTrue()
				ids[tile.petId] = true
				expect(tile.seenAny).toBeFalse()
			end
		end)

		it("lists exactly the pets whose edition is set on the Fruit Edition tab", function()
			local expected: { string } = {}
			for _, pet in Config.pets do
				if pet.edition ~= nil then
					table.insert(expected, pet.id)
				end
			end
			expect(#expected > 0).toBeTrue()
			local tiles = PetsView.fruitTiles({})
			expect(#tiles).toEqual(#expected)
			for position, tile in tiles do
				expect(tile.petId).toEqual(expected[position])
				expect(tile.edition ~= nil).toBeTrue()
			end
		end)

		it("tracks normal, shiny and golden separately in the Index", function()
			local pet = Config.pets[1]
			local index = { [pet.id] = { shiny = true } }
			local tile = PetsView.indexTiles(index)[1]
			expect(tile.seen.normal).toBeFalse()
			expect(tile.seen.shiny).toBeTrue()
			expect(tile.seen.golden).toBeFalse()
			expect(tile.seenAny).toBeTrue()
		end)

		it("counts egg completion from normal hatches and shows the config bonus", function()
			local egg = Config.eggs[1]
			local index: { [string]: any } = {}
			local rows = PetsView.eggProgress(index)
			expect(#rows).toEqual(#Config.eggs)
			expect(rows[1].seen).toEqual(0)
			expect(rows[1].complete).toBeFalse()
			expect(rows[1].bonus).toEqual(Config.constants.index_egg_bonus)
			for _, pet in Config.pets do
				if pet.egg == egg.id then
					index[pet.id] = { normal = true }
				end
			end
			rows = PetsView.eggProgress(index)
			expect(rows[1].seen).toEqual(Config.constants.pets_per_egg)
			expect(rows[1].total).toEqual(Config.constants.pets_per_egg)
			expect(rows[1].complete).toBeTrue()
			expect(rows[2].complete).toBeFalse()
			expect(#rows[1].tiles).toEqual(Config.constants.pets_per_egg)
		end)

		it("shows a pet's stats with the variant multipliers the game uses", function()
			local pet = Config.pets[1]
			local base = PetsView.detail(pet.id, nil)
			expect(base.clickPower).toEqual(pet.click_power)
			expect(base.hp).toEqual(pet.hp)
			expect(base.attack).toEqual(pet.attack)
			expect(base.speed).toEqual(pet.speed)
			for _, variant in Config.variants do
				local shown = PetsView.detail(pet.id, variant.id)
				expect(shown.clickPower).toEqual(
					Coins.clickPowerOf({ petId = pet.id, variant = variant.id })
				)
				local mult = Battle.playerMultiplier(0, variant.id)
				expect(shown.hp).toBeCloseTo(pet.hp * mult, 1e-9)
				expect(shown.attack).toBeCloseTo(pet.attack * mult, 1e-9)
				expect(shown.variantName).toEqual(variant.name)
			end
		end)

		it("shows both moves with the special's effect text from config", function()
			for _, pet in Config.pets do
				local detail = PetsView.detail(pet.id, nil)
				expect(#detail.moves).toEqual(2)
				expect(detail.moves[1].kind).toEqual("basic")
				local special = Config.specialById[pet.special]
				expect(detail.moves[2].name).toEqual(special.name)
				expect(detail.moves[2].text).toEqual(
					PetsView.specialText(
						special,
						Config.typeById[pet.type].name,
						if pet.special_off_type ~= nil
							then Config.typeById[pet.special_off_type].name
							else nil
					)
				)
				expect(detail.typeName).toEqual(Config.typeById[pet.type].name)
				expect(detail.roleName).toEqual(Config.roleById[pet.role].name)
				expect(detail.editionName ~= nil).toEqual(pet.edition ~= nil)
			end
		end)

		it("shows special moves with their real numbers from config", function()
			local cooldown = tostring(Config.constants.special_cooldown_turns)
			local function has(text: string, part: string): boolean
				return string.find(text, part, 1, true) ~= nil
			end
			for _, special in Config.specials do
				local text = PetsView.specialText(special, "Fire", "Water")
				expect(has(text, "after " .. cooldown .. " turns")).toBeTrue()
				if special.kind == "heal" then
					expect(
						has(
							text,
							"restores " .. PetsView.number(special.value * 100) .. "% of max HP"
						)
					).toBeTrue()
				elseif special.kind == "guard" or special.kind == "speed" then
					expect(has(text, PetsView.number(special.value * 100) .. "%")).toBeTrue()
				elseif special.kind == "drain" then
					expect(has(text, PetsView.number(special.power) .. " power")).toBeTrue()
					expect(has(text, PetsView.number(special.value * 100) .. "%")).toBeTrue()
				elseif special.kind == "attack" then
					expect(
						has(text, "Fire attack with " .. PetsView.number(special.power) .. " power")
					).toBeTrue()
				elseif special.kind == "offtype" then
					expect(
						has(
							text,
							"Water attack with " .. PetsView.number(special.power) .. " power"
						)
					).toBeTrue()
				end
			end
			local heal = Config.specialById.heal
			if heal ~= nil and heal.value == 0.3 then
				expect(PetsView.specialText(heal, "Fire", nil)).toEqual(
					"restores 30% of max HP. Ready again after " .. cooldown .. " turns"
				)
			end
		end)

		it("labels a tile's Click Power", function()
			expect(PetsView.clickText(3)).toEqual("Click +3")
			expect(PetsView.clickText(2.5)).toEqual("Click +2.5")
			local pet = Config.pets[1]
			local tiles = PetsView.tiles({ { uid = "a", petId = pet.id } }, {})
			expect(tiles[1].clickPowerText).toEqual(
				"Click +" .. PetsView.number(Coins.clickPowerOf({ petId = pet.id, variant = nil }))
			)
		end)

		it("turns server refusals into readable messages", function()
			expect(string.find(PetsView.reasonText("team_full"), "full", 1, true) ~= nil).toBeTrue()
			expect(type(PetsView.reasonText("something_new"))).toEqual("string")
		end)

		it("counts tabs from the profile", function()
			local pet = Config.pets[1]
			local counts = PetsView.tabCounts(sampleOwned(), { [pet.id] = { normal = true } })
			expect(counts.owned).toEqual(6)
			expect(counts.seen).toEqual(1)
			expect(counts.total).toEqual(#Config.pets)
		end)

		it("formats numbers without trailing zeros", function()
			expect(PetsView.number(2)).toEqual("2")
			expect(PetsView.number(2.4)).toEqual("2.4")
			expect(PetsView.number(58.8)).toEqual("58.8")
			expect(PetsView.number(1500)).toEqual("1,500")
		end)
	end)
	describe("PetsView with few pets", function()
		it("keeps collection tabs accessible even before the first hatch", function()
			for count = 0, PetsView.FULL_SCREEN_PETS - 1 do
				local parts = PetsView.screenParts(count)
				expect(parts.filters).toBeFalse()
				expect(table.concat(parts.tabs, ",")).toEqual("pets,index,fruit")
			end
			local full = PetsView.screenParts(PetsView.FULL_SCREEN_PETS)
			expect(full.filters).toBeTrue()
			expect(table.concat(full.tabs, ",")).toEqual("pets,index,fruit")
		end)
	end)

	describe("Inventory search and refresh", function()
		it("finds names, types and variants without case sensitivity or pattern parsing", function()
			local tiles = PetsView.tiles(sampleOwned(), {})
			local name = tiles[1].name
			local found =
				PetsView.arrange(tiles, nil, { query = "  " .. string.upper(name) .. "  " })
			expect(#found >= 1).toBeTrue()
			for _, tile in found do
				expect(tile.name).toEqual(name)
			end
			local variantName = Config.variants[1].name
			local variants = PetsView.arrange(tiles, nil, { query = variantName })
			expect(#variants).toEqual(1)
			expect(variants[1].uid).toEqual("u4")
			expect(#PetsView.arrange(tiles, nil, { query = "[" })).toEqual(0)
		end)

		it("combines search with filters and leaves the inventory untouched", function()
			local tiles = PetsView.tiles(sampleOwned(), {})
			local wanted = tiles[3]
			local found =
				PetsView.arrange(tiles, nil, { query = wanted.typeName, rarity = wanted.rarity })
			expect(#found >= 1).toBeTrue()
			for _, tile in found do
				expect(tile.rarity).toEqual(wanted.rarity)
			end
			expect(#tiles).toEqual(6)
		end)

		it("ignores coin and playtime pushes but detects team and discoveries", function()
			local profile =
				{ pets = sampleOwned(), team = {}, index = {}, coins = 50, playSeconds = 0 }
			local before = PetsView.signature(profile)
			profile.coins = 5000
			profile.playSeconds = 100
			expect(PetsView.signature(profile)).toEqual(before)
			table.insert(profile.team, "u1")
			local equipped = PetsView.signature(profile)
			expect(equipped == before).toBeFalse()
			profile.index[Config.pets[1].id] = { golden = true }
			expect(PetsView.signature(profile) == equipped).toBeFalse()
		end)
	end)

	describe("PetsView stats", function()
		it("shows HP and Attack as whole numbers", function()
			expect(PetsView.whole(37.5)).toEqual("38")
			expect(PetsView.whole(12.2)).toEqual("12")
			expect(PetsView.whole(1500.4)).toEqual("1,500")
			for _, pet in Config.pets do
				for _, variant in Config.variants do
					local detail = PetsView.detail(pet.id, variant.id)
					for _, stat in detail.stats do
						if stat.label == "HP" or stat.label == "Attack" then
							expect(string.find(stat.value, ".", 1, true) == nil).toBeTrue()
						end
					end
				end
			end
		end)
	end)
	describe("PetsView beginner detail", function()
		it("is a beginner while the tutorial runs or with fewer than 4 pets", function()
			local full = PetsView.FULL_SCREEN_PETS
			expect(full).toEqual(4)
			expect(PetsView.beginner(0, false)).toBeTrue()
			expect(PetsView.beginner(full - 1, false)).toBeTrue()
			expect(PetsView.beginner(full, false)).toBeFalse()
			expect(PetsView.beginner(full + 5, true)).toBeTrue()
		end)

		it("shows only Click Power until Battle stats is opened", function()
			local pet = Config.pets[1]
			local info = PetsView.detail(pet.id, nil)
			local closed = PetsView.detailParts(info, true, false)
			expect(#closed.stats).toEqual(1)
			expect(closed.stats[1].label).toEqual("Click Power")
			expect(closed.moves).toBeFalse()
			expect(closed.toggle).toEqual(PetsView.BATTLE_TOGGLE.closed)
			expect(closed.typeLine).toEqual(info.typeName)
			local open = PetsView.detailParts(info, true, true)
			expect(#open.stats).toEqual(#info.stats)
			expect(open.moves).toBeTrue()
			expect(open.toggle).toEqual(PetsView.BATTLE_TOGGLE.open)
		end)

		it("shows everything with no toggle to a player past the beginning", function()
			local pet = Config.pets[1]
			local info = PetsView.detail(pet.id, nil)
			local parts = PetsView.detailParts(info, false, false)
			expect(#parts.stats).toEqual(#info.stats)
			expect(parts.moves).toBeTrue()
			expect(parts.toggle).toEqual(nil)
		end)
	end)
end
