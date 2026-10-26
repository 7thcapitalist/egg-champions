--!strict
local Config = require(script.Parent.Parent.Config)
local C = Config.constants
local Prisms = {}
function Prisms.definition(id: any): any
	for _, p in Config.prisms do
		if p.id == id then
			return p
		end
	end
	return nil
end
function Prisms.initial(starter: boolean): { [string]: number }
	local stock = {}
	for _, p in Config.prisms do
		stock[p.id] = if starter then p.starter else 0
	end
	return stock
end
function Prisms.rarity(id: string): any
	for _, r in Config.wildRarities do
		if r.id == id then
			return r
		end
	end
	error("Unknown wild rarity " .. id)
end
function Prisms.area(id: string): any
	for _, a in Config.wildAreas do
		if a.id == id then
			return a
		end
	end
	error("Unknown wild area " .. id)
end
function Prisms.eggFactor(pet: any): number
	return if pet.egg == Config.worldById[pet.world].eggs[1] then 1 else C.wild_second_egg_factor
end
function Prisms.chance(petId: string, prismId: string): number
	local p = Prisms.definition(prismId)
	if not p then
		return 0
	end
	local pet = Config.petById[petId]
	return math.min(
		C.wild_capture_cap,
		Prisms.rarity(pet.rarity).capture_chance
			* p.multiplier
			/ (
				(1 + C.wild_origin_penalty * (Config.worldById[pet.world].index - 1))
				* Prisms.eggFactor(pet)
			)
	)
end
function Prisms.strength(petId: string): number
	local pet = Config.petById[petId]
	return Prisms.rarity(pet.rarity).strength
		* (1 + C.wild_origin_strength * (Config.worldById[pet.world].index - 1))
		* Prisms.eggFactor(pet)
end
function Prisms.count(profile: any, id: string, paidAllowed: boolean): number
	return ((profile.prisms or {})[id] or 0)
		+ (if paidAllowed then ((profile.paidPrisms or {})[id] or 0) else 0)
end
function Prisms.spend(profile: any, id: any, paidAllowed: boolean): boolean
	if not Prisms.definition(id) then
		return false
	end
	for _, stock in { profile.prisms or {}, if paidAllowed then profile.paidPrisms or {} else {} } do
		if (stock[id] or 0) > 0 then
			stock[id] -= 1
			return true
		end
	end
	return false
end
function Prisms.buy(profile: any, id: any): boolean
	local p = Prisms.definition(id)
	if not p or p.coin_price <= 0 or profile.coins < p.coin_price then
		return false
	end
	profile.coins -= p.coin_price
	profile.prisms[id] += 1
	return true
end
-- Grant and receipt marker are saved in the same profile write. Replay only flushes.
function Prisms.receipt(profile: any, productId: any, purchaseId: any): boolean
	if type(purchaseId) ~= "string" or #purchaseId == 0 then
		return false
	end
	local product = nil
	for _, p in Config.prisms do
		if p.test_product == productId then
			product = p
			break
		end
	end
	if not product then
		return false
	end
	if not profile.purchaseReceipts[purchaseId] then
		profile.paidPrisms[product.id] += product.pack
		profile.purchaseReceipts[purchaseId] = true
	end
	return true
end
local function weighted(ids: { string }, weights: any, roll: number): string
	local cumulative = 0
	for _, id in ids do
		cumulative += weights[id]
		if roll < cumulative then
			return id
		end
	end
	return ids[#ids]
end
function Prisms.drop(worldId: string, roll: number, quality: number): string?
	if roll >= C.wild_prism_drop_chance then
		return nil
	end
	return weighted({ "basic", "refined", "aurora" }, Prisms.area(worldId).drops, quality)
end
-- Inject independent rolls to make every area boundary testable, without client RNG.
function Prisms.spawn(
	worldId: string,
	visitorRoll: number,
	directionRoll: number,
	rarityRoll: number,
	speciesRoll: number
): string
	local index = Config.worldById[worldId].index
	local origin = index
	if visitorRoll < C.wild_visitor_chance then
		local neighbors = {}
		if index > 1 then
			table.insert(neighbors, index - 1)
		end
		if index < #Config.worlds then
			table.insert(neighbors, index + 1)
		end
		origin = neighbors[math.min(#neighbors, math.floor(directionRoll * #neighbors) + 1)]
	end
	local rarity = weighted(
		{ "common", "uncommon", "rare", "epic", "legendary" },
		Prisms.area(worldId).rarities,
		rarityRoll
	)
	local pool = {}
	for _, pet in Config.pets do
		if pet.world == Config.worldByIndex[origin].id and pet.rarity == rarity then
			table.insert(pool, pet.id)
		end
	end
	return pool[math.min(#pool, math.floor(speciesRoll * #pool) + 1)]
end
return Prisms
