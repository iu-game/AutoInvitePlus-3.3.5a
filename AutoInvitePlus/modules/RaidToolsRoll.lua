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
    RT.bannedRollers = {}   -- name -> ban reason for loot-banned players who rolled
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

-- Is this roller loot-banned? Uses the Raid Mgmt loot-ban list, checked against
-- the currently-tracked boss (falls back to all-boss bans). Returns banned, boss.
function RT.IsRollerBanned(name)
    local RM = AIP.Panels and AIP.Panels.RaidMgmt
    if not RM or not RM.IsPlayerLootBanned then return false end
    return RM.IsPlayerLootBanned(name, RM.CurrentBoss)
end

-- Highest roller who is NOT loot-banned. Returns winnerEntry, skippedCount, total.
function RT.GetEligibleWinner()
    local sorted = RT.GetSortedRolls()
    local banned = RT.bannedRollers or {}
    local skipped = 0
    for _, r in ipairs(sorted) do
        if banned[r.name] then
            skipped = skipped + 1
        else
            return r, skipped, #sorted
        end
    end
    return nil, skipped, #sorted
end

function RT.FinishRoll()
    if not RT.rollActive then return end
    RT.rollActive = false
    RT.rollEndTime = nil

    -- The winner is the highest roller who is NOT loot-banned.
    local winner, skipped, total = RT.GetEligibleWinner()

    local itemText = RT.rollItemLink or tostring(RT.rollItem)
    if winner then
        local note = skipped > 0 and (" [" .. skipped .. " loot-banned skipped]") or ""
        RT.Send("WINNER: " .. winner.name .. " rolled " .. winner.value .. " for " ..
            itemText .. " (" .. total .. " rolls)" .. note, "RAID_WARNING")

        -- Record the win in the loot history (Won tab). Only when we have a real
        -- item link to log; a bare /roll has no item to attribute.
        if RT.rollItemLink then
            local LH = AIP.Panels and AIP.Panels.LootHistory
            if LH and LH.AddLootEntry then
                LH.AddLootEntry(RT.rollItemLink, winner.name, nil, GetRealZoneText(), "won")
            end
        end
    elseif total > 0 then
        -- Everyone who rolled is loot-banned.
        RT.Send("No eligible winner for " .. itemText ..
            " - all " .. total .. " rollers are loot-banned.", "RAID_WARNING")
    else
        RT.Send("No valid rolls for " .. itemText .. ".", "RAID_WARNING")
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
    -- Trade the eligible (non-loot-banned) winner, consistent with FinishRoll.
    local eligible = RT.GetEligibleWinner()
    if not eligible then
        AIP.Print("No eligible winner to trade with.")
        return
    end
    local winner = eligible.name
    local itemText = RT.rollItemLink or tostring(RT.rollItem or "loot")
    RT.Send("Trading " .. winner .. " for " .. itemText .. ".", "RAID")
    if TargetByName then TargetByName(winner, true) end
    if InitiateTrade then
        local ok = pcall(InitiateTrade, "target")
        if not ok then AIP.Print("Could not open trade with " .. winner .. " (out of range?).") end
    end
end

-- Locale-agnostic roll matcher derived from the client's RANDOM_ROLL_RESULT
-- ("%s rolls %d (%d-%d)") so roll capture also works on non-enUS clients.
local ROLL_PATTERN = (function()
    local fmt = RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
    fmt = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")   -- escape magic chars (leave % specifiers)
    fmt = fmt:gsub("%%s", "(.-)", 1)                        -- name capture
    local seen = false
    fmt = fmt:gsub("%%d", function()                        -- first %d = roll capture, rest = digits
        if not seen then seen = true; return "(%d+)" end
        return "%d+"
    end)
    return "^" .. fmt .. "$"
end)()

-- Scan system messages for "<name> rolls <n> (1-100)" while a roll is active.
function RT.OnSystemMessage(message)
    if not RT.rollActive or not message then return end
    local name, roll = message:match(ROLL_PATTERN)
    if not name then return end
    roll = tonumber(roll)
    if roll and not RT.rolls[name] then
        RT.rolls[name] = roll
        if AIP.Debug then AIP.Debug("RaidTools: roll " .. name .. " = " .. roll) end

        -- Flag loot-banned rollers so they can't win and the ML is warned.
        local banned, banBoss = RT.IsRollerBanned(name)
        if banned then
            RT.bannedRollers = RT.bannedRollers or {}
            RT.bannedRollers[name] = banBoss or true
            local where = (type(banBoss) == "string") and (" (" .. banBoss .. ")") or ""
            AIP.Print("|cFFFF0000LOOT BANNED:|r " .. name .. " rolled " .. roll ..
                " but is banned" .. where .. " - excluded from winning.")
        end

        if RT.RefreshRollWindow then RT.RefreshRollWindow() end
    end
end
