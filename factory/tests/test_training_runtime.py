"""Run actual training and shop services together without live player data."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"factory/tools"))
import run_tests

class TrainingRuntimeTests(unittest.TestCase):
    def test_successful_hatches_and_legacy_pause_attribute_never_stop_training(self):
        fixture=r'''
local function node(name)
 return setmetatable({name=name,WaitForChild=function(self,n)return node(n)end},{__index=function(_,n)return node(n)end})
end
local attrs={TrainingBlockedUntil=999}
local root={Position={X=0,Y=3,Z=0},IsA=function()return true end}
local humanoid={Health=100}
local player={Parent={},Character={FindFirstChild=function()return root end,FindFirstChildOfClass=function()return humanoid end},GetAttribute=function(self,k)return attrs[k]end,
 SetAttribute=function(self,k,v)assert(k~="TrainingBlockedUntil","hatch must not install a pause");attrs[k]=v end}
local profile={coins=1000,pets={},team={},index={},unlocked=1}
local vector={__kind="Vector3",X=0,Y=0,Z=0}
local site={IsDescendantOf=function()return true end,GetAttribute=function(self,k)return ({TrainingPosition=vector,WorldId="green_meadow",WorldIndex=1})[k]end}
local services={Players={},ReplicatedStorage=node("RS"),CollectionService={GetTagged=function()return {site}end},Workspace={},HttpService={GenerateGUID=function()return "unique"end}}
local game={GetService=function(self,k)return services[k]end}
local typeof=function(v)return if type(v)=="table" and v.__kind then v.__kind else type(v)end
local script={Parent=node("Services")}
local Random={new=function()return {}end}
local config={constants={training_tick_seconds=.25,training_hits_per_tick=4,training_auto_bonus_hits=1,training_radius=12,training_max_vertical=8},eggs={{id="meadow"}},eggById={meadow={price=50}},petById={testpet={rarity="common"}}}
local progression={worldUnlocked=function(p,i)return p.unlocked>=i end,eggUnlocked=function()return true end}
local invokes={}
local deps={Config=config,Progression=progression,Profile={},Profiles={get=function()return profile end},
 Passes={owned=function()return {}end},GymService={isBattling=function()return false end},
 WildService={observe=function()end,multiplier=function()return 1 end},
 ClickService={train=function(p,data,hits) data.coins+=hits end},
 Coins={clickPowerOf=function()return 1 end},
 Hatch={TRIPLE_COUNT=3,rollMany=function()return {{petId="testpet"}}end},
 PassEffects={autoClick=function()return false end,hatchCountAllowed=function(_,n)return n==1 end,hatchOptions=function()return {}end},
 PetIndex={record=function(index,id)index[id]=true;return true end},
 Remotes={names={BuyEgg="BuyEgg"}},Requests={setOf=function()return {}end,checkChoice=function()return true end,reasons={badChoice="bad"}},
 Guard={addDerived=function()end,onInvoke=function(name,fn)invokes[name]=fn end},
 TutorialService={note=function()end},Analytics={track=function()end,withPlaytime=function(_,data)return data end}}
local require=function(module)return assert(deps[module.name],module.name)end
local scriptRule={Parent={Parent={Config=node("Config")},Progression=node("Progression")}}
local function loadRule(source)
end
local Training=(function()
 local script=scriptRule
__TRAINING__
end)()
deps.Training=Training
deps.TrainingSites=(function()
__SITES__
end)()
local TrainingService=(function()
__SERVICE__
end)()
local ShopService=(function()
__SHOP__
end)()
ShopService.start()
TrainingService.step(player,0)
for i=1,24 do
 local now=i/4
 if i==1 or i==13 then assert(invokes.BuyEgg(player,profile,"meadow",1)) end
 TrainingService.step(player,now)
 assert(attrs.TrainingWorld=="green_meadow" and attrs.TrainingStartedAt==0)
 assert(attrs.TrainingPulseAt==now)
end
assert(#profile.pets==2)
assert(profile.coins==1000-100+24*4,"all 24 rewards must survive both hatch reveals")
root.Position.X=13;TrainingService.step(player,6.25)
assert(attrs.TrainingWorld==nil and profile.coins==996,"leaving still stops rewards")
'''
        for token,path in {"__TRAINING__":"shared/rules/Training.luau","__SITES__":"shared/world/TrainingSites.luau","__SERVICE__":"server/Services/TrainingService.luau","__SHOP__":"server/Services/ShopService.luau"}.items():
            fixture=fixture.replace(token,(ROOT/"games/egg-champions/src"/path).read_text())
        name,_=run_tests.pinned_luau();tool=run_tests.find_luau(name)
        self.assertIsNotNone(tool)
        with tempfile.TemporaryDirectory(dir=ROOT) as temp:
            path=Path(temp)/"training.luau";path.write_text(fixture)
            result=subprocess.run([str(tool),str(path)],capture_output=True,text=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
