--!strict
--[[
	ModelTemplates: turns the model table into pet and egg templates.

	The model table is assets/models.json, written by
	factory/tools/build_models.py from the asset manifest and mapped to
	ReplicatedStorage.GameConfig.models. Each entry names a mesh id, a
	texture id and the height the model is scaled to.

	load walks the entries one at a time and, for each, asks the Kit to make
	the MeshPart (up to TRIES tries, waiting RETRY_SECONDS between them), then
	scales it to the entry's height and has the Kit dress it as a template.
	The Kit is every engine call (AssetService, instances, task.wait, warn),
	so this module touches no engine global and the headless tests can run
	the whole loader against fakes. The server's ModelLibrary is the real Kit.

	A failure is logged with the id and leaves that pet or egg on the
	placeholder block; it never raises. Pets that loaded go into
	PetLook.MODEL_IDS, the seam PetVisual reads.

	TRIES and RETRY_SECONDS are loader timing, not game numbers.
]]

local PetLook = require(script.Parent.PetLook)
local Config = require(script.Parent.Parent.Config)

export type Entry = {
	id: string,
	kind: string,
	mesh_id: number,
	texture_id: number,
	height: number,
	parts: { any }?,
	flying: boolean?,
}

export type Table = {
	manifest_sha256: string,
	entries: { Entry },
}

export type Kit = {
	-- Makes the MeshPart for a mesh content id. May error.
	createMeshPart: (meshUri: string) -> any,
	-- The part's current height in studs.
	height: (part: any) -> number,
	-- Sets the texture and flags, multiplies the size by scale, wraps the
	-- part in a Model named by entry.id (with the attachment, when named)
	-- and stores it. May error.
	dress: (part: any, entry: Entry, textureUri: string, scale: number, attachment: string?) -> (),
	wait: (seconds: number) -> (),
	warn: (message: string) -> (),
}

export type Failure = { id: string, reason: string }

export type Report = {
	loaded: { string },
	failed: { Failure },
	-- Pet id to template name, for PetLook.MODEL_IDS.
	modelIds: { [string]: string },
}

local ModelTemplates = {}

ModelTemplates.TRIES = 3
ModelTemplates.RETRY_SECONDS = 1

local petIds: { [string]: boolean } = {}
for _, pet in Config.pets do
	petIds[pet.id] = true
end

function ModelTemplates.assetUri(id: number): string
	return string.format("rbxassetid://%.0f", id)
end

-- The factor that takes a part from meshHeight to target, or nil when either
-- is not a positive finite number.
function ModelTemplates.scale(meshHeight: number, target: number): number?
	local function usable(n: number): boolean
		return n == n and n > 0 and n < math.huge
	end
	if not usable(meshHeight) or not usable(target) then
		return nil
	end
	return target / meshHeight
end

-- The elemental attachment a template carries: the pet type's feature, and
-- none for eggs.
function ModelTemplates.attachmentFor(entry: Entry): string?
	if entry.kind ~= "pet" or not petIds[entry.id] then
		return nil
	end
	return PetLook.resolve(entry.id, nil).feature.attachment
end

-- Pet id to template name for every pet template present, given the names
-- of the templates found. Names that are not pet ids are left out.
function ModelTemplates.seamFrom(names: { string }): { [string]: string }
	local seam: { [string]: string } = {}
	for _, name in names do
		if petIds[name] then
			seam[name] = name
		end
	end
	return seam
end

-- Copies a seam table into PetLook.MODEL_IDS.
function ModelTemplates.applySeam(seam: { [string]: string })
	for petId, modelId in seam do
		PetLook.MODEL_IDS[petId] = modelId
	end
end

local function fail(report: Report, kit: Kit, id: string, reason: string)
	table.insert(report.failed, { id = id, reason = reason })
	kit.warn(string.format("ModelLibrary: %s stays a placeholder: %s", id, reason))
end

function ModelTemplates.load(entries: { Entry }, kit: Kit): Report
	local report: Report = { loaded = {}, failed = {}, modelIds = {} }
	for _, entry in entries do
		local uri = ModelTemplates.assetUri(entry.mesh_id)
		local part: any = nil
		local lastError = "no try made"
		for try = 1, ModelTemplates.TRIES do
			local ok, result = pcall(kit.createMeshPart, uri)
			if ok and result ~= nil then
				part = result
				break
			end
			lastError = if ok then "no part returned" else tostring(result)
			kit.warn(
				string.format(
					"ModelLibrary: %s mesh %s try %d of %d failed: %s",
					entry.id,
					uri,
					try,
					ModelTemplates.TRIES,
					lastError
				)
			)
			if try < ModelTemplates.TRIES then
				kit.wait(ModelTemplates.RETRY_SECONDS)
			end
		end
		if part == nil then
			fail(report, kit, entry.id, lastError)
			continue
		end
		local ok, measured = pcall(kit.height, part)
		local factor = if ok then ModelTemplates.scale(measured, entry.height) else nil
		if factor == nil then
			fail(report, kit, entry.id, "the mesh has no usable height")
			continue
		end
		local dressed, err = pcall(
			kit.dress,
			part,
			entry,
			ModelTemplates.assetUri(entry.texture_id),
			factor,
			ModelTemplates.attachmentFor(entry)
		)
		if not dressed then
			fail(report, kit, entry.id, tostring(err))
			continue
		end
		table.insert(report.loaded, entry.id)
		if entry.kind == "pet" and petIds[entry.id] then
			report.modelIds[entry.id] = entry.id
		end
	end
	return report
end

return ModelTemplates
