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
-- CreateMeshPartAsync yields on asset retrieval. A small worker pool lets
-- independent pets become available without waiting for earlier retries.
ModelLibrary.LOAD_WORKERS = 4

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
	local results: { [number]: ModelTemplates.Report } = {}
	local cursor = 0
	local finished = 0
	local seen: { [string]: boolean } = {}
	local uniqueIds = true
	for _, entry in data.entries do
		if seen[entry.id] then
			uniqueIds = false
			break
		end
		seen[entry.id] = true
	end
	-- Duplicate template names replace one another. Preserve their input
	-- order if a future generated table contains any.
	local workerCount = math.min(if uniqueIds then ModelLibrary.LOAD_WORKERS else 1, #data.entries)
	local done = Instance.new("BindableEvent")
	local loaderKit = kit(folder())
	for _ = 1, workerCount do
		task.spawn(function()
			while true do
				-- No yield between taking an index and advancing the cursor.
				cursor += 1
				local index = cursor
				local entry = data.entries[index]
				if entry == nil then
					break
				end
				local ok, loaded = pcall(ModelTemplates.load, { entry }, loaderKit)
				local partial: ModelTemplates.Report
				if ok then
					partial = loaded :: ModelTemplates.Report
				else
					local reason = tostring(loaded)
					warn(
						string.format("ModelLibrary: %s stays a placeholder: %s", entry.id, reason)
					)
					partial = {
						loaded = {},
						failed = { { id = entry.id, reason = reason } },
						modelIds = {},
					}
				end
				results[index] = partial
				-- The template is already parented by dress. Make the server's
				-- PetVisual seam available as soon as this entry succeeds too.
				ModelTemplates.applySeam(partial.modelIds)
			end
			finished += 1
			if finished == workerCount then
				done:Fire()
			end
		end)
	end
	if finished < workerCount then
		done.Event:Wait()
	end
	done:Destroy()
	local report: ModelTemplates.Report = { loaded = {}, failed = {}, modelIds = {} }
	for index = 1, #data.entries do
		local partial = results[index]
		for _, id in partial.loaded do
			table.insert(report.loaded, id)
		end
		for _, failure in partial.failed do
			table.insert(report.failed, failure)
		end
		for petId, modelId in partial.modelIds do
			report.modelIds[petId] = modelId
		end
	end
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
