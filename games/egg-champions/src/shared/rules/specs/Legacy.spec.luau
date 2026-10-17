--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Coins = require(script.Parent.Parent.Coins)
local Team = require(script.Parent.Parent.Team)
local Config = require(script.Parent.Parent.Parent.Config)
local PetsView = require(script.Parent.Parent.Parent.ui.PetsView)

return function()
	Runner.describe("Legacy Power", function()
		Runner.it("keeps old rares useful without recursive or variant inflation", function()
			local owned = {
				{ uid = "old", petId = "voltibun" },
				{ uid = "epic", petId = "abacatudo", variant = "golden" },
				{ uid = "new", petId = "driftgull" },
				{ uid = "weak", petId = "leafpup" },
			}
			local anchor = Coins.legacyAnchor(owned)
			Runner.expect(anchor).toEqual(Coins.rawPowerOf(owned[3]))
			Runner.expect(Coins.clickPowerOf(owned[1], anchor))
				.toEqual(anchor * Config.constants.legacy_legendary_floor)
			Runner.expect(Coins.clickPowerOf(owned[2], anchor))
				.toEqual(anchor * Config.constants.legacy_epic_floor)
			Runner.expect(Coins.clickPowerOf(owned[4], anchor)).toEqual(Coins.rawPowerOf(owned[4]))
			Runner.expect(Coins.legacyAnchor(owned)).toEqual(anchor)
			local best = Team.bestForCoins(owned)
			Runner.expect(best[1]).toEqual("new")
			Runner.expect(best[2]).toEqual("old")
			Runner.expect(best[3]).toEqual("epic")
			local tiles = PetsView.tiles(owned, best)
			for _, tile in tiles do
				Runner.expect(tile.clickPower)
					.toEqual(Coins.clickPowerOf({ petId = tile.petId, variant = tile.variant }, anchor))
			end
		end)
		Runner.it("does not reduce a naturally stronger rare pet", function()
			local pet = { petId = "magmaroc", variant = "golden" }
			Runner.expect(Coins.clickPowerOf(pet, 1)).toEqual(Coins.rawPowerOf(pet))
			Runner.expect(Coins.legacyAnchor({})).toEqual(0)
		end)
	end)
end
