"""Execute the actual purchase callback; never call Roblox or buy anything."""
from pathlib import Path
import json
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "factory/tools"))
import run_tests


class PrismServiceRuntimeTests(unittest.TestCase):
    def test_policy_receipts_failed_commits_retry_departure_and_unknown_products(self):
        game_dir = ROOT / "games/egg-champions"
        config = {"prisms": json.loads((game_dir / "config/prisms.json").read_text())}
        fixture = r'''
local function node(name)
 return setmetatable({name=name,WaitForChild=function(_,n)return node(n)end},{__index=function(_,n)return node(n)end})
end
local config=__CONFIG__
local script={Parent=node("Services")}
local callbacks={}
local players={}
local function event(name)return {Connect=function(_,fn)callbacks[name]=fn end}end
players.PlayerAdded,players.PlayerRemoving=event("add"),event("remove")
local player={UserId=42}
function players:GetPlayers()return {player}end
function players:GetPlayerByUserId(id)return if id==42 then player else nil end
local market={}
local restricted,policyError,commit,mode,pushes=false,false,false,"datastore",0
local profile={prisms={basic=1,refined=0,aurora=0},paidPrisms={basic=0,refined=0,aurora=0},purchaseReceipts={}}
local saved=nil
local flushHook=nil
local services={Players=players,MarketplaceService=market,ReplicatedStorage=node("RS"),PolicyService={GetPolicyInfoForPlayerAsync=function()
 if policyError then error("policy unavailable") end
 return {ArePaidRandomItemsRestricted=restricted}
end}}
local game={GameId=10769019206,GetService=function(_,k)return services[k]end}
local task={spawn=function(fn,...)fn(...)end}
local Enum={ProductPurchaseDecision={NotProcessedYet="pending",PurchaseGranted="granted"}}
local derived,invokes={},{}
local deps={Config=config,Remotes={names={BuyPrism="BuyPrism"}},Profiles={
 get=function()return profile end,persistenceMode=function()return mode end,
 flush=function()
  if flushHook then flushHook() end
  if commit then
   saved={balance=profile.paidPrisms.basic,receipt=profile.purchaseReceipts.purchase}
  end
  return commit
 end},Guard={push=function()pushes+=1 end,addDerived=function(k,f)derived[k]=f end,onInvoke=function(k,f)invokes[k]=f end}}
local require=function(m)return assert(deps[m.name],m.name)end
deps.Prisms=(function()local script={Parent={Parent={Config=node("Config")}}}
__PRISMS__
end)()
local service=(function()
__SERVICE__
end)()
service.start()
local receipt={PlayerId=42,ProductId=config.prisms[1].test_product,PurchaseId="purchase"}
assert(service.paidAllowed(player))
assert(derived.prisms(player,profile).canPurchase)
assert(market.ProcessReceipt(receipt)=="pending")
assert(profile.paidPrisms.basic==10 and saved==nil,"failed commit must not acknowledge")
assert(market.ProcessReceipt(receipt)=="pending" and profile.paidPrisms.basic==10,"retry must not regrant")
commit=true
flushHook=function()
 assert(market.ProcessReceipt(receipt)=="pending","concurrent callback must wait")
end
assert(market.ProcessReceipt(receipt)=="granted")
assert(saved.balance==10 and saved.receipt,"grant plus marker must precede acknowledgement")
flushHook=nil
assert(market.ProcessReceipt(receipt)=="granted" and profile.paidPrisms.basic==10)
receipt.ProductId=-1; assert(market.ProcessReceipt(receipt)=="pending")
receipt.ProductId=config.prisms[1].test_product
mode="temporary"; assert(market.ProcessReceipt(receipt)=="pending")
assert(not derived.prisms(player,profile).canPurchase)
mode="datastore"; restricted=true; callbacks.add(player)
assert(not service.paidAllowed(player) and derived.prisms(player,profile).items[1].count==1)
restricted=false; policyError=true; callbacks.add(player)
assert(not service.paidAllowed(player))
policyError=false; callbacks.add(player)
receipt.PlayerId=999; assert(market.ProcessReceipt(receipt)=="pending")
receipt.PlayerId=42; game.GameId=1
assert(market.ProcessReceipt(receipt)=="pending" and not service.paidAllowed(player))
assert(derived.prisms(player,profile).items[1].productId==0)
assert(market.PromptProductPurchaseFinished==nil,"purchase-finished events must never grant currency")
'''
        fixture = fixture.replace("__CONFIG__", run_tests.lua_value(config, "purchase fixture"))
        fixture = fixture.replace("__PRISMS__", (game_dir / "src/shared/rules/Prisms.luau").read_text())
        fixture = fixture.replace("__SERVICE__", (game_dir / "src/server/Services/PrismService.luau").read_text())
        name, _ = run_tests.pinned_luau()
        tool = run_tests.find_luau(name)
        with tempfile.TemporaryDirectory(dir=ROOT) as folder:
            path = Path(folder) / "prisms.luau"
            path.write_text(fixture)
            result = subprocess.run([str(tool), str(path)], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
