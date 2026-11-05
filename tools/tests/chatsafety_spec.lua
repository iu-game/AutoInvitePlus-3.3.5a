-- Headless spec: ChatGate reject-whisper limiter + stats, ActivityLog ring buffer.
-- Run from repo root: luajit tools/tests/chatsafety_spec.lua
local fails, passes = 0, 0
local function eq(a, b, msg)
    if a == b then passes = passes + 1 else fails = fails + 1; print("FAIL: " .. msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end
end

local clock = 1000
function GetTime() return clock end
function time() return 1700000000 + clock end
function date(f, t) return "00:00:00" end
function GetChannelName() return 0 end
function SendChatMessage() end
function CreateFrame()
    return { RegisterEvent = function() end, SetScript = function() end }
end
UIParent = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }

AutoInvitePlus = { db = {}, Utils = { DelayedCall = function() end }, Print = function() end }
local AIP = AutoInvitePlus

local function load(path)
    local f = assert(loadfile(path))
    f()
end
load("AutoInvitePlus/core/ChatGate.lua")
load("AutoInvitePlus/modules/ActivityLog.lua")
local CG, AL = AIP.ChatGate, AIP.ActivityLog

-- Defaults: cooldown 120s, cap 6/min
eq(CG.AllowRejectWhisper("Bob", clock), true, "first whisper allowed")
eq(CG.AllowRejectWhisper("bob", clock + 10), false, "same sender (case-insens) within cooldown blocked")
eq(CG.AllowRejectWhisper("Bob", clock + 121), true, "same sender after cooldown allowed")

-- global cap
clock = 5000
CG.Reject = { perSender = {}, recent = {}, suppressed = {}, sentTotal = 0, suppressedTotal = 0 }
for i = 1, 6 do eq(CG.AllowRejectWhisper("P" .. i, clock + i), true, "within cap " .. i) end
eq(CG.AllowRejectWhisper("P7", clock + 7), false, "7th in a minute dropped")
eq(CG.Reject.suppressedTotal, 1, "suppressed counted")
local st = CG.GetStats(clock + 8)
eq(st.rejectSent, 6, "stats rejectSent")
eq(st.rejectSuppressed, 1, "stats rejectSuppressed")
eq(st.queued, 0, "stats queued")
eq(st.muted, false, "not muted")
eq(CG.AllowRejectWhisper("P8", clock + 62), true, "window rolls after 60s")

-- configurable
AIP.db.rejectWhisperMaxPerMin = 1
AIP.db.rejectWhisperCooldown = 5
CG.Reject = { perSender = {}, recent = {}, suppressed = {}, sentTotal = 0, suppressedTotal = 0 }
eq(CG.AllowRejectWhisper("A", 9000), true, "custom cap first")
eq(CG.AllowRejectWhisper("B", 9001), false, "custom cap blocks second")
eq(CG.AllowRejectWhisper("A", 9061), true, "custom cooldown elapsed")

-- muted state
CG.State.blackoutUntil = 20000
eq(CG.GetStats(19990).muted, true, "muted during blackout")
eq(CG.GetStats(19990).mutedFor, 10, "mutedFor seconds")

-- ActivityLog ring buffer
for i = 1, 250 do AL.Add("k", "m" .. i) end
eq(#AL.entries, 200, "ring capped at 200")
local r = AL.Recent(3)
eq(#r, 3, "Recent(3) size")
eq(r[3].text, "m250", "newest last")
eq(r[1].text, "m248", "oldest of the 3")
eq(AL.Recent(1000)[1].text, "m51", "oldest kept is m51")
AL.Clear()
eq(#AL.Recent(5), 0, "cleared")

print(string.format("chatsafety_spec: %d passed, %d failed", passes, fails))
os.exit(fails == 0 and 0 or 1)
