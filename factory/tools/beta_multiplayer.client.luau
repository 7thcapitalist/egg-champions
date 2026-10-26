--!strict
-- Explicitly mapped only by build_beta.py; never part of the shipping game.
assert(game:GetService("RunService"):IsStudio() and game.PlaceId == 0, "local unpublished QA only")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
assert(ReplicatedStorage:GetAttribute("BetaQA") == true, "QA project guard missing")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local driver = ReplicatedStorage:WaitForChild("BetaDriver", 30) :: RemoteFunction
local ready = ReplicatedStorage:WaitForChild("BetaReady", 30) :: RemoteEvent
assert(driver ~= nil and ready ~= nil, "beta server driver unavailable")
local folder = ReplicatedStorage:WaitForChild(Remotes.FOLDER, 30)
assert(folder ~= nil, "game remotes unavailable")
local allowed = {
	[Remotes.names.PayGymFee] = true,
	[Remotes.names.StartBattle] = true,
	[Remotes.names.BattleMove] = true,
	[Remotes.names.GiveUp] = true,
	[Remotes.names.Equip] = true,
}
driver.OnClientInvoke = function(name: any, args: any): any
	assert(type(name) == "string" and allowed[name] == true, "unsupported beta action")
	assert(type(args) == "table" and #args <= 3, "bad beta arguments")
	local remote = folder:FindFirstChild(name)
	assert(remote ~= nil and remote:IsA("RemoteFunction"), "remote not ready")
	return (remote :: RemoteFunction):InvokeServer(table.unpack(args))
end
ready:FireServer()
