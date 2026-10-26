"""Actual pass cache retains known entitlements while final saves yield."""
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "factory/tools"))
import run_tests

class PassServiceRuntimeTests(unittest.TestCase):
    def test_departure_preserves_bonuses_for_pending_final_save(self):
        body = (ROOT / "games/egg-champions/src/server/Services/PassService.luau").read_text()
        body = re.sub(r'\["2x_coins"\]\s*=\s*\d+', '["2x_coins"] = 11', body)
        prefix = r''' 
local function node(name)
 return setmetatable({name=name,WaitForChild=function(self,n)return node(n)end}, {__index=function(_,n)return node(n)end})
end
local function event() return {Connect=function(self,fn) self.callback=fn end} end
local players={PlayerAdded=event(),PlayerRemoving=event(),GetPlayers=function()return {}end}
local market={PromptGamePassPurchaseFinished=event(),UserOwnsGamePassAsync=function()return false end}
local services={Players=players,MarketplaceService=market,ReplicatedStorage=node("ReplicatedStorage"),
 RunService={IsStudio=function()return false end},ServerScriptService={GetAttribute=function()return false end}}
local game={PlaceId=123,GetService=function(self,name)return services[name]end}
local task={spawn=function()end}
local script={Parent={Parent=node("Server")}}
local effects={HANDLED={"2x_coins","lucky_eggs","triple_hatch","auto_click"},
 effective=function(owned,disabled)return if disabled then {} else table.clone(owned or {})end,
 playtestNoPasses=function()return false end}
local require=function(module)
 if module.name=="PassEffects" then return effects end
 if module.name=="Config" then return {passes={}} end
 if module.name=="Guard" then return {addDerived=function()end,push=function()end} end
 if module.name=="Analytics" then return {track=function()end} end
 if module.name=="Profile" then return {} end
 error("unexpected dependency "..module.name)
end
local PassService=(function()
'''
        suffix = r'''
end)()
PassService.start()
local player={Parent=players,UserId=1,Name="test"}
players.PlayerAdded.callback(player)
market.PromptGamePassPurchaseFinished.callback(player,11,true)
assert(PassService.owns(player,"2x_coins"))
-- The profile writer may yield after PlayerRemoving; ownership must survive.
players.PlayerRemoving.callback(player); player.Parent=nil
assert(PassService.owns(player,"2x_coins"))
local other={Parent=players,UserId=2,Name="other"}
players.PlayerAdded.callback(other)
assert(not PassService.owns(other,"2x_coins"))
'''
        name, _ = run_tests.pinned_luau()
        tool = run_tests.find_luau(name)
        self.assertIsNotNone(tool)
        with tempfile.TemporaryDirectory(dir=ROOT) as temp:
            path=Path(temp)/"passes.luau"
            path.write_text(prefix+body+suffix)
            result=subprocess.run([str(tool),str(path)],capture_output=True,text=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
