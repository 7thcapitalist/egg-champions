--!strict
-- Reconstructs generated mesh pieces in their recorded model-space poses.
local AssetService = game:GetService("AssetService")
local SegmentedTemplate = {}

local function roleFor(name: string): string?
	local lower = string.lower(name)
	if string.find(lower, "tail") then
		return "tail"
	end
	if lower == "wings" then
		return "wings"
	end
	if lower == "front legs" or lower == "limbs" then
		return "bounce"
	end
	if lower == "eyestalks" or lower == "antennae" then
		return "feelers"
	end
	if string.find(lower, "wing") or string.find(lower, "flipper") then
		return if string.find(lower, "left") then "wingL" else "wingR"
	end
	if string.find(lower, "leg") or string.find(lower, "arm") then
		local left = string.find(lower, "left") ~= nil
		local rear = string.find(lower, "rear") ~= nil or string.find(lower, "hind") ~= nil
		return if left ~= rear then "legA" else "legB"
	end
	return nil
end

function SegmentedTemplate.create(entry: any): Model
	local model = Instance.new("Model")
	model.Name = entry.id
	model:SetAttribute("Kind", entry.kind)
	model:SetAttribute("VisualStyle", "FacetedCollector")
	model:SetAttribute("Flying", entry.flying == true)
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.05, 0.05, 0.05)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Parent = model
	model.PrimaryPart = root
	local ok, err = pcall(function()
		for _, piece in entry.parts do
			local mesh: MeshPart? = nil
			local lastError: any = nil
			for attempt = 1, 3 do
				local loaded, result = pcall(function()
					return AssetService:CreateMeshPartAsync(
						"rbxassetid://" .. tostring(piece.mesh_id)
					)
				end)
				if loaded then
					mesh = result
					break
				end
				lastError = result
				if attempt < 3 then
					task.wait(1)
				end
			end
			assert(mesh ~= nil, tostring(lastError))
			local part = mesh :: MeshPart
			part.Name = piece.name
			part.TextureID = "rbxassetid://" .. tostring(piece.texture_id)
			part.Size = Vector3.new(table.unpack(piece.size))
			part.CFrame = CFrame.new(table.unpack(piece.cframe))
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Material = Enum.Material.SmoothPlastic
			part.Parent = model
			local role = roleFor(piece.name)
			if role ~= nil then
				local pivot = part.Position
				if role == "legA" or role == "legB" then
					pivot += Vector3.new(0, part.Size.Y * 0.4, 0)
				elseif role == "tail" then
					pivot -= Vector3.new(0, 0, part.Size.Z * 0.4)
				else
					pivot = Vector3.new(pivot.X * 0.3, pivot.Y, pivot.Z)
				end
				part:SetAttribute("MotionRole", role)
				part:SetAttribute("MotionPivot", pivot)
			end
		end
		local _, bounds = model:GetBoundingBox()
		assert(bounds.Y > 0, "segmented model has no height")
		model:ScaleTo(entry.height / bounds.Y)
	end)
	if not ok then
		model:Destroy()
		error(err)
	end
	return model
end

return SegmentedTemplate
