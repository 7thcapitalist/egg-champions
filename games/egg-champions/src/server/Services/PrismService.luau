--!strict
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local MarketplaceService = game:GetService("MarketplaceService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Prisms = require(Shared.rules.Prisms)
local Profiles = require(script.Parent.Parent.Profiles)
local Guard = require(script.Parent.Parent.Guard)
local Remotes = require(Shared.Remotes)
local PrismService = {}
local allowed: { [Player]: boolean } = {}
local processing: { [number]: boolean } = {}
-- TEST developer products must never be offered in a different universe.
local TEST_UNIVERSE = 10769019206
function PrismService.paidAllowed(player: Player): boolean
	return game.GameId == TEST_UNIVERSE and allowed[player] == true
end
function PrismService.start()
	local function policy(player: Player)
		local ok, info = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end)
		allowed[player] = ok and info.ArePaidRandomItemsRestricted == false
		Guard.push(player)
	end
	Players.PlayerAdded:Connect(function(player)
		task.spawn(policy, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(policy, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		allowed[player] = nil
	end)
	Guard.addDerived("prisms", function(player: Player, profile: any)
		local paid = PrismService.paidAllowed(player)
		local rows = {}
		for _, p in Config.prisms do
			table.insert(rows, {
				id = p.id,
				count = Prisms.count(profile, p.id, paid),
				earned = profile.prisms[p.id],
				paid = profile.paidPrisms[p.id],
				productId = if game.GameId == TEST_UNIVERSE then p.test_product else 0,
			})
		end
		return {
			items = rows,
			paidAllowed = paid,
			canPurchase = paid and Profiles.persistenceMode(player) == "datastore",
		}
	end)
	Guard.onInvoke(Remotes.names.BuyPrism, function(_player: Player, profile: any, id: any)
		if not Prisms.buy(profile, id) then
			return false, "prism_unavailable"
		end
		return true, { prismId = id }
	end)
	MarketplaceService.ProcessReceipt = function(receipt)
		local pending = Enum.ProductPurchaseDecision.NotProcessedYet
		if game.GameId ~= TEST_UNIVERSE or processing[receipt.PlayerId] then
			return pending
		end
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		if not player or Profiles.persistenceMode(player) ~= "datastore" then
			return pending
		end
		local profile = Profiles.get(player)
		if not profile then
			return pending
		end
		processing[receipt.PlayerId] = true
		local ok, committed = pcall(function()
			if not Prisms.receipt(profile, receipt.ProductId, receipt.PurchaseId) then
				return false
			end
			return Profiles.flush(player)
		end)
		processing[receipt.PlayerId] = nil
		if ok and committed then
			Guard.push(player)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return pending
	end
end
return PrismService
