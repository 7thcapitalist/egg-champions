--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Rewards = require(script.Parent.Parent.CollectionRewards)
local Config = require(script.Parent.Parent.Parent.Config)
local expect = Runner.expect
return function()
	Runner.describe("permanent index milestones", function()
		Runner.it(
			"grants world/full bonuses from normal collection only, without claims",
			function()
				local index: any = {}
				expect(Rewards.summary(index).extraMultiplier).toEqual(1)
				for _, pet in Config.pets do
					index[pet.id] = { golden = true, shiny = true }
				end
				expect(Rewards.summary(index).worlds).toEqual(0)
				for _, pet in Config.pets do
					if pet.world == Config.worlds[1].id then
						index[pet.id].normal = true
					end
				end
				local first = Rewards.summary(index)
				expect(first.eggs).toEqual(2)
				expect(first.worlds).toEqual(1)
				expect(first.extraMultiplier).toEqual(1.1)
				for _, pet in Config.pets do
					index[pet.id].normal = true
				end
				local full = Rewards.summary(index)
				expect(full.full).toBeTrue()
				expect(full.worlds).toEqual(3)
				expect(full.extraMultiplier).toEqual(1.5)
				expect(Rewards.summary(index).bonusPercent).toBeCloseTo(140, 0.00001)
			end
		)
		Runner.it(
			"keeps every older Epic above the next egg low rarities, and Legendary above Epic",
			function()
				for i = 1, #Config.eggs - 1 do
					local previous, following = Config.eggs[i].id, Config.eggs[i + 1].id
					for _, older in Config.pets do
						if older.egg ~= previous then
							continue
						end
						for _, newer in Config.pets do
							if newer.egg ~= following then
								continue
							end
							if
								(
									older.rarity == "epic"
									and (newer.rarity == "common" or newer.rarity == "uncommon")
								)
								or (older.rarity == "legendary" and newer.rarity == "epic")
							then
								for _, field in { "click_power", "hp", "attack" } do
									expect((older :: any)[field] > (newer :: any)[field]).toBeTrue()
								end
							end
						end
					end
				end
			end
		)
	end)
end
