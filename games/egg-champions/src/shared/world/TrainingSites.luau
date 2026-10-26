--!strict
-- Geometry shared by the scenery reservation, server props and guide.
local TrainingSites = {}
TrainingSites.TAG = "TrainingGround"
TrainingSites.WORLD_ATTRIBUTE = "TrainingWorld"
TrainingSites.TARGET_ATTRIBUTE = "TrainingTarget"
TrainingSites.START_ATTRIBUTE = "TrainingStartedAt"
TrainingSites.PULSE_ATTRIBUTE = "TrainingPulseAt"
TrainingSites.CLEAR_RADIUS = 16

function TrainingSites.position(origin: { x: number, y: number, z: number })
	return { x = origin.x - 26, y = origin.y, z = origin.z - 4 }
end

function TrainingSites.modelName(worldId: string): string
	return "Training_" .. worldId
end

return TrainingSites
