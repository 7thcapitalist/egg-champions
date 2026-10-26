--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local Gym = require(script.Parent.Parent.Gym)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

return function()
	describe("Gym", function()
		it("keeps tuned combat fields while assigning matching world pet looks", function()
			for _, gym in Config.gyms do
				local world = Config.worldById[gym.world]
				local team = Gym.leaderTeam(gym.world, gym.target_rebirths)
				expect(#team).toEqual(#gym.leader_team)
				for i, leader in gym.leader_team do
					local looks = {}
					for _, pet in Config.pets do
						if
							pet.world == world.id
							and pet.type == leader.type
							and table.find(world.eggs, pet.egg) ~= nil
						then
							table.insert(looks, pet.id)
						end
					end
					expect(#looks > 0).toBeTrue()
					expect(team[i].pet).toEqual(looks[(i - 1) % #looks + 1])
					expect(team[i].variant).toEqual(nil)
					expect(team[i].offType).toEqual(nil)
					expect(team[i].type).toEqual(leader.type)
					expect(team[i].hp).toEqual(leader.hp)
					expect(team[i].attack).toEqual(leader.attack)
					expect(team[i].speed).toEqual(leader.speed)
					expect(team[i].special).toEqual(leader.special)
				end
			end
		end)

		it("gives leader pets no rebirth bonus", function()
			for _, gym in Config.gyms do
				expect(Gym.leaderTeam(gym.world, 0)).toEqual(Gym.leaderTeam(gym.world, 10))
			end
		end)

		it("matches the leader count in the world config", function()
			for _, world in Config.worlds do
				expect(#Gym.leaderTeam(world.id, 0)).toEqual(world.gym.leader_count)
			end
		end)

		it("reads the fee and retry wait from config", function()
			for _, world in Config.worlds do
				expect(Gym.fee(world.id)).toEqual(world.gym.fee)
			end
			expect(Gym.retrySeconds()).toEqual(Config.constants.gym_retry_seconds)
		end)

		it("builds the reference team from tuning/gyms.json", function()
			for _, gym in Config.gyms do
				local team = Gym.referenceTeam(gym.world)
				expect(#team).toEqual(#gym.reference_team)
				for i, reference in gym.reference_team do
					expect(team[i].pet).toEqual(reference.pet)
					expect(team[i].hp).toEqual(reference.hp)
					expect(team[i].attack).toEqual(reference.attack)
				end
			end
		end)

		it("sets the retry deadline from config on a loss", function()
			local worldId = Config.worlds[1].id
			local waits: Gym.RetryWaits = {}
			Gym.recordLoss(waits, worldId, 1000)
			expect(waits[worldId]).toEqual(1000 + Config.constants.gym_retry_seconds)
			expect(Gym.retryWaitLeft(waits, worldId, 1000)).toEqual(
				Config.constants.gym_retry_seconds
			)
		end)

		it("refuses a start before the deadline and allows one after it", function()
			local worldId = Config.worlds[1].id
			local wait = Config.constants.gym_retry_seconds
			local waits: Gym.RetryWaits = {}
			expect(Gym.canStart(waits, worldId, 1000)).toBeTrue()
			Gym.recordLoss(waits, worldId, 1000)
			expect(Gym.canStart(waits, worldId, 1000)).toBeFalse()
			expect(Gym.canStart(waits, worldId, 1000 + wait - 0.5)).toBeFalse()
			expect(Gym.canStart(waits, worldId, 1000 + wait)).toBeTrue()
			expect(Gym.canStart(waits, worldId, 1000 + wait + 60)).toBeTrue()
			expect(Gym.retryWaitLeft(waits, worldId, 1000 + wait + 60)).toEqual(0)
		end)

		it("keeps each gym's wait separate and clears it on a win", function()
			local first = Config.worlds[1].id
			local waits: Gym.RetryWaits = {}
			Gym.recordLoss(waits, first, 1000)
			if #Config.worlds > 1 then
				expect(Gym.canStart(waits, Config.worlds[2].id, 1000)).toBeTrue()
			end
			Gym.clearWait(waits, first)
			expect(Gym.canStart(waits, first, 1000)).toBeTrue()
		end)

		it("survives a rejoin because the deadline is plain saved data", function()
			local worldId = Config.worlds[1].id
			local waits: Gym.RetryWaits = {}
			Gym.recordLoss(waits, worldId, 1000)
			-- What a save and load gives back: a fresh table with the same numbers.
			local reloaded: Gym.RetryWaits = table.clone(waits)
			expect(Gym.canStart(reloaded, worldId, 1001)).toBeFalse()
		end)

		it("never waits longer than one retry wait, even for a deadline far ahead", function()
			local worldId = Config.worlds[1].id
			local waits: Gym.RetryWaits = { [worldId] = 1e12 }
			expect(Gym.retryWaitLeft(waits, worldId, 1000)).toEqual(
				Config.constants.gym_retry_seconds
			)
		end)

		it("rejects an unknown world", function()
			expect(function()
				Gym.leaderTeam("no_such_world", 0)
			end).toThrow("no_such_world")
			expect(function()
				Gym.fee("no_such_world")
			end).toThrow("no_such_world")
		end)

		it("sets the same deadline when a session ends by leaving as after a loss", function()
			local worldId = Config.worlds[1].id
			local lost: Gym.RetryWaits = {}
			local left: Gym.RetryWaits = {}
			Gym.recordEnd(lost, worldId, Gym.endings.loss, 1000)
			Gym.recordLeave(left, worldId, 1000)
			expect(left[worldId]).toEqual(lost[worldId])
			expect(left[worldId]).toEqual(1000 + Config.constants.gym_retry_seconds)
			expect(Gym.canStart(left, worldId, 1001)).toBeFalse()
		end)

		it("treats giving up like a loss and a win as clearing the wait", function()
			local worldId = Config.worlds[1].id
			local waits: Gym.RetryWaits = {}
			Gym.recordEnd(waits, worldId, Gym.endings.gaveUp, 1000)
			expect(waits[worldId]).toEqual(1000 + Config.constants.gym_retry_seconds)
			Gym.recordEnd(waits, worldId, Gym.endings.win, 1001)
			expect(waits[worldId]).toEqual(nil)
		end)

		it("refuses a start for the wait with the whole seconds left", function()
			local worldId = Config.worlds[1].id
			local wait = Config.constants.gym_retry_seconds
			local waits: Gym.RetryWaits = {}
			local reason, seconds = Gym.retryRefusal(waits, worldId, 1000)
			expect(reason).toEqual(nil)
			expect(seconds).toEqual(nil)
			Gym.recordLeave(waits, worldId, 1000)
			reason, seconds = Gym.retryRefusal(waits, worldId, 1000)
			expect(reason).toEqual("retry_wait")
			expect(seconds).toEqual(wait)
			reason, seconds = Gym.retryRefusal(waits, worldId, 1000 + 10.25)
			expect(seconds).toEqual(math.ceil(wait - 10.25))
			reason, seconds = Gym.retryRefusal(waits, worldId, 1000 + wait - 0.1)
			expect(reason).toEqual("retry_wait")
			expect(seconds).toEqual(1)
			reason, seconds = Gym.retryRefusal(waits, worldId, 1000 + wait)
			expect(reason).toEqual(nil)
			expect(seconds).toEqual(nil)
		end)
	end)
end
