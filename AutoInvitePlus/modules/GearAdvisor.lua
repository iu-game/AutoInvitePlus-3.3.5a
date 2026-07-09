-- AutoInvite Plus - Gear Advisor (best-from-what-you-own + enchant/gem audit)
-- Uses AIP.ItemScore to rank the gear you actually carry and to catch un-enchanted
-- slots / empty gem sockets. Also PEER-SHARES each AIP user's own audit summary
-- over the DataBus, so the raid sees everyone's enchant/gem/score status WITHOUT
-- anyone running an inspect (the "faster inspect" - zero inspection for AIP users).

local AIP = AutoInvitePlus
if not AIP then return end

AIP.GearAdvisor = AIP.GearAdvisor or {}
local GA = AIP.GearAdvisor
local IS = AIP.ItemScore

-- Slots that everyone can put a permanent enchant on (common set; rings are
-- enchanter-only, off-hand/ranged are situational, so we skip those to avoid
-- false "missing enchant" flags).
local ENCHANTABLE = { [1]="Head",[3]="Shoulder",[5]="Chest",[7]="Legs",[8]="Feet",
                      [9]="Wrist",[10]="Hands",[15]="Back",[16]="Weapon" }

-- All real gear slots (skip shirt 4 / tabard 19).
local GEAR_SLOTS = {1,2,3,5,6,7,8,9,10,11,12,13,14,15,16,17,18}

-- Armor subclass a class can wear at 80 (for best-from-bags filtering).
local CLASS_ARMOR = {
    WARRIOR="Plate", PALADIN="Plate", DEATHKNIGHT="Plate",
    HUNTER="Mail", SHAMAN="Mail",
    ROGUE="Leather", DRUID="Leather",
    MAGE="Cloth", PRIEST="Cloth", WARLOCK="Cloth",
}
local ARMOR_RANK = { Cloth=1, Leather=2, Mail=3, Plate=4 }

-- INVTYPE -> candidate equip slot(s). Shared with ItemScore (loaded first) to
-- avoid a duplicate copy that could drift out of sync.
local INVTYPE_SLOTS = AIP.ItemScore.INVTYPE_SLOTS

-- ---- hidden tooltip for empty-socket detection ----
local tip
local function ensureTip()
    if tip then return tip end
    tip = CreateFrame("GameTooltip", "AIPGearAdvisorTip", nil, "GameTooltipTemplate")
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    return tip
end

local EMPTY_SOCKET_TEXTS = {
    [EMPTY_SOCKET_RED or "Red Socket"] = true,
    [EMPTY_SOCKET_YELLOW or "Yellow Socket"] = true,
    [EMPTY_SOCKET_BLUE or "Blue Socket"] = true,
    [EMPTY_SOCKET_META or "Meta Socket"] = true,
    [EMPTY_SOCKET_PRISMATIC or "Prismatic Socket"] = true,
}

local function emptySockets(slot)
    local t = ensureTip()
    t:ClearLines()
    local link = GetInventoryItemLink("player", slot)
    if not link then return 0 end
    pcall(function() t:SetInventoryItem("player", slot) end)
    local n = 0
    for i = 1, t:NumLines() do
        local fs = _G["AIPGearAdvisorTipTextLeft" .. i]
        local txt = fs and fs:GetText()
        if txt and EMPTY_SOCKET_TEXTS[txt] then n = n + 1 end
    end
    return n
end

-- enchantId from the item link's 10-field WotLK item string (field 2).
local function enchantId(link)
    if not link then return nil end
    local id = link:match("item:%d+:(%d*)")
    return tonumber(id) or 0
end

-- ============================================================================
-- Audit: missing enchants + empty sockets on equipped gear
-- ============================================================================
function GA.Audit()
    local missingEnch, emptyGem = {}, 0
    for slot, label in pairs(ENCHANTABLE) do
        local link = GetInventoryItemLink("player", slot)
        if link and enchantId(link) == 0 then
            missingEnch[#missingEnch + 1] = label
        end
    end
    for _, slot in ipairs(GEAR_SLOTS) do
        emptyGem = emptyGem + emptySockets(slot)
    end
    return missingEnch, emptyGem
end

-- Per-slot audit for the character-sheet overlay: is this slot missing its
-- permanent enchant, and how many empty gem sockets does it have?
function GA.SlotAudit(slot)
    local link = GetInventoryItemLink("player", slot)
    if not link then return false, 0 end
    local missing = ENCHANTABLE[slot] and enchantId(link) == 0 or false
    return missing, emptySockets(slot)
end

-- ============================================================================
-- Best-from-what-you-own: scan bags for a piece that out-scores the equipped
-- item in its slot (cap-aware, spec-aware, armor/weapon-type filtered).
-- ============================================================================
local function canUseArmor(class, subType)
    if not subType or not ARMOR_RANK[subType] then return true end  -- non-armor (weapon/relic) handled elsewhere
    local max = CLASS_ARMOR[class]
    return ARMOR_RANK[subType] <= (ARMOR_RANK[max] or 4)
end

function GA.BestFromBags()
    if not IS then return {} end
    local _, class = UnitClass("player")
    local scale = IS.GetScale()
    local caps = IS.CurrentCaps()
    local finds = {}

    -- Hand/spec awareness so we never suggest a 1H for the off-hand of a 2H user
    -- (the Shadowmourne-vs-tank-1H-sword bug), and never offer off-hand weapons
    -- to classes that can't dual-wield.
    local mhLink = GetInventoryItemLink("player", 16)
    local mh2H = mhLink and select(9, GetItemInfo(mhLink)) == "INVTYPE_2HWEAPON" or false
    local canDW = (class == "WARRIOR" or class == "ROGUE" or class == "DEATHKNIGHT" or class == "HUNTER" or class == "SHAMAN")

    -- Pre-score equipped items per slot.
    local equippedScore = {}
    for _, slot in ipairs(GEAR_SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local st = IS.GetStats(link)
            equippedScore[slot] = st and IS.Score(st, scale, caps) or 0
        else
            equippedScore[slot] = 0
        end
    end

    for bag = 0, 4 do
        for s = 1, (GetContainerNumSlots(bag) or 0) do
            local link = GetContainerItemLink(bag, s)
            if link then
                local _, _, quality, _, _, _, subType, _, equipLoc = GetItemInfo(link)
                local slots = equipLoc and INVTYPE_SLOTS[equipLoc]
                -- Hand/dual-wield aware weapon slotting.
                if equipLoc == "INVTYPE_2HWEAPON" then slots = { 16 }
                elseif equipLoc == "INVTYPE_WEAPONMAINHAND" then slots = (not mh2H) and { 16 } or nil
                elseif equipLoc == "INVTYPE_WEAPONOFFHAND" then slots = (not mh2H and canDW) and { 17 } or nil
                elseif equipLoc == "INVTYPE_WEAPON" then
                    if mh2H then slots = nil                      -- using a 2H: a 1H is not an upgrade
                    elseif canDW then slots = { 16, 17 } else slots = { 16 } end
                elseif equipLoc == "INVTYPE_HOLDABLE" or equipLoc == "INVTYPE_SHIELD" then
                    if mh2H then slots = nil end                  -- can't use an off-hand while wielding a 2H
                end
                if slots and quality and quality >= 2 then   -- uncommon+
                    local usable = true
                    if ARMOR_RANK[subType] then usable = canUseArmor(class, subType) end
                    if usable then
                        local st = IS.GetStats(link)
                        local score = st and IS.Score(st, scale, caps) or 0
                        if score > 0 then
                            -- best candidate slot = the one with the lowest equipped score
                            local target, targetScore
                            for _, slot in ipairs(slots) do
                                if not target or equippedScore[slot] < targetScore then
                                    target, targetScore = slot, equippedScore[slot]
                                end
                            end
                            if target and score > (targetScore or 0) * 1.02 then  -- >2% better
                                local pct = (targetScore and targetScore > 0) and ((score/targetScore - 1) * 100) or 100
                                finds[#finds + 1] = { link = link, slot = target,
                                    score = score, equipped = targetScore or 0, pct = pct }
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(finds, function(a, b) return a.pct > b.pct end)
    return finds
end

-- ============================================================================
-- Report
-- ============================================================================
function GA.Report()
    if not IS then AIP.Print("Gear advisor needs the ItemScore module."); return end
    local arch = IS.PlayerArchetype()
    AIP.Print("|cFF66CCFFGear Advisor|r (spec profile: " .. arch .. ")")

    local missing, sockets = GA.Audit()
    if #missing > 0 then
        AIP.Print("  |cFFFF6060Missing enchants:|r " .. table.concat(missing, ", "))
    end
    if sockets > 0 then
        AIP.Print("  |cFFFF6060Empty gem sockets:|r " .. sockets)
    end
    if #missing == 0 and sockets == 0 then
        AIP.Print("  |cFF00FF00Enchants & gems: all filled.|r")
    end

    local finds = GA.BestFromBags()
    if #finds == 0 then
        AIP.Print("  |cFF00FF00No upgrades sitting in your bags.|r")
    else
        AIP.Print("  |cFFFFFF00Upgrades in your bags:|r")
        for i = 1, math.min(#finds, 6) do
            local f = finds[i]
            AIP.Print(string.format("   %s -> %s slot (+%.0f%%)",
                f.link, ENCHANTABLE[f.slot] or ("#" .. f.slot), f.pct))
        end
    end

    -- Share my summary so peers don't need to inspect me.
    GA.BroadcastMine(#missing, sockets)
end

-- ============================================================================
-- Peer share over the DataBus (GEAR event) - "faster inspect"
-- ============================================================================
function GA.BroadcastMine(missingCount, socketCount)
    if not (AIP.DataBus and AIP.DataBus.Broadcast and AIP.DataBus.CreateEvent) then return end
    if not (AIP.db and AIP.db.gearShare) then return end
    if not missingCount then
        local m, sk = GA.Audit(); missingCount, socketCount = #m, sk
    end
    local gs = 0
    if AIP.Integrations and AIP.Integrations.GetGearScore then
        gs = AIP.Integrations.GetGearScore(UnitName("player")) or 0
    end
    local ev = AIP.DataBus.CreateEvent("GEAR", {
        arch = IS and IS.PlayerArchetype() or "?",
        missing = missingCount or 0,
        sockets = socketCount or 0,
        gs = gs,
    })
    if ev then AIP.DataBus.Broadcast(ev) end
end

GA.peerGear = {}   -- name -> {arch, missing, sockets, gs, ts}
local function onGear(event)
    if not event or not event.sender then return end
    GA.peerGear[event.sender] = {
        arch = event.data.arch, missing = event.data.missing or 0,
        sockets = event.data.sockets or 0, gs = event.data.gs or 0, ts = time(),
    }
end

-- Show the raid's shared gear-readiness (AIP users only; no inspection needed).
function GA.RaidReport()
    local now = time()
    local rows = {}
    for name, g in pairs(GA.peerGear) do
        if (now - (g.ts or 0)) < 900 then rows[#rows + 1] = { name = name, g = g } end
    end
    if #rows == 0 then
        AIP.Print("No shared gear data yet (AIP users broadcast theirs on /aip gear).")
        return
    end
    table.sort(rows, function(a, b) return (a.g.missing + a.g.sockets) > (b.g.missing + b.g.sockets) end)
    AIP.Print("|cFF66CCFFRaid gear readiness|r (shared by AIP users - no inspect):")
    for _, r in ipairs(rows) do
        local flag = (r.g.missing > 0 or r.g.sockets > 0)
            and string.format("|cFFFF6060%d ench / %d sockets missing|r", r.g.missing, r.g.sockets)
            or "|cFF00FF00ready|r"
        AIP.Print(string.format("  %s (%s): %s", r.name, r.g.arch or "?", flag))
    end
end

-- ============================================================================
-- Init: subscribe to GEAR events once the DataBus is up.
-- ============================================================================
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if AIP.DataBus and AIP.DataBus.Subscribe then
        AIP.DataBus.Subscribe("GEAR", onGear, "GearAdvisor")
    end
end)
