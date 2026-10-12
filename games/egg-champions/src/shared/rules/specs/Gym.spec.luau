--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local Gym = require(script.Parent.Parent.Gym)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

return function()
	describe("Gym", function()
		it("reads every leader team from tuning/gyms.json as it is", function()
			for _, gym in Config.gyms do
				local team = Gym.leaderTeam(gym.world, gym.target_rebirths)
				expect(#team).toEqual(#gym.leader_team)
				for i, leader in gym.leader_team do
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

		it("rejects an unknown world", function()
			expect(function()
				Gym.leaderTeam("no_such_world", 0)
			end).toThrow("no_such_world")
			expect(function()
				Gym.fee("no_such_world")
			end).toThrow("no_such_world")
		end)
	end)
end
