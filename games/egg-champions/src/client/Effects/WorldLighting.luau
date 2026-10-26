--!strict
--[[
	WorldLighting: each world's sky, haze and color grade, applied when the
	player enters it.

	Every half second it finds which island the character is on
	(Scenery.islandAt, from the same Layout plan the server builds) and, when
	that changes, fades Lighting to the world's look from shared/world/
	WorldLook: Atmosphere, Sky, ColorCorrection, a subtle Bloom, the clock
	time and the water color. Lighting changes made here stay on this client.

	The timings below are display timing, not game numbers.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local worldFolder = Shared:WaitForChild("world")
local Layout = require(worldFolder:WaitForChild("Layout"))
local Scenery = require(worldFolder:WaitForChild("Scenery"))
local WorldLook = require(worldFolder:WaitForChild("WorldLook"))

local CHECK_SECONDS = 0.5
local FADE_SECONDS = 2

local WorldLighting = {}

local function rgb(c: WorldLook.RGB): Color3
	return Color3.fromRGB(c.r, c.g, c.b)
end

-- The one instance of a class this module owns under Lighting.
local function owned(className: string, name: string): Instance
	local found = Lighting:FindFirstChild(name)
	if found ~= nil and found.ClassName == className then
		return found
	end
	local made = Instance.new(className)
	made.Name = name
	made.Parent = Lighting
	return made
end

local function fade(instance: Instance, seconds: number, goal: { [string]: any })
	if seconds <= 0 then
		for key, value in goal do
			(instance :: any)[key] = value
		end
		return
	end
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	TweenService:Create(instance, info, goal):Play()
end

-- Applies a world's look, fading over `seconds` (0 sets it at once).
function WorldLighting.apply(look: WorldLook.Look, seconds: number)
	local l = look.lighting
	fade(Lighting, seconds, {
		ClockTime = l.clockTime,
		Brightness = l.brightness,
		Ambient = rgb(l.ambient),
		OutdoorAmbient = rgb(l.outdoorAmbient),
	})
	local atmosphere = owned("Atmosphere", "WorldAtmosphere") :: Atmosphere
	fade(atmosphere, seconds, {
		Density = l.atmosphere.density,
		Offset = l.atmosphere.offset,
		Haze = l.atmosphere.haze,
		Glare = l.atmosphere.glare,
		Color = rgb(l.atmosphere.color),
		Decay = rgb(l.atmosphere.decay),
	})
	local sky = owned("Sky", "WorldSky") :: Sky
	sky.StarCount = l.sky.starCount
	sky.SunAngularSize = l.sky.sunSize
	sky.MoonAngularSize = l.sky.moonSize
	sky.CelestialBodiesShown = true
	local grade = owned("ColorCorrectionEffect", "WorldColor") :: ColorCorrectionEffect
	fade(grade, seconds, {
		Brightness = l.colorCorrection.brightness,
		Contrast = l.colorCorrection.contrast,
		Saturation = l.colorCorrection.saturation,
		TintColor = rgb(l.colorCorrection.tint),
	})
	local bloom = owned("BloomEffect", "WorldBloom") :: BloomEffect
	fade(bloom, seconds, {
		Intensity = l.bloom.intensity,
		Size = l.bloom.size,
		Threshold = l.bloom.threshold,
	})
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if terrain ~= nil then
		fade(terrain, seconds, {
			WaterColor = rgb(l.water.color),
			WaterTransparency = l.water.transparency,
			WaterWaveSize = l.water.waveSize,
			WaterReflectance = l.water.reflectance,
		})
	end
end

-- Each biome owns its horizon. Local visibility never changes collision or progress.
function WorldLighting.showWorld(worldId: string)
	for _, world in Workspace:GetChildren() do
		if world:IsA("Folder") and string.sub(world.Name, 1, 6) == "World_" then
			local visible = world.Name == "World_" .. worldId
			for _, item in world:GetDescendants() do
				if item:IsA("BasePart") then
					item.LocalTransparencyModifier = if visible then 0 else 1
				elseif item:IsA("BillboardGui") or item:IsA("SurfaceGui") then
					item.Enabled = visible
				end
			end
		end
	end
end

function WorldLighting.mount()
	local plan = Layout.plan()
	local looks: { [string]: WorldLook.Look } = {}
	for _, island in plan.islands do
		looks[island.worldId] = WorldLook.forWorld(island.worldId, island.environment)
	end
	local player = Players.LocalPlayer
	local current: string? = nil
	-- Start on the first world's look, so the sky is right before spawning.
	local first = plan.islands[1]
	if first ~= nil then
		current = first.worldId
		WorldLighting.apply(looks[first.worldId], 0)
		WorldLighting.showWorld(first.worldId)
	end
	Workspace.ChildAdded:Connect(function(child)
		if child:IsA("Folder") and string.sub(child.Name, 1, 6) == "World_" and current then
			WorldLighting.showWorld(current)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(CHECK_SECONDS)
			local character = player.Character
			local root = if character ~= nil
				then character:FindFirstChild("HumanoidRootPart")
				else nil
			if root ~= nil and root:IsA("BasePart") then
				local here = Scenery.islandAt(plan, root.Position.X, root.Position.Z)
				if here ~= nil and here ~= current and looks[here] ~= nil then
					current = here
					WorldLighting.showWorld(here)
					WorldLighting.apply(looks[here], FADE_SECONDS)
				end
			end
		end
	end)
end

return WorldLighting
