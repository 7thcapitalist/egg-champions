--!strict
--[[
	The hatch reveal: what it shows for each pet, when it ends (a tap on the
	button or SECONDS), and when the tutorial may close the egg shop.
]]

local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local EggShopView = require(script.Parent.Parent.EggShopView)
local HatchReveal = require(script.Parent.Parent.HatchReveal)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

return function()
	describe("HatchReveal timing", function()
		it("stays for SECONDS when nobody taps", function()
			expect(HatchReveal.SECONDS).toEqual(3)
			expect(HatchReveal.ended(10, 10, false)).toBeFalse()
			expect(HatchReveal.ended(10, 12.9, false)).toBeFalse()
			expect(HatchReveal.ended(10, 13, false)).toBeTrue()
			expect(HatchReveal.ended(10, 20, false)).toBeTrue()
		end)

		it("ends at once when the player taps the button", function()
			expect(HatchReveal.BUTTON).toEqual("Nice!")
			expect(HatchReveal.ended(10, 10, true)).toBeTrue()
			expect(HatchReveal.ended(10, 11, true)).toBeTrue()
		end)

		it("counts the time left down to zero, never below", function()
			expect(HatchReveal.remaining(10, 10)).toEqual(3)
			expect(HatchReveal.remaining(10, 12)).toEqual(1)
			expect(HatchReveal.remaining(10, 30)).toEqual(0)
		end)

		it("closes the tutorial's egg shop only after the reveal ends", function()
			-- The hatch step ended while the hatch still plays: wait.
			expect(HatchReveal.shopCloses(true, true, false)).toBeFalse()
			-- The reveal is over: close.
			expect(HatchReveal.shopCloses(true, false, false)).toBeTrue()
			-- Nothing waiting, or back on the hatch step: stay open.
			expect(HatchReveal.shopCloses(false, false, false)).toBeFalse()
			expect(HatchReveal.shopCloses(true, false, true)).toBeFalse()
		end)
	end)

	describe("HatchReveal entries", function()
		local pet = Config.pets[1]
		local variant = Config.variants[1]

		it("shows name, rarity, badge and Click +N from the server reply", function()
			local reply = {
				ok = true,
				pets = {
					{ petId = pet.id, newInIndex = true, clickPower = 12 },
					{ petId = pet.id, variant = variant.id, clickPower = 2500 },
				},
			}
			local entries = HatchReveal.entries(EggShopView.hatchLines(reply))
			expect(#entries).toEqual(2)
			expect(entries[1].name).toEqual(pet.name)
			expect(entries[1].rarity).toEqual(pet.rarity)
			expect(entries[1].rarityName).toEqual(Config.rarityById[pet.rarity].name)
			expect(entries[1].badge).toEqual(nil)
			expect(entries[1].clickText).toEqual("Click +12")
			expect(entries[2].badge).toEqual(variant.name)
			expect(entries[2].variant).toEqual(variant.id)
			expect(entries[2].clickText).toEqual("Click +2.5K")
		end)

		it("leaves out Click +N when the server sent no Click Power", function()
			local entries = HatchReveal.entries(EggShopView.hatchLines({
				pets = { { petId = pet.id }, { petId = pet.id, clickPower = 0 / 0 } },
			}))
			expect(entries[1].clickText).toEqual(nil)
			expect(entries[2].clickText).toEqual(nil)
		end)

		it("badges only the Shiny and Golden variants from config", function()
			for _, v in Config.variants do
				local entries = HatchReveal.entries(EggShopView.hatchLines({
					pets = { { petId = pet.id, variant = v.id, clickPower = 1 } },
				}))
				expect(entries[1].badge).toEqual(v.name)
			end
		end)
	end)
end
