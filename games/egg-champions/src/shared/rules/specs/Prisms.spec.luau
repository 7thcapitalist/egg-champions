--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local Prisms = require(script.Parent.Parent.Prisms)
local Profile = require(script.Parent.Parent.Profile)
local Rebirth = require(script.Parent.Parent.Rebirth)
local expect = Runner.expect
return function()
	Runner.describe("saved capture prisms", function()
		Runner.it("preserves earned and paid prisms and receipts through rebirth", function()
			local p: any = Profile.new()
			p.coins = Rebirth.cost(0)
			p.prisms.refined, p.paidPrisms.aurora, p.purchaseReceipts.paid = 7, 3, true
			local reborn: any = Rebirth.apply(p)
			expect(reborn.prisms.refined).toEqual(7)
			expect(reborn.paidPrisms.aurora).toEqual(3)
			expect(reborn.purchaseReceipts.paid).toBeTrue()
		end)
		Runner.it(
			"migrates once without changing prior inventory or duplicating starter stock",
			function()
				local p: any = Profile.new()
				p.version, p.prisms, p.paidPrisms, p.purchaseReceipts = 5, nil, nil, nil
				p.coins = 12345
				local migrated = Profile.migrate(p)
				expect(migrated.prisms.basic).toEqual(1)
				expect(migrated.coins).toEqual(12345)
				migrated.prisms.basic = 0
				expect(Profile.migrate(migrated).prisms.basic).toEqual(0)
				expect(p.version).toEqual(5)
				expect(#Profile.validate(migrated)).toEqual(0)
			end
		)
		Runner.it(
			"refuses malformed earned, paid or receipt data without repairing away purchases",
			function()
				for _, bad in { -1, 0.5, math.huge, 0 / 0, "1" } do
					local p: any = Profile.new()
					p.paidPrisms.aurora = bad
					local _, remaining = Profile.repair(p)
					expect(#remaining > 0).toBeTrue()
				end
				local p = Profile.new()
				p.purchaseReceipts.bad = false
				expect(#Profile.validate(p) > 0).toBeTrue()
			end
		)
		Runner.it("spends earned first, refuses empty and restricted paid stock", function()
			local p = Profile.new()
			p.paidPrisms.basic = 3
			expect(Prisms.spend(p, "basic", true)).toBeTrue()
			expect(p.paidPrisms.basic).toEqual(3)
			expect(Prisms.spend(p, "basic", false)).toBeFalse()
			expect(Prisms.spend(p, "basic", true)).toBeTrue()
			expect(p.paidPrisms.basic).toEqual(2)
			expect(Prisms.spend(p, {}, true)).toBeFalse()
			expect(Prisms.spend(p, "aurora", true)).toBeFalse()
		end)
		Runner.it("buys only the configured coin prism and never accepts client amounts", function()
			local p = Profile.new()
			p.coins = 499
			expect(Prisms.buy(p, "basic")).toBeFalse()
			p.coins = 600
			expect(Prisms.buy(p, "refined")).toBeFalse()
			expect(Prisms.buy(p, {})).toBeFalse()
			expect(Prisms.buy(p, "basic")).toBeTrue()
			expect(p.coins).toEqual(100)
			expect(p.prisms.basic).toEqual(2)
		end)
		Runner.it("grants deterministic packs once across retry and migrated reload", function()
			local p = Profile.new()
			for _, product in Config.prisms do
				local id = "receipt-" .. product.id
				expect(Prisms.receipt(p, product.test_product, id)).toBeTrue()
				expect(Prisms.receipt(p, product.test_product, id)).toBeTrue()
				expect(p.paidPrisms[product.id]).toEqual(product.pack)
				p = Profile.migrate(p)
				expect(Prisms.receipt(p, product.test_product, id)).toBeTrue()
				expect(p.paidPrisms[product.id]).toEqual(product.pack)
			end
			expect(Prisms.receipt(p, -1, "forged")).toBeFalse()
			expect(Prisms.receipt(p, Config.prisms[1].test_product, "")).toBeFalse()
		end)
		Runner.it(
			"makes rarer monsters harder and better prisms more effective, with a cap",
			function()
				for _, world in Config.worlds do
					for _, eggId in world.eggs do
						local previous = math.huge
						for _, rarity in Config.wildRarities do
							for _, pet in Config.pets do
								if pet.egg == eggId and pet.rarity == rarity.id then
									local basic = Prisms.chance(pet.id, "basic")
									expect(basic < previous).toBeTrue()
									previous = basic
									expect(Prisms.chance(pet.id, "refined") >= basic).toBeTrue()
									expect(
										Prisms.chance(pet.id, "aurora")
											>= Prisms.chance(pet.id, "refined")
									).toBeTrue()
									expect(
										Prisms.chance(pet.id, "aurora")
											<= Config.constants.wild_capture_cap
									).toBeTrue()
								end
							end
						end
					end
				end
				expect(Prisms.chance("voltibun", "basic")).toEqual(0.01)
				expect(Prisms.chance("leafpup", "aurora")).toEqual(0.9)
				expect(Prisms.chance("brookdeer", "basic") < Prisms.chance("voltibun", "basic")).toBeTrue()
			end
		)
		Runner.it(
			"keeps each area's local roster, permits rare adjacent visitors and improves rarity odds",
			function()
				for _, world in Config.worlds do
					local localPet = Prisms.spawn(world.id, 0.99, 0, 0, 0)
					expect(Config.petById[localPet].world).toEqual(world.id)
					local visitor = Prisms.spawn(world.id, 0, 0, 0.9999, 0.99)
					expect(Config.petById[visitor].world ~= world.id).toBeTrue()
					expect(Config.petById[visitor].rarity).toEqual("legendary")
				end
				expect(Config.petById[Prisms.spawn("green_meadow", 1, 0, 0.98, 0)].rarity).toEqual(
					"rare"
				)
				expect(Config.petById[Prisms.spawn("ember_volcano", 1, 0, 0.98, 0)].rarity).toEqual(
					"epic"
				)
			end
		)
		Runner.it(
			"drops only at the low configured rate and uses origin-specific quality",
			function()
				expect(Prisms.drop("green_meadow", 0.08, 0)).toEqual(nil)
				expect(Prisms.drop("green_meadow", 0.079, 0.99)).toEqual("refined")
				expect(Prisms.drop("ember_volcano", 0, 0.99)).toEqual("aurora")
				local count = 0
				for i = 0, 9999 do
					if Prisms.drop("green_meadow", i / 10000, 0) then
						count += 1
					end
				end
				expect(count).toEqual(800)
			end
		)
	end)
end
