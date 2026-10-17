--!strict
-- Bounded local environment animation, culled outside the current island.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Ambience = {}
function Ambience.mount()
	local rotors: { [Model]: CFrame } = {}
	local waves: { [BasePart]: CFrame } = {}
	local emitters: { [ParticleEmitter]: boolean } = {}
	local function rotor(i: Instance)
		if i:IsA("Model") then
			rotors[i] = i:GetPivot()
		end
	end
	local function wave(i: Instance)
		if i:IsA("BasePart") then
			waves[i] = i.CFrame
		end
	end
	local function emitter(i: Instance)
		if i:IsA("ParticleEmitter") then
			emitters[i] = true
		end
	end
	for _, i in CollectionService:GetTagged("WorldRotor") do
		rotor(i)
	end
	for _, i in CollectionService:GetTagged("WorldWave") do
		wave(i)
	end
	for _, i in CollectionService:GetTagged("WorldAmbient") do
		emitter(i)
	end
	CollectionService:GetInstanceAddedSignal("WorldRotor"):Connect(rotor)
	CollectionService:GetInstanceAddedSignal("WorldWave"):Connect(wave)
	CollectionService:GetInstanceAddedSignal("WorldAmbient"):Connect(emitter)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 1 / 30 then
			return
		end
		elapsed = 0
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local eye = camera.CFrame.Position
		local now = os.clock()
		for model, base in rotors do
			if model.Parent == nil then
				rotors[model] = nil
			elseif (base.Position - eye).Magnitude < 220 then
				model:PivotTo(base * CFrame.Angles(0, 0, now * 0.32))
			end
		end
		for p, base in waves do
			if p.Parent == nil then
				waves[p] = nil
			elseif (base.Position - eye).Magnitude < 220 then
				p.CFrame = base
					* CFrame.new(
						0,
						math.sin(now * 1.4 + base.Position.Z) * 0.12,
						math.sin(now * 0.6) * 2
					)
				p.Transparency = 0.35 + math.sin(now + base.Position.Z) * 0.2
			end
		end
		for fx in emitters do
			local p = fx.Parent
			if p == nil then
				emitters[fx] = nil
			elseif p:IsA("BasePart") then
				fx.Enabled = (p.Position - eye).Magnitude < 160
			end
		end
	end)
end
return Ambience
