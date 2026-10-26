"""Execute actual Profiles/SaveOrder in Luau with an in-memory DataStore.

No Roblox API, Studio, user data, executor or model call is involved.
Schema migration has its own shared-rule suite; this harness isolates storage.
"""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "factory/tools"))
import run_tests

PREFIX = r'''
local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {} for k,v in t do out[k]=copy(v) end return out
end
local function create(mode, trace, encoderFails)
    local captures, records = {}, {}
    local store = { fail=false, records=records }
    function store:UpdateAsync(key, fn)
        if self.fail then error("simulated save outage") end
        if self.replay then fn(copy(records[key])) end
        local value=fn(copy(records[key]))
        if value ~= nil then records[key]=copy(value) end
        if self.afterCommitFail then self.afterCommitFail=false error("simulated lost commit acknowledgement") end
        return copy(records[key])
    end
    local function event()
        return {Connect=function(self, cb) self.callback=cb end}
    end
    local players={PlayerAdded=event(),PlayerRemoving=event()}
    function players:GetPlayers() return {} end
    local attributes={BetaSaveEvidence=trace,BetaBuildSha256=string.rep("a",64)}
    local function node(name)
        return {name=name,WaitForChild=function(self,n) return node(n) end}
    end
    local http={GenerateGUID=function() return "test-job" end,
        JSONEncode=function(self, value)
            if encoderFails then error("simulated evidence failure") end
            table.insert(captures,value) return "mock-json"
        end}
    local services={Players=players,ReplicatedStorage=node("ReplicatedStorage"),
        HttpService=http,RunService={IsStudio=function() return true end},
        ServerScriptService={GetAttribute=function(self,k) return attributes[k] end},
        DataStoreService={GetDataStore=function()
            if mode=="temporary" then error("unpublished Studio store unavailable") end
            return store
        end}}
    local game={JobId="server-a",PlaceId=123,PlaceVersion=1,
        GetService=function(self,k) return services[k] end,
        BindToClose=function(self,cb) self.close=cb end}
    local task={spawn=function() end,wait=function() end}
    local os={time=function() return store.now or 1000 end,clock=function() return 10 end}
    local DateTime={now=function() return {ToIsoDate=function() return "2026-10-20T12:00:00Z" end} end}
    local warn=function() end
    local print=function() end
    local profile={new=function() return {coins=0,playSeconds=0,gymRetryAt={}} end,
        isNoAccessError=function() return false end,migrate=copy,
        validate=function() return {} end,repair=function(p) return copy(p),{} end,
        playSecondsAfter=function(base,elapsed) return base+math.floor(elapsed) end}
    local SaveOrder=(function()
__SAVE_ORDER__
    end)()
    local Offline=(function()
        local script={Parent={Parent={Config={name="Config"}}}}
        local require=function() return {constants={offline_max_seconds=7200,offline_rate_fraction=0.25}} end
__OFFLINE__
    end)()
    local require=function(module)
        if module.name=="Profile" then return profile end
        if module.name=="SaveOrder" then return SaveOrder end
        if module.name=="Offline" then return Offline end
        error("unexpected dependency: "..module.name)
    end
    local Profiles=(function()
__PROFILES__
    end)()
    local function player(id)
        return {UserId=id,Parent=players,GetAttribute=function(self,k)
            return if k=="BetaSubject" then "qa-"..id else nil end,
            Kick=function() error("unexpected kick") end}
    end
    Profiles.start()
    return Profiles,players,store,captures,player
end
'''


class ProfilesRuntimeTests(unittest.TestCase):
    def test_receipt_flush_is_durable_and_refuses_outage_temporary_foreign_and_departed(self):
        self.run_luau('''
local p,events,store,logs,make=create("datastore",false)
local a=make(1); events.PlayerAdded.callback(a)
local profile=p.get(a)
profile.paidPrisms={basic=10}; profile.purchaseReceipts={purchase=true}
store.fail=true
assert(not p.flush(a)); assert(store.records.user_1.profile==nil)
store.fail=false; store.replay=true; store.afterCommitFail=true
assert(p.flush(a))
assert(store.records.user_1.profile.paidPrisms.basic==10)
assert(store.records.user_1.profile.purchaseReceipts.purchase)
assert(p.flush(a)); assert(store.records.user_1.profile.paidPrisms.basic==10)
events.PlayerRemoving.callback(a)
assert(not p.flush(a))
events.PlayerAdded.callback(a)
assert(p.get(a).paidPrisms.basic==10 and p.get(a).purchaseReceipts.purchase)
store.records.user_1.session.jobId="another-server"
assert(not p.flush(a))
local temp,te,ts,tl,tm=create("temporary",false)
local b=tm(2); te.PlayerAdded.callback(b); assert(not temp.flush(b))
''')

    def run_luau(self, case):
        source = PREFIX.replace("__SAVE_ORDER__", (ROOT / "games/egg-champions/src/shared/rules/SaveOrder.luau").read_text())
        source = source.replace("__OFFLINE__", (ROOT / "games/egg-champions/src/shared/rules/Offline.luau").read_text())
        source = source.replace("__PROFILES__", (ROOT / "games/egg-champions/src/server/Profiles.luau").read_text())
        name, _ = run_tests.pinned_luau()
        tool = run_tests.find_luau(name)
        self.assertIsNotNone(tool, "pinned Luau interpreter is required")
        with tempfile.TemporaryDirectory(dir=ROOT) as temp:
            path = Path(temp) / "profiles-mock.luau"
            path.write_text(source + "\n" + case, encoding="utf-8")
            result = subprocess.run([str(tool), str(path)], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_save_release_rejoin_and_player_isolation(self):
        self.run_luau('''
local p,events,store,logs,make=create("datastore",true)
local a,b=make(1),make(2)
assert(p.persistenceMode(a)=="unloaded")
events.PlayerAdded.callback(a); events.PlayerAdded.callback(b)
assert(p.persistenceMode(a)=="datastore")
p.get(a).coins=42
p.onLeaving(function(player,profile) profile.gymRetryAt.gym=1030 end)
events.PlayerRemoving.callback(a)
assert(p.persistenceMode(a)=="unloaded")
assert(store.records.user_1.session==nil)
assert(logs[1].saved==true and logs[1].released==true and logs[1].subject=="qa-1")
events.PlayerAdded.callback(a)
assert(p.get(a).coins==42 and p.get(a).gymRetryAt.gym==1030)
assert(p.get(b).coins==0 and p.get(b).gymRetryAt.gym==nil)
''')

    def test_offline_reward_is_committed_once_and_release_starts_new_clock(self):
        self.run_luau(''' 
local p,events,store,logs,make=create("datastore",false)
store.records.user_1={profile={coins=12,playSeconds=0},offline={at=900,rate=2}}
local a=make(1); events.PlayerAdded.callback(a)
assert(p.get(a).coins==212 and store.records.user_1.profile.coins==212)
assert(p.offlineReward(a).coins==212-12)
-- A repeated claim before any save consumes no new currency.
events.PlayerAdded.callback(a); assert(p.get(a).coins==212)
p.setOfflineRate(function() return 3 end)
events.PlayerRemoving.callback(a)
assert(store.records.user_1.offline.at==1000 and store.records.user_1.offline.rate==3)
store.now=1010; events.PlayerAdded.callback(a)
assert(p.get(a).coins==242 and p.offlineReward(a).coins==30)
''')

    def test_claim_callback_replay_and_lost_acknowledgement_do_not_duplicate_reward(self):
        self.run_luau('''
local p,events,store,logs,make=create("datastore",false)
store.records.user_1={profile={coins=10,playSeconds=0},offline={at=900,rate=2}}
store.replay=true; store.afterCommitFail=true
local a=make(1); events.PlayerAdded.callback(a)
assert(p.get(a).coins==210 and store.records.user_1.profile.coins==210)
assert(p.offlineReward(a).coins==200)
assert(p.offlineReward(a).source.at==900 and p.offlineReward(a).source.rate==2)
''')

    def test_offline_cap_legacy_and_failed_write(self):
        self.run_luau('''
local p,events,store,logs,make=create("datastore",false)
store.records.user_1={profile={coins=10,playSeconds=0},offline={at=1,rate=2}}
store.now=20000
local a=make(1); events.PlayerAdded.callback(a)
assert(p.get(a).coins==14410 and p.offlineReward(a).seconds==7200)
p.setOfflineRate(function() return 5 end)
store.fail=true; events.PlayerRemoving.callback(a); store.fail=false
assert(store.records.user_1.offline.rate==0)
store.now=20100; events.PlayerAdded.callback(a)
assert(p.get(a).coins==14410)
local b=make(2); store.records.user_2={profile={coins=20,playSeconds=0}}
events.PlayerAdded.callback(b); assert(p.get(b).coins==20 and p.offlineReward(b).coins==0)
''')

    def test_temporary_profile_never_claims_persistent_success(self):
        self.run_luau('''
local p,events,store,logs,make=create("temporary",true)
local a=make(1); events.PlayerAdded.callback(a)
assert(p.persistenceMode(a)=="temporary")
p.get(a).coins=42; events.PlayerRemoving.callback(a)
assert(next(store.records)==nil)
assert(logs[1].saved==false and logs[1].storage_mode=="temporary")
events.PlayerAdded.callback(a); assert(p.get(a).coins==0)
''')

    def test_write_outage_and_foreign_lock_do_not_report_success(self):
        self.run_luau('''
for _,kind in {"outage","foreign"} do
    local p,events,store,logs,make=create("datastore",true)
    local a=make(1); events.PlayerAdded.callback(a)
    store.records.user_1.profile={coins=17,playSeconds=0}
    p.get(a).coins=42
    if kind=="outage" then store.fail=true else store.records.user_1.session.jobId="server-b" end
    events.PlayerRemoving.callback(a)
    assert(store.records.user_1.profile.coins==17)
    assert(logs[1].saved==false)
end
''')

    def test_save_logging_is_disabled_by_default(self):
        self.run_luau('''
local p,events,store,logs,make=create("datastore",false)
local a=make(1); events.PlayerAdded.callback(a); events.PlayerRemoving.callback(a)
assert(#logs==0 and store.records.user_1.session==nil)
''')

    def test_optional_evidence_failure_cannot_break_save_release(self):
        self.run_luau('''
local p,events,store,logs,make=create("datastore",true,true)
local a=make(1); events.PlayerAdded.callback(a); p.get(a).coins=42
events.PlayerRemoving.callback(a)
assert(#logs==0 and store.records.user_1.session==nil)
assert(store.records.user_1.profile.coins==42)
''')


if __name__ == "__main__":
    unittest.main()
