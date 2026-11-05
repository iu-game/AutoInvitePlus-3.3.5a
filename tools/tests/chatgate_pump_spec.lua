-- Headless spec: ChatGate.Pump survives a throwing validate() and drops the record.
-- Run from repo root: luajit tools/tests/chatgate_pump_spec.lua
local fails, passes = 0, 0
local function eq(a, b, msg)
    if a == b then passes = passes + 1 else fails = fails + 1; print("FAIL: " .. msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end
end

local clock = 1000
function GetTime() return clock end
function time() return 1700000000 + clock end
function date() return "00:00:00" end
function GetChannelName() return 0 end
local sent = {}
function SendChatMessage(m) sent[#sent + 1] = m end
function CreateFrame() return { RegisterEvent = function() end, SetScript = function() end } end
UIParent = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
AutoInvitePlus = { db = {}, Utils = { DelayedCall = function() end }, Print = function() end }
local AIP = AutoInvitePlus
assert(loadfile("AutoInvitePlus/core/ChatGate.lua"))()
local CG = AIP.ChatGate

CG.Send("boom", "SAY", nil, { owner = "t", validate = function() error("bad validate") end })
eq(#CG.State.queue, 1, "queued")
local ok = pcall(CG.Pump)
eq(ok, true, "Pump does not throw on throwing validate")
eq(#CG.State.queue, 0, "record dropped")
eq(CG.State.dropped, 1, "dropped counted")
eq(#sent, 0, "nothing sent")

print(string.format("chatgate_pump_spec: %d passed, %d failed", passes, fails))
os.exit(fails == 0 and 0 or 1)
