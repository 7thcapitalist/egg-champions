--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local Team = require(script.Parent.Parent.Team)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

-- Uids "pet1" to "petN" for N owned pets.
local function ownedUids(count: number): { string }
	local uids = {}
	for i = 1, count do
		table.insert(uids, "pet" .. i)
	end
	return uids
end

-- Equips the first `count` owned uids, failing loudly if any is refused.
local function fill(owned: { string }, count: number): { string }
	local team: { string } = {}
	for i = 1, count do
		local nextTeam, reason = Team.equip(team, owned, owned[i])
		assert(nextTeam, "equip refused: " .. tostring(reason))
		team = nextTeam
	end
	return team
end

return function()
	describe("Team", function()
		it("takes its size from config", function()
			expect(Team.maxSize()).toEqual(Config.constants.team_size)
		end)

		it("equips owned pets up to the team size", function()
			local owned = ownedUids(Team.maxSize())
			local team = fill(owned, Team.maxSize())
			expect(team).toEqual(owned)
		end)

		it("rejects a pet past the team size and leaves the team unchanged", function()
			local owned = ownedUids(Team.maxSize() + 1)
			local team = fill(owned, Team.maxSize())
			local before = table.clone(team)
			local extra = owned[Team.maxSize() + 1]

			local ok, why = Team.canEquip(team, owned, extra)
			expect(ok).toBeFalse()
			expect(why).toEqual(Team.reasons.teamFull)

			local nextTeam, reason = Team.equip(team, owned, extra)
			expect(nextTeam).toEqual(nil)
			expect(reason).toEqual(Team.reasons.teamFull)
			expect(team).toEqual(before)
		end)

		it("rejects a pet already on the team", function()
			local owned = ownedUids(Team.maxSize())
			local team = fill(owned, 1)
			local nextTeam, reason = Team.equip(team, owned, owned[1])
			expect(nextTeam).toEqual(nil)
			expect(reason).toEqual(Team.reasons.alreadyEquipped)
			expect(team).toEqual({ owned[1] })
		end)

		it("rejects a pet the player does not own", function()
			local owned = ownedUids(Team.maxSize())
			local nextTeam, reason = Team.equip({}, owned, "someone_elses_pet")
			expect(nextTeam).toEqual(nil)
			expect(reason).toEqual(Team.reasons.notOwned)
		end)

		it("gives each rejection a distinct reason", function()
			local reasons = Team.reasons
			local seen: { [string]: boolean } = {}
			for _, reason in
				{ reasons.notOwned, reasons.alreadyEquipped, reasons.teamFull, reasons.notEquipped }
			do
				expect(seen[reason] == nil).toBeTrue()
				seen[reason] = true
			end
		end)

		it("unequips a pet and makes room again", function()
			local owned = ownedUids(Team.maxSize() + 1)
			local team = fill(owned, Team.maxSize())
			local nextTeam = Team.unequip(team, owned[1])
			assert(nextTeam, "unequip refused")
			expect(#nextTeam).toEqual(Team.maxSize() - 1)
			expect(Team.isEquipped(nextTeam, owned[1])).toBeFalse()
			expect(#team).toEqual(Team.maxSize())

			local refilled = Team.equip(nextTeam, owned, owned[Team.maxSize() + 1])
			expect(refilled ~= nil).toBeTrue()
		end)

		it("refuses to unequip a pet that is not equipped", function()
			local nextTeam, reason = Team.unequip({}, "pet1")
			expect(nextTeam).toEqual(nil)
			expect(reason).toEqual(Team.reasons.notEquipped)
		end)

		it("equips the strongest owned variants for coins with stable ties", function()
			local id = Config.pets[1].id
			local pets: { Team.OwnedPet } = {
				{ uid = "normal-a", petId = id },
				{ uid = "shiny", petId = id, variant = "shiny" },
				{ uid = "normal-b", petId = id },
				{ uid = "golden", petId = id, variant = "golden" },
			}
			local before = table.clone(pets)
			expect(Team.bestForCoins(pets)).toEqual({ "golden", "shiny", "normal-a" })
			expect(pets).toEqual(before)
		end)

		it("chooses a different team for battle than for coins", function()
			local pets: { Team.OwnedPet } = {
				{ uid = "worker", petId = "puddlet" },
				{ uid = "fighter", petId = "emberkit" },
				{ uid = "balanced", petId = "leafpup" },
				{ uid = "shiny-worker", petId = "puddlet", variant = "shiny" },
			}
			expect(Team.bestForCoins(pets)).toEqual({ "shiny-worker", "worker", "fighter" })
			expect(Team.bestForBattle(pets, 0)).toEqual({ "fighter", "balanced", "shiny-worker" })
		end)

		it("breaks equal battle strength by Speed then inventory order", function()
			local pets: { Team.OwnedPet } = {
				{ uid = "slow", petId = "cinderhog" },
				{ uid = "fast", petId = "bananao" },
				{ uid = "fast-again", petId = "bananao" },
			}
			expect(Team.bestForBattle(pets, 2)).toEqual({ "fast", "fast-again", "slow" })
		end)

		it("returns a new empty team for unequip all", function()
			local current = { "pet1", "pet2" }
			expect(Team.unequipAll()).toEqual({})
			expect(current).toEqual({ "pet1", "pet2" })
			expect(Team.bestForCoins({})).toEqual({})
		end)
	end)
end
