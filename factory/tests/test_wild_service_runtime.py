"""Exercise real wild + training services and rules against an isolated engine fixture."""
from pathlib import Path
import json
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "factory/tools"))
import run_tests


class WildServiceRuntimeTests(unittest.TestCase):
    def test_training_capture_reward_replays_exit_and_boost_expiry(self):
        game_dir = ROOT / "games/egg-champions"
        config = {}
        for name in ("constants", "pets", "worlds", "variants", "eggs", "prisms", "wild_rarities", "wild_areas"):
            config[name] = json.loads((game_dir / "config" / (name + ".json")).read_text())
        for name in ("pets", "worlds", "variants", "eggs"):
            config[{"pets": "petById", "worlds": "worldById", "variants": "variantById", "eggs": "eggById"}[name]] = {v["id"]: v for v in config[name]}
        config["wildRarities"] = config["wild_rarities"]
        config["wildAreas"] = config["wild_areas"]
        config["worldByIndex"] = {v["index"]: v for v in config["worlds"]}
        fixture = r''' 
local function node(name)
 return setmetatable({name=name,WaitForChild=function(_,n)return node(n)end},{__index=function(_,n)return node(n)end})
end
local now, guid, roll, battling = 0, 0, 0.1, false
local attrs={}
local root={Position={X=0,Y=3,Z=0},IsA=function()return true end}
local humanoid={Health=100}
local player={Parent={},Character={FindFirstChild=function()return root end,FindFirstChildOfClass=function()return humanoid end},
 SetAttribute=function(_,k,v)attrs[k]=v end}
local profile={coins=0,pets={},team={},index={},unlocked=1,prisms={basic=2,refined=0,aurora=0},paidPrisms={basic=0,refined=0,aurora=0}}
local callbacks={}
local removed={Connect=function(_,fn)table.insert(callbacks,fn)end}
local vector={__kind="Vector3",X=0,Y=0,Z=0}
local site={IsDescendantOf=function()return true end,GetAttribute=function(_,k)return ({TrainingPosition=vector,WorldId="green_meadow",WorldIndex=1})[k]end}
local workspace={GetServerTimeNow=function()return now end}
local services={Players={PlayerRemoving=removed},ReplicatedStorage=node("RS"),CollectionService={GetTagged=function()return {site}end},Workspace=workspace,
 HttpService={GenerateGUID=function()guid+=1;return tostring(guid)end}}
local game={GetService=function(_,k)return services[k]end}
local typeof=function(v)return if type(v)=="table" and v.__kind then v.__kind else type(v)end
local script={Parent=node("Services")}
local task={spawn=function()end}
local Random={new=function()return {NextInteger=function()return 1 end,NextNumber=function()return roll end}end}
local config=__CONFIG__
config.worldByIndex={}
for _,world in config.worlds do config.worldByIndex[world.index]=world end
local invokes,derived={},{}
local deps={PrismService={paidAllowed=function()return false end},TutorialService={note=function()end},Config=config,Profiles={get=function()return profile end},
 Progression={worldUnlocked=function(p,i)return p.unlocked>=i end},
 Passes={owned=function()return {}end},PassEffects={autoClick=function()return false end},
 GymService={isBattling=function()return battling end},
 ClickService={coinsPerClick=function()return 10 end,train=function(_,p,hits)p.coins+=hits*10 end},
 Remotes={names={WildAction="WildAction"}},Guard={addDerived=function(k,fn)derived[k]=fn end,onInvoke=function(k,fn)invokes[k]=fn end}}
local require=function(module)return assert(deps[module.name],module.name)end
local scriptRule={Parent={Parent={Config=node("Config")},Prisms=node("Prisms"),Coins=node("Coins"),Progression=node("Progression")}}
deps.Coins=(function()local script=scriptRule
__COINS__
end)()
deps.PetIndex=(function()local script=scriptRule
__INDEX__
end)()
deps.Training=(function()local script=scriptRule
__TRAINING__
end)()
deps.TrainingSites=(function()
__SITES__
end)()
deps.Prisms=(function()local script=scriptRule
__PRISMS__
end)()
deps.WildEncounter=(function()local script=scriptRule
__WILD__
end)()
deps.WildService=(function()
__SERVICE__
end)()
local Training=(function()
__TRAININGSERVICE__
end)()
Training.start()
local function step(t)now=t;Training.step(player,t)end
local function view()return derived.wild(player,profile)end
local function action(e,choice,t)now=t;return invokes.WildAction(player,profile,e.id,choice,"basic")end
step(0); step(19.9); assert(view().encounter==nil)
step(20);local e=view().encounter;assert(e and e.hp==100)
local before=profile.coins
assert(not action(e,"capture",20))
assert(not invokes.WildAction(player,profile,"forged","strike"))
assert(not invokes.WildAction(player,profile,e.id,{}))
for _, t in {20.8,22.4,24,25.6} do
 local ok,result=action(e,"strike",t);assert(ok and result.result=="perfect")
 if t<25.6 then
  local coins=profile.coins;step(t);assert(profile.coins==coins+40,"wild combat must not pause training")
 end
end
assert(e.phase=="defeated" and profile.coins==before+3*40+800,"victory is five base-income seconds")
local paid=profile.coins
assert(not action(e,"strike",27.2));assert(profile.coins==paid,"no repeated win payment")
assert(deps.WildService.multiplier(player,26)==1.5)
step(26);assert(profile.coins==paid+60,"active bonus applied to training only")
local stockBefore=profile.prisms.basic
profile.prisms.basic=0
assert(not action(e,"capture",26.05));assert(e.phase=="defeated","no stock keeps the capture opportunity")
profile.prisms.basic=stockBefore
assert(action(e,"capture",26.1));assert(profile.prisms.basic==stockBefore-1);assert(#profile.pets==1 and profile.index.leafpup.normal)
assert(not action(e,"capture",26.2));assert(#profile.pets==1,"no repeated pet grant")
assert(profile.pets[1].uid~=nil)
assert(deps.WildService.multiplier(player,85.6)==1,"boost expires exactly")
root.Position.X=13;step(27);assert(view().encounter==nil and attrs.TrainingWorld==nil)
root.Position.X=0;step(28);step(48);e=view().encounter;assert(e)
root.Position.X=13;assert(not action(e,"strike",48.8));assert(view().encounter==nil)
root.Position.X=0;step(49);step(69);e=view().encounter;assert(e)
battling=true;assert(not action(e,"strike",69.8));assert(view().encounter==nil)
battling=false;step(70);step(90);e=view().encounter;assert(e)
for _, t in {90.8,92.4,94,95.6} do assert(action(e,"strike",t)) end
roll=0.999;assert(action(e,"capture",96));assert(#profile.pets==1,"failed capture grants nothing")
assert(not action(e,"capture",96.1));assert(#profile.pets==1)
for _, fn in callbacks do fn(player) end
assert(view().encounter==nil and deps.WildService.multiplier(player,96)==1,"leave clears all temporary state")
'''
        fixture = fixture.replace("__CONFIG__", run_tests.lua_value(config, "wild fixture"))
        files = {
            "__PRISMS__": "shared/rules/Prisms.luau",
            "__COINS__": "shared/rules/Coins.luau", "__INDEX__": "shared/rules/PetIndex.luau",
            "__TRAINING__": "shared/rules/Training.luau", "__SITES__": "shared/world/TrainingSites.luau",
            "__WILD__": "shared/rules/WildEncounter.luau", "__SERVICE__": "server/Services/WildService.luau",
            "__TRAININGSERVICE__": "server/Services/TrainingService.luau",
        }
        for token, path in files.items():
            fixture = fixture.replace(token, (game_dir / "src" / path).read_text())
        name, _ = run_tests.pinned_luau()
        tool = run_tests.find_luau(name)
        self.assertIsNotNone(tool)
        with tempfile.TemporaryDirectory(dir=ROOT) as temp:
            path = Path(temp) / "wild.luau"
            path.write_text(fixture)
            result = subprocess.run([str(tool), str(path)], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
