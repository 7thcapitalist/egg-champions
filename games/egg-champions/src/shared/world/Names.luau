--!strict
--[[
	Names: the instance names and tags the server's world and the client's
	scripts agree on. Both sides read them from here, so a rename can not
	leave one side looking for something that is no longer there.
]]

local Names = {}

-- The tag on every egg that turns on its stand. The server tags, the client
-- spins.
Names.SPINNING_EGG_TAG = "SpinningEgg"

-- A gym building's Model is named this prefix plus its world id.
Names.GYM_MODEL_PREFIX = "Gym_"

-- The name of the gym building Model for a world.
function Names.gymModel(worldId: string): string
	return Names.GYM_MODEL_PREFIX .. worldId
end

return table.freeze(Names)
