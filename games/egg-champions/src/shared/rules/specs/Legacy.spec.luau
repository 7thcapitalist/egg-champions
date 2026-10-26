--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Coins = require(script.Parent.Parent.Coins)
local Team = require(script.Parent.Parent.Team)
local PetsView = require(script.Parent.Parent.Parent.ui.PetsView)

return function()
	Runner.describe("Fixed pet power (retired Legacy scaling)", function()
		Runner.it("keeps every rarity fixed despite a stronger inventory", function()
			local owned = {
				{ uid = "old", petId = "voltibun" },
				{ uid = "epic", petId = "abacatudo", variant = "golden" },
				{ uid = "new", petId = "driftgull" },
				{ uid = "weak", petId = "leafpup" },
			}
			local anchor = Coins.legacyAnchor(owned)
			Runner.expect(anchor).toEqual(Coins.rawPowerOf(owned[1]))
			Runner.expect(Coins.clickPowerOf(owned[1], anchor)).toEqual(Coins.rawPowerOf(owned[1]))
			Runner.expect(Coins.clickPowerOf(owned[2], anchor)).toEqual(Coins.rawPowerOf(owned[2]))
			Runner.expect(Coins.clickPowerOf(owned[4], anchor)).toEqual(Coins.rawPowerOf(owned[4]))
			Runner.expect(Coins.legacyAnchor(owned)).toEqual(anchor)
			Runner.expect(Coins.clickPowerOf(owned[1], 1e20)).toEqual(Coins.rawPowerOf(owned[1]))
			Runner.expect(Coins.clickPowerOf(owned[2], 1e20)).toEqual(Coins.rawPowerOf(owned[2]))
			local best = Team.bestForCoins(owned)
			Runner.expect(best[1]).toEqual("old")
			Runner.expect(best[2]).toEqual("new")
			Runner.expect(best[3]).toEqual("epic")
			local tiles = PetsView.tiles(owned, best)
			for _, tile in tiles do
				Runner.expect(tile.clickPower)
					.toEqual(Coins.clickPowerOf({ petId = tile.petId, variant = tile.variant }, anchor))
			end
			table.insert(owned, { uid = "stronger", petId = "magmaroc", variant = "golden" })
			local updated = PetsView.tiles(owned, best)
			for _, tile in updated do
				Runner.expect(tile.clickPower)
					.toEqual(Coins.rawPowerOf({ petId = tile.petId, variant = tile.variant }))
			end
		end)
		Runner.it("does not reduce a naturally stronger rare pet", function()
			local pet = { petId = "magmaroc", variant = "golden" }
			Runner.expect(Coins.clickPowerOf(pet, 1)).toEqual(Coins.rawPowerOf(pet))
			Runner.expect(Coins.legacyAnchor({})).toEqual(0)
		end)
	end)
end
