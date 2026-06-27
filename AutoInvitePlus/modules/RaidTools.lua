-- AutoInvite Plus - Raid Tools (core: chat sender, announcements, loot items)
-- Split into RaidTools / RaidToolsRoll / RaidToolsUI / RaidToolsEvents so the
-- WoW client load phase reports failures per-section.

local AIP = AutoInvitePlus
if not AIP then
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[AIP Error]|r RaidTools: namespace not found!")
    return
end

AIP.RaidTools = AIP.RaidTools or {}
local RT = AIP.RaidTools

-- Constants shared across the RaidTools files
RT.LOOT_EXPIRE_SECONDS = 7200   -- BoP trade window (2h)
RT.LOOT_WARN_SECONDS = 900      -- warn when <15m remaining

-- State
RT.rollActive = false
RT.rolls = {}
RT.rollItem = nil
RT.rollItemLink = nil
RT.rollEndTime = nil
RT.manualItems = {}
RT.selectedKey = nil
RT.warnedItems = {}

-- ============================================================================
-- CHAT SENDER (smart channel with safe fallbacks)
-- ============================================================================

function RT.Send(msg, channel)
    if not msg or msg == "" then return end
    channel = channel or "RAID_WARNING"
    local inRaid = (GetNumRaidMembers() or 0) > 0
    local inParty = (GetNumPartyMembers() or 0) > 0

    if channel == "RAID_WARNING" then
        if inRaid and (IsRaidLeader() or IsRaidOfficer()) then
            SendChatMessage(msg, "RAID_WARNING")
        elseif inRaid then
            SendChatMessage(msg, "RAID")
        elseif inParty then
            SendChatMessage(msg, "PARTY")
        else
            SendChatMessage(msg, "SAY")
        end
    elseif channel == "RAID" then
        if inRaid then SendChatMessage(msg, "RAID")
        elseif inParty then SendChatMessage(msg, "PARTY")
        else SendChatMessage(msg, "SAY") end
    elseif channel == "PARTY" then
        if inParty or inRaid then SendChatMessage(msg, "PARTY")
        else SendChatMessage(msg, "SAY") end
    elseif channel == "GUILD" then
        if IsInGuild() then SendChatMessage(msg, "GUILD") else SendChatMessage(msg, "SAY") end
    else
        SendChatMessage(msg, channel)
    end
end

-- ============================================================================
-- CUSTOM ANNOUNCEMENTS
-- ============================================================================

function RT.GetAnnouncements()
    if AIP.db then
        AIP.db.customAnnouncements = AIP.db.customAnnouncements or {}
        return AIP.db.customAnnouncements
    end
    return {}
end

function RT.SendAnnouncement(index)
    local list = RT.GetAnnouncements()
    local ann = list[index]
    if ann then RT.Send(ann.message, ann.channel or "RAID_WARNING") end
end

-- ============================================================================
-- /RW LOOT ANNOUNCE (reserved items)
-- ============================================================================

function RT.AnnounceReserved()
    local reserved = (AIP.db and AIP.db.reservedItems) or ""
    if reserved == "" then
        RT.Send("No reserved items set.", "RAID")
        return
    end
    RT.Send("=== Reserved Items (Soft Reserve) ===", "RAID_WARNING")
    for rawLine in reserved:gmatch("[^\r\n]+") do
        local itemLine = rawLine:gsub("^%s+", ""):gsub("%s+$", "")
        if itemLine ~= "" then
            RT.Send(itemLine, "RAID_WARNING")
        end
    end
end

-- ============================================================================
-- LOOT ITEMS (from the current raid session) + EXPIRATION
-- ============================================================================

-- Format remaining seconds as "1h 45m" / "12m" / "expired"
function RT.FormatRemaining(secs)
    if not secs or secs <= 0 then return "expired" end
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h > 0 then return h .. "h " .. m .. "m" end
    return m .. "m"
end

function RT.GetRollItems()
    local items = {}
    local now = time()
    local expire = RT.LOOT_EXPIRE_SECONDS
    local warn = RT.LOOT_WARN_SECONDS

    local session = AIP.RaidSession and AIP.RaidSession.GetCurrentSession and AIP.RaidSession.GetCurrentSession()
    if session and session.loot then
        for i = #session.loot, 1, -1 do
            local e = session.loot[i]
            local ts = e.timestamp or now
            local remaining = (ts + expire) - now
            if remaining > 0 then
                items[#items + 1] = {
                    key = "s" .. i,
                    name = e.itemName or "Unknown",
                    link = e.itemLink,
                    quality = e.itemQuality or 1,
                    timestamp = ts,
                    winner = e.winner,
                    remaining = remaining,
                    expiring = remaining <= warn,
                }
            end
        end
    end

    for i, m in ipairs(RT.manualItems) do
        local ts = m.timestamp or now
        local remaining = (ts + expire) - now
        items[#items + 1] = {
            key = "m" .. i,
            name = m.name or "Unknown",
            link = m.link,
            quality = m.quality or 1,
            timestamp = ts,
            winner = nil,
            remaining = remaining,
            expiring = remaining <= warn,
        }
    end

    return items
end

function RT.AddManualItem(text)
    if not text or text == "" then return end
    local link = text:match("|c%x+|Hitem:.-|h.-|h|r")
    local name, quality
    if link then
        name = link:match("%[(.-)%]") or link
        local _, _, q = GetItemInfo(link)
        quality = q
    else
        name = text:gsub("^%s+", ""):gsub("%s+$", "")
    end
    if name and name ~= "" then
        table.insert(RT.manualItems, { name = name, link = link, quality = quality or 1, timestamp = time() })
        if RT.RefreshRollWindow then RT.RefreshRollWindow() end
    end
end

-- Warn once per item when it crosses the expiry threshold
function RT.CheckExpirations()
    local items = RT.GetRollItems()
    for _, it in ipairs(items) do
        if it.expiring and not it.winner and not RT.warnedItems[it.key] then
            RT.warnedItems[it.key] = true
            AIP.Print("|cFFFF6060Loot warning:|r " .. (it.link or it.name) ..
                " expires in " .. RT.FormatRemaining(it.remaining) .. " (trade window).")
        end
    end
end
