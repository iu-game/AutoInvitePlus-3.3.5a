-- Headless tests for the inspect arbiter (data/InspectionEngine.lua) and
-- LFGWatch.ParseProposal (modules/LFGWatch.lua). Run from the repo root:
--   luajit tools/tests/inspect_spec.lua

local fails, passes = 0, 0
local function check(cond, msg)
    if cond then passes = passes + 1 else fails = fails + 1; print("FAIL: " .. msg) end
end

local now = 1000
local notifies, clears = {}, 0
GetTime = function() return now end
time = function() return 0 end
NotifyInspect = function(u) notifies[#notifies + 1] = u end
ClearInspectPlayer = function() clears = clears + 1 end
UnitName = function(u) return "N_" .. tostring(u) end
CanInspect = function() return true end
GetNumRaidMembers = function() return 0 end
GetNumPartyMembers = function() return 0 end
local frames = {}
CreateFrame = function()
    local f = { scripts = {} }
    function f:RegisterEvent() end
    function f:SetScript(n, fn) self.scripts[n] = fn end
    function f:Hide() end
    function f:Show() end
    frames[#frames + 1] = f
    return f
end

AutoInvitePlus = { db = {}, Utils = {} }
local function load(path)
    local chunk = assert(loadfile(path))
    chunk("AutoInvitePlus", AutoInvitePlus)
end

load("AutoInvitePlus/data/InspectionEngine.lua")
local IE = AutoInvitePlus.InspectionEngine
local ieFrame = frames[#frames]

-- ---- arbiter ---------------------------------------------------------------
check(not IE.Busy(), "idle at start")
check(IE.Request("raid1", "comp") == true, "first request granted")
check(#notifies == 1 and notifies[1] == "raid1", "NotifyInspect issued once")
check(IE.Busy(), "busy after request")
check(IE.Request("raid2", "queue") == false, "second request refused while busy")
check(IE.SafeNotify("mouseover") == false, "SafeNotify no-op while busy")
check(#notifies == 1, "no second NotifyInspect while busy")

-- completion frees the lock and runs the callback; buffer is NOT cleared
local cbUnit
IE.Arb.callback = function(u) cbUnit = u end
local clearsBefore = clears
ieFrame.scripts.OnEvent(ieFrame, "INSPECT_TALENT_READY")
check(not IE.Busy(), "free after INSPECT_TALENT_READY")
check(cbUnit == "raid1", "callback receives the unit")
check(clears == clearsBefore, "ClearInspectPlayer not called on normal completion")

-- timeout release
check(IE.Request("raid3", "queue") == true, "request after release")
now = now + IE.ArbTimeout - 1
check(IE.Busy(), "still busy before timeout")
now = now + 2
check(not IE.Busy(), "released after timeout")
check(IE.Request("raid4", "comp") == true, "request granted after timeout release")
ieFrame.scripts.OnEvent(ieFrame, "INSPECT_TALENT_READY")

-- SafeNotify rate limit
notifies = {}
now = now + 10
check(IE.SafeNotify("mouseover") == true, "SafeNotify fires when idle")
ieFrame.scripts.OnEvent(ieFrame, "INSPECT_TALENT_READY")
now = now + 0.5
check(IE.SafeNotify("mouseover") == false, "SafeNotify rate-limited")
now = now + 2
check(IE.SafeNotify("mouseover") == true, "SafeNotify allowed after interval")
check(#notifies == 2, "exactly two tooltip notifies")
ieFrame.scripts.OnEvent(ieFrame, "INSPECT_TALENT_READY")

-- queue defers to a busy arbiter and keeps its entry
IE.Queue.pending = { { name = "Bob", priority = 1, time = 0 } }
IE.ResolveUnit = function(n) return "party1" end
now = now + 20
IE.Request("raid9", "comp")
local nBefore = #notifies
for _, f in ipairs(frames) do if f.scripts.OnUpdate then f.scripts.OnUpdate(f, 1) end end
check(#notifies == nBefore, "queue does not NotifyInspect while comp inspect in flight")
check(#IE.Queue.pending == 1, "queue entry retained while busy")
ieFrame.scripts.OnEvent(ieFrame, "INSPECT_TALENT_READY")

-- ---- LFGWatch.ParseProposal -----------------------------------------------
load("AutoInvitePlus/modules/LFGWatch.lua")
local LW = AutoInvitePlus.LFGWatch
check(LW and LW.ParseProposal, "ParseProposal exposed")
local P = LW.ParseProposal

-- 12-value form (with subtypeID)
local p = P(true, 262, 1, 1, "Utgarde Keep", "Interface\\Icons", "DAMAGER", false, 3, 1, 5, true)
check(p and p.id == 262 and p.name == "Utgarde Keep", "12-value: id+name")
check(p.role == "DAMAGER" and p.hasResponded == false and p.isLeader == true, "12-value: role/bools")
check(p.numMembers == 5 and p.completedEncounters == 1 and p.totalEncounters == 3, "12-value: counts")

-- 11-value form (no subtypeID)
p = P(true, 262, 1, "Utgarde Keep", "Interface\\Icons", "TANK", true, 3, 2, 5, false)
check(p and p.id == 262 and p.name == "Utgarde Keep" and p.role == "TANK", "11-value: fields")
check(p.numMembers == 5 and p.completedEncounters == 2 and p.totalEncounters == 3, "11-value: counts")
check(p.hasResponded == true and p.isLeader == false, "11-value: bools")

-- no proposal / nil / short returns never error
check(P() == nil, "no args -> nil")
check(P(false) == nil, "exists=false -> nil")
check(P(nil, 1, 2) == nil, "exists=nil -> nil")
local ok, short = pcall(P, true, 5, "Name")
check(ok and short and short.name == "Name" and short.numMembers == nil, "short return tolerated")
ok = pcall(P, true, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil)
check(ok, "all-nil tail tolerated")

print(string.format("inspect_spec: %d passed, %d failed", passes, fails))
os.exit(fails == 0 and 0 or 1)
