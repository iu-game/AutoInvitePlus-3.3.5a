-- AutoInvite Plus - Raid Tools (roll system: countdown, capture, winners)

local AIP = AutoInvitePlus
if not AIP then return end
AIP.RaidTools = AIP.RaidTools or {}
local RT = AIP.RaidTools

function RT.StartRoll(itemText, itemLink)
    if RT.rollActive then
        RT.Send("A roll is already in progress for " .. tostring(RT.rollItem) .. ".", "RAID")
        return
    end
    itemText = (itemText and itemText ~= "" and itemText) or "loot"
    local duration = (AIP.db and AIP.db.rollDuration) or 10
    if duration < 3 then duration = 3 end

    RT.rollActive = true
    RT.rolls = {}
    RT.rollItem = itemText
    RT.rollItemLink = itemLink
    RT.rollEndTime = time() + duration

    RT.Send("ROLL for " .. (itemLink or itemText) .. "!  Type /roll (1-100).  " .. duration .. " seconds!", "RAID_WARNING")

    if AIP.Utils and AIP.Utils.DelayedCall then
        AIP.Utils.DelayedCall(math.max(1, duration - 3), function()
            if RT.rollActive then
                RT.Send("3 seconds left to roll for " .. tostring(RT.rollItem) .. "!", "RAID_WARNING")
            end
        end)
        AIP.Utils.DelayedCall(duration, function() RT.FinishRoll() end)
    end

    if RT.RefreshRollWindow then RT.RefreshRollWindow() end
end

function RT.GetSortedRolls()
    local sorted = {}
    for name, val in pairs(RT.rolls) do
        sorted[#sorted + 1] = { name = name, value = val }
    end
    table.sort(sorted, function(a, b) return a.value > b.value end)
    return sorted
end

function RT.FinishRoll()
    if not RT.rollActive then return end
    RT.rollActive = false
    RT.rollEndTime = nil

    local sorted = RT.GetSortedRolls()
    if sorted[1] then
        local top = sorted[1]
        RT.Send("WINNER: " .. top.name .. " rolled " .. top.value .. " for " ..
            (RT.rollItemLink or tostring(RT.rollItem)) .. " (" .. #sorted .. " rolls)", "RAID_WARNING")
    else
        RT.Send("No valid rolls for " .. (RT.rollItemLink or tostring(RT.rollItem)) .. ".", "RAID_WARNING")
    end
    if RT.RefreshRollWindow then RT.RefreshRollWindow() end
end

function RT.CancelRoll()
    if not RT.rollActive then return end
    RT.rollActive = false
    RT.rollEndTime = nil
    RT.rolls = {}
    RT.Send("Roll cancelled.", "RAID")
    if RT.RefreshRollWindow then RT.RefreshRollWindow() end
end

function RT.AnnounceWinners(n)
    n = n or 1
    local sorted = RT.GetSortedRolls()
    if #sorted == 0 then
        RT.Send("No rolls to announce.", "RAID")
        return
    end
    local itemText = RT.rollItemLink or tostring(RT.rollItem or "loot")
    RT.Send("=== Roll results for " .. itemText .. " ===", "RAID_WARNING")
    local count = math.min(n, #sorted)
    for i = 1, count do
        RT.Send(i .. ". " .. sorted[i].name .. " - " .. sorted[i].value, "RAID_WARNING")
    end
end

function RT.TradeWinner()
    local sorted = RT.GetSortedRolls()
    if not sorted[1] then
        AIP.Print("No winner to trade with.")
        return
    end
    local winner = sorted[1].name
    local itemText = RT.rollItemLink or tostring(RT.rollItem or "loot")
    RT.Send("Trading " .. winner .. " for " .. itemText .. ".", "RAID")
    if TargetByName then TargetByName(winner, true) end
    if InitiateTrade then
        local ok = pcall(InitiateTrade, "target")
        if not ok then AIP.Print("Could not open trade with " .. winner .. " (out of range?).") end
    end
end

-- Scan system messages for "<name> rolls <n> (1-100)" while a roll is active.
function RT.OnSystemMessage(message)
    if not RT.rollActive or not message then return end
    local name, roll = message:match("^(.-) rolls (%d+) %(1%-100%)$")
    if not name then return end
    roll = tonumber(roll)
    if roll and not RT.rolls[name] then
        RT.rolls[name] = roll
        if AIP.Debug then AIP.Debug("RaidTools: roll " .. name .. " = " .. roll) end
        if RT.RefreshRollWindow then RT.RefreshRollWindow() end
    end
end
