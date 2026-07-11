-- AutoInvite Plus - Character Card share (full char info in an LFG listing).
-- Broadcasts a compact "character card" over the DataBus so peers see a player's
-- equipped gear (item + enchant + gem ids) and their key raid/PvP achievements
-- WITHOUT inspecting - attached to their LFG listing (shown in the browser tooltip).
--
-- Compact by design: instead of full item links we send per-slot {s,i,e,g} (slot,
-- itemID, enchant id, gem ids - all read straight from the item string). Paged for
-- the 255-char DataBus cap and staggered past the rate gate (like the blacklist share).

local AIP = AutoInvitePlus
if not AIP then return end
AIP.CharCard = AIP.CharCard or {}
local CC = AIP.CharCard

local GEAR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
local SLOTS_PER_PAGE = 3
local MAX_ACH = 12

CC.peerCards = {}   -- name -> assembled card { name, gs, ilvl, slots = {slotId -> {s,i,e,g}}, ach = {ids}, ts }
local pending = {}  -- sender -> { name, gs, ilvl, ach, slots = {slotId -> row}, seqs = {}, total }

-- Completed key raid/PvP achievements (ids from Integrations.RaidAchievements - already
-- verified in-repo). Only works for the local player (or an inspected unit).
local function completedAchievements()
    local out = {}
    local Int = AIP.Integrations
    if not (Int and Int.RaidAchievements and Int.HasAchievement) then return out end
    for _, id in pairs(Int.RaidAchievements) do
        if type(id) == "number" and Int.HasAchievement(id) then
            out[#out + 1] = id
            if #out >= MAX_ACH then break end
        end
    end
    return out
end

-- Build the local player's card.
function CC.BuildMine()
    local slots = {}
    for _, s in ipairs(GEAR_SLOTS) do
        local link = GetInventoryItemLink("player", s)
        if link then
            local itemID = tonumber(link:match("item:(%d+)")) or 0
            local ench = tonumber(link:match("item:%d+:(%d*)")) or 0
            local g1, g2, g3, g4 = link:match("item:%d+:%d*:(%d*):(%d*):(%d*):(%d*)")
            local gems = {}
            for _, g in ipairs({ g1, g2, g3, g4 }) do
                local n = tonumber(g); if n and n > 0 then gems[#gems + 1] = n end
            end
            slots[#slots + 1] = { s = s, i = itemID, e = ench, g = gems }
        end
    end
    local gs = 0
    if AIP.CentralGUI and AIP.CentralGUI.CalculatePlayerGS then gs = AIP.CentralGUI.CalculatePlayerGS() or 0
    elseif AIP.Integrations and AIP.Integrations.GetGearScore then gs = AIP.Integrations.GetGearScore(UnitName("player")) or 0 end
    local ilvl = (AIP.UpgradePath and AIP.UpgradePath.AvgItemLevel and AIP.UpgradePath.AvgItemLevel()) or 0
    return { name = UnitName("player"), gs = math.floor(gs), ilvl = math.floor(ilvl), slots = slots, ach = completedAchievements() }
end

-- Broadcast the card to all peers (target=nil) or one peer (target=name), paged.
function CC.ShareMine(target)
    if not (AIP.DataBus and AIP.DataBus.CreateEvent and AIP.DataBus.Broadcast) then return end
    local card = CC.BuildMine()
    local total = math.max(1, math.ceil(#card.slots / SLOTS_PER_PAGE))
    local function sendPage(idx)
        local page = {}
        for j = (idx - 1) * SLOTS_PER_PAGE + 1, math.min(idx * SLOTS_PER_PAGE, #card.slots) do
            page[#page + 1] = card.slots[j]
        end
        local data = { seq = idx, total = total, name = card.name, slots = page }
        if idx == 1 then data.gs = card.gs; data.ilvl = card.ilvl; data.ach = card.ach end
        local ev = AIP.DataBus.CreateEvent("CARD", data)
        if ev then AIP.DataBus.Broadcast(ev, target) end
    end
    sendPage(1)
    for idx = 2, total do
        if AIP.Utils and AIP.Utils.DelayedCall then
            AIP.Utils.DelayedCall(2.2 * (idx - 1), function() sendPage(idx) end)
        else
            sendPage(idx)
        end
    end
    if AIP.Debug then AIP.Debug("Shared character card (" .. #card.slots .. " slots, " .. #card.ach .. " achievements) to " .. (target or "peers")) end
end

-- Resolve a class token/name (e.g. "DEATHKNIGHT", "Warrior", "DK") to a colour.
-- LFG listings store the uppercase class token, but be defensive about casing/spaces.
local function classColor(classStr)
    if not classStr then return nil end
    local token = tostring(classStr):upper():gsub("[%s%-]", "")
    if token == "DK" then token = "DEATHKNIGHT" end
    if AIP.Composition and AIP.Composition.ClassColors and AIP.Composition.ClassColors[token] then
        return AIP.Composition.ClassColors[token]
    end
    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[token] then return RAID_CLASS_COLORS[token] end
    return nil
end

-- Slots grouped into scannable blocks: armor, then jewelry (rings/trinkets), then
-- weapons. A blank spacer line is inserted before a block that starts a new group.
local CARD_SLOT_ORDER = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }
local GROUP_BREAK = { [11] = true, [16] = true }  -- first ring / main hand start a group

-- Append a player's shared character card to an open GameTooltip as a clean "recruit
-- card": the equipped gear grouped armor -> jewelry -> weapons (each slot E = enchanted /
-- Gn = n gems, item quality coloured) and their achievements, above a GS / iLvl line. If
-- opts.raid names the content the LFG entry targets, the player's BEST achievement for
-- THAT instance is highlighted at the top of the achievements section.
--   opts = { header = <bool>, class = <token>, role = <"Tank"...>, spec = <name>, raid = <"ICC25"...> }
-- With opts.header (the LFG-row tooltip) it also renders a class-coloured name / role - spec
-- - class header and a "No shared card yet" fallback, making it the single source of truth
-- for that tooltip. Without it (appended under a tooltip that already has its own header) it
-- keeps the old contract: render nothing when there is no shared card. Returns true if a
-- full card rendered. For the local player, builds the card live so you see what peers get.
function CC.AppendToTooltip(tooltip, name, isSelf, opts)
    if not (tooltip and name) then return false end
    opts = opts or {}
    local mine = isSelf or name == UnitName("player")
    local card = CC.peerCards and CC.peerCards[name]
    if not card and mine then card = CC.BuildMine() end

    if opts.header then
        -- Class-coloured name.
        local cc = classColor(opts.class)
        if not cc and mine then
            local _, ctoken = UnitClass("player")
            cc = ctoken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[ctoken] or nil
        end
        if cc then tooltip:AddLine(name, cc.r, cc.g, cc.b) else tooltip:AddLine(name, 1, 0.82, 0) end
        -- role - spec - class on one line (only the parts we know).
        local bits = {}
        if opts.role and opts.role ~= "" then bits[#bits + 1] = opts.role end
        if opts.spec and opts.spec ~= "" then bits[#bits + 1] = opts.spec end
        if opts.class and opts.class ~= "" then bits[#bits + 1] = opts.class end
        if #bits > 0 then tooltip:AddLine(table.concat(bits, "  \194\183  "), 0.72, 0.72, 0.78) end
        if not card then
            tooltip:AddLine("No shared character card yet (the player broadcasts it with their LFG listing).", 0.55, 0.55, 0.6, true)
            return false
        end
    else
        -- Appended below a tooltip that owns its own header: keep the old contract of
        -- adding nothing when there is no shared card.
        if not card then return false end
        tooltip:AddLine(" ")
    end

    -- GS / iLvl line.
    tooltip:AddDoubleLine(string.format("GearScore  |cffffffff%d|r", card.gs or 0),
        string.format("iLvl  |cffffffff%d|r", card.ilvl or 0), 0.4, 0.78, 1, 0.4, 0.78, 1)

    -- Gear, grouped for scannability.
    tooltip:AddLine(" ")
    tooltip:AddLine("Gear  |cff888888(E = enchanted, Gn = n gems)|r", 0.9, 0.82, 0.2)
    local IS = AIP.ItemScore
    for _, sid in ipairs(CARD_SLOT_ORDER) do
        local sl = card.slots and card.slots[sid]
        if sl then
            if GROUP_BREAK[sid] then tooltip:AddLine(" ") end
            local iname, _, q = GetItemInfo(sl.i)
            local qc = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
            local label = (IS and IS.SLOT_NAME and IS.SLOT_NAME[sid]) or ("Slot " .. sid)
            local flags = ""
            if sl.e and sl.e ~= 0 then flags = flags .. " |cff40ff40E|r" end
            local ng = sl.g and #sl.g or 0
            if ng > 0 then flags = flags .. " |cff40a0ffG" .. ng .. "|r" end
            tooltip:AddDoubleLine(label, (iname or ("item:" .. (sl.i or "?"))) .. flags,
                0.6, 0.6, 0.66, qc and qc.r or 0.9, qc and qc.g or 0.9, qc and qc.b or 0.9)
        end
    end

    -- Achievements. Highlight the best one for the targeted instance (if any) at the top.
    local achSet = {}
    if card.ach then for _, id in ipairs(card.ach) do achSet[id] = true end end
    local bestId, bestName
    local Int = AIP.Integrations
    if opts.raid and Int and Int.RaidToInstanceKey and Int.BestAchievementFor then
        local instKey = Int.RaidToInstanceKey(opts.raid)
        if instKey then
            bestId, bestName = Int.BestAchievementFor(instKey, function(id) return achSet[id] end)
        end
    end

    if bestId or (card.ach and #card.ach > 0) then
        tooltip:AddLine(" ")
        tooltip:AddLine("Achievements", 0.9, 0.82, 0.2)
        if bestId then
            local _, aname = GetAchievementInfo(bestId)
            tooltip:AddLine("  \226\152\133 " .. (bestName or aname or ("#" .. bestId))
                .. "  |cffcc9900(best for " .. opts.raid .. ")|r", 1, 0.82, 0)
        end
        for _, aid in ipairs(card.ach or {}) do
            if aid ~= bestId then
                local _, aname = GetAchievementInfo(aid)
                tooltip:AddLine("  " .. (aname or ("#" .. aid)), 0.5, 0.9, 0.5)
            end
        end
    end
    return true
end

-- Receive a page: accumulate, assemble when all pages arrive.
local function onCard(event)
    if not (event and event.sender and event.data) then return end
    if event.sender == UnitName("player") then return end
    local d = event.data
    local buf = pending[event.sender] or { slots = {}, seqs = {} }
    pending[event.sender] = buf
    buf.name = d.name or event.sender
    buf.total = d.total or 1
    if d.seq then buf.seqs[d.seq] = true end
    if d.gs then buf.gs = d.gs end
    if d.ilvl then buf.ilvl = d.ilvl end
    if d.ach then buf.ach = d.ach end
    for _, sl in ipairs(d.slots or {}) do if sl.s then buf.slots[sl.s] = sl end end
    local got = 0; for _ in pairs(buf.seqs) do got = got + 1 end
    if got >= (buf.total or 1) then
        CC.peerCards[buf.name] = { name = buf.name, gs = buf.gs or 0, ilvl = buf.ilvl or 0,
            slots = buf.slots, ach = buf.ach or {}, ts = time() }
        pending[event.sender] = nil
    end
end

-- Subscribe on login (DataBus loads first; guard anyway).
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if AIP.DataBus and AIP.DataBus.Subscribe then
        AIP.DataBus.Subscribe("CARD", onCard, "CharCard")
    end
end)
