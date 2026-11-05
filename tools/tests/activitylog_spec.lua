-- Headless spec: ActivityLog ring buffer cap, ordering and kind filter.
-- Run from repo root: luajit tools/tests/activitylog_spec.lua
local fails, passes = 0, 0
local function eq(a, b, msg)
    if a == b then passes = passes + 1 else fails = fails + 1; print("FAIL: " .. msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end
end

local clock = 0
function time() clock = clock + 1; return 1700000000 + clock end
function date(f, t) return "12:00:00" end
AutoInvitePlus = { db = {}, Print = function() end }
local AIP = AutoInvitePlus
assert(loadfile("AutoInvitePlus/modules/ActivityLog.lua"))()
local AL = AIP.ActivityLog

-- cap
for i = 1, 250 do AL.Add("invite", "i" .. i) end
eq(#AL.entries, AL.MAX, "ring capped")
eq(AL.entries[1].text, "i51", "oldest dropped")

-- ordering: newest first
local f = AL.Filter(nil, 3)
eq(#f, 3, "Filter n")
eq(f[1].text, "i250", "newest first")
eq(f[3].text, "i248", "third newest")
eq(#AL.Filter("all"), AL.MAX, "all returns everything")

-- kind filter
AL.Clear()
eq(#AL.Filter(nil), 0, "cleared")
AL.Add("invite", "a"); AL.Add("whisper", "b"); AL.Add("queue", "c")
AL.Add("waitlist", "d"); AL.Add("timer", "e"); AL.Add("whisper", "f")
local w = AL.Filter("whisper")
eq(#w, 2, "whisper count")
eq(w[1].text, "f", "whisper newest first")
eq(w[2].text, "b", "whisper older second")
local q = AL.Filter("queue")
eq(#q, 2, "queue chip includes waitlist")
eq(q[1].text, "d", "waitlist newest")
eq(#AL.Filter("broadcast"), 0, "no broadcast")
eq(#AL.Filter("whisper", 1), 1, "n limits after filtering")
eq(AL.Matches(nil, "x"), true, "nil matches all")
eq(AL.Matches("invite", "whisper"), false, "mismatch")

-- rev counter changes on mutation
local r = AL.rev
AL.Add("timer", "x"); eq(AL.rev ~= r, true, "rev bumps on Add")
r = AL.rev; AL.Clear(); eq(AL.rev ~= r, true, "rev bumps on Clear")

print(string.format("activitylog_spec: %d passed, %d failed", passes, fails))
os.exit(fails == 0 and 0 or 1)
