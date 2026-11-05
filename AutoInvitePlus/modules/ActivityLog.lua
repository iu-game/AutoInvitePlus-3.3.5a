-- AutoInvite Plus - ActivityLog
-- In-memory ring buffer (never saved) of what the addon did on the player's
-- behalf: invites, whispers, broadcasts, timers, queue/waitlist adds. Lets the
-- user answer "what did AIP just send?" without chat spam.
local AIP = AutoInvitePlus
AIP.ActivityLog = AIP.ActivityLog or {}
local AL = AIP.ActivityLog

AL.MAX = 200
AL.entries = AL.entries or {}

local function now()
    if time then return time() end
    return 0
end

-- kind: short tag ("invite", "whisper", "broadcast", "timer", "queue", "waitlist")
function AL.Add(kind, text)
    local e = AL.entries
    e[#e + 1] = { t = now(), kind = tostring(kind or "?"), text = tostring(text or "") }
    if #e > AL.MAX then table.remove(e, 1) end
end

-- Last n entries, oldest first.
function AL.Recent(n)
    local e = AL.entries
    n = tonumber(n) or 20
    if n > #e then n = #e end
    local out = {}
    for i = #e - n + 1, #e do out[#out + 1] = e[i] end
    return out
end

function AL.Clear() AL.entries = {} end

function AL.Print(n)
    local list = AL.Recent(n or 20)
    if #list == 0 then AIP.Print("Activity log is empty.") return end
    AIP.Print("Activity (last " .. #list .. "):")
    for _, e in ipairs(list) do
        AIP.Print("  " .. date("%H:%M:%S", e.t) .. " [" .. e.kind .. "] " .. e.text)
    end
end
