--!strict
--[[
	ModelLibrary: builds the pet and egg templates at server start.

	For each entry in ReplicatedStorage.GameConfig.models (assets/models.json,
	from factory/tools/build_models.py), ModelTemplates.load calls
	AssetService:CreateMeshPartAsync in a pcall, one entry at a time, with
	retries. This module is its engine Kit: it sets TextureID and the part
	flags, scales Size so the height matches the entry, wraps the part in a
	Model named by id with the pet's elemental attachment, and parents it to
	ReplicatedStorage.PetModels. PetVisual clones from there.

	Every failure is logged with the id and leaves the placeholder block.
	Pets that loaded go into PetLook.MODEL_IDS on the server; clients fill
	their own copy from the PetModels folder.
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ModelTemplates = require(Shared:WaitForChild("visual"):WaitForChild("ModelTemplates"))

local ModelLibrary = {}

ModelLibrary.FOLDER = "PetModels"

local function folder(): Folder
	local found = ReplicatedStorage:FindFirstChild(ModelLibrary.FOLDER)
	if found ~= nil and found:IsA("Folder") then
		return found
	end
	local made = Instance.new("Folder")
	made.Name = ModelLibrary.FOLDER
	made.Parent = ReplicatedStorage
	return made
end

local function kit(target: Folder): ModelTemplates.Kit
	return {
		createMeshPart = function(meshUri: string): any
			return AssetService:CreateMeshPartAsync(meshUri)
		end,
		height = function(part: any): number
			return (part :: MeshPart).Size.Y
		end,
		dress = function(
			part: any,
			entry: ModelTemplates.Entry,
			textureUri: string,
			scale: number,
			attachment: string?
		)
			local mesh = part :: MeshPart
			mesh.Name = "Mesh"
			mesh.TextureID = textureUri
			mesh.Anchored = true
			mesh.CanCollide = false
			mesh.CanQuery = false
			mesh.CanTouch = false
			mesh.CastShadow = true
			mesh.Size = mesh.Size * scale
			mesh.CFrame = CFrame.new()

			local model = Instance.new("Model")
			model.Name = entry.id
			model:SetAttribute("Kind", entry.kind)
			mesh.Parent = model
			model.PrimaryPart = mesh
			if attachment ~= nil then
				-- Same spot PetVisual uses: the top back of the part.
				local point = Instance.new("Attachment")
				point.Name = attachment
				point.Position = Vector3.new(0, mesh.Size.Y / 2, mesh.Size.Z / 2)
				point.Parent = mesh
			end
			local old = target:FindFirstChild(entry.id)
			if old ~= nil then
				old:Destroy()
			end
			model.Parent = target
		end,
		wait = function(seconds: number)
			task.wait(seconds)
		end,
		warn = function(message: string)
			warn(message)
		end,
	}
end

-- Builds every template. Yields while meshes load, so call it in its own
-- thread. Returns the load report.
function ModelLibrary.start(): ModelTemplates.Report
	local source = ReplicatedStorage:WaitForChild("GameConfig"):FindFirstChild("models")
	if source == nil or not source:IsA("ModuleScript") then
		warn("ModelLibrary: GameConfig.models is missing; every pet and egg stays a placeholder")
		return { loaded = {}, failed = {}, modelIds = {} }
	end
	local data = require(source) :: ModelTemplates.Table
	local report = ModelTemplates.load(data.entries, kit(folder()))
	ModelTemplates.applySeam(report.modelIds)
	print(
		string.format(
			"ModelLibrary: %d of %d models loaded, %d left as placeholders",
			#report.loaded,
			#data.entries,
			#report.failed
		)
	)
	return report
end

return ModelLibrary
