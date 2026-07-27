-- AutoInvite Plus - FitEngine
-- THE single fit verdict for the matchmaking loop. Every judgment about
-- "does this player fit this listing" / "does this listing fit me" comes
-- from here, so the auto-inviter, the auto-queue, the queue-panel chips,
-- the browser chips and the match alerts can never disagree.
--
-- Verdicts:
--   RED    - a hard fail (blacklist, GS below minimum, role already full,
--            raid mismatch, saved to the instance). Never auto-acted on.
--   GREEN  - score >= 75 with no soft concerns. The only verdict the opt-in
--            auto actions (autoInviteGreen / autoApplyGreen) may act on.
--   YELLOW - everything else, including "not enough data". Missing data
--            never hard-fails; it caps the verdict at YELLOW with a reason.

local AIP = AutoInvitePlus
AIP.FitEngine = AIP.FitEngine or {}
local Fit = AIP.FitEngine

Fit.GREEN_THRESHOLD = 75

local function addReason(r, text)
    r[#r + 1] = text
end

local function clamp(score)
    return math.max(0, math.min(100, score))
end

-- {current, needed} helper: is there an open slot for this role?
local function roleOpen(listing, roleKey)
    local slot = listing and listing[roleKey]
    if type(slot) ~= "table" then return nil end  -- unknown
    return (slot.needed or 0) > (slot.current or 0)
end

-- Map a role string (TANK/HEALER/MDPS/RDPS/DPS + MELEE/RANGED aliases some
-- peers send) to the listing slot key(s)
local function roleSlots(role)
    local upper = role and role:upper() or nil
    if upper == "TANK" then return { "tanks" } end
    if upper == "HEALER" then return { "healers" } end
    if upper == "MDPS" or upper == "MELEE" then return { "mdps" } end
    if upper == "RDPS" or upper == "RANGED" then return { "rdps" } end
    if upper == "DPS" then return { "mdps", "rdps" } end
    return nil
end

local function finalize(score, reasons, hardFail, softFail)
    score = clamp(score)
    local verdict
    if hardFail then
        verdict = "RED"
        score = math.min(score, 25)
    elseif score >= Fit.GREEN_THRESHOLD and not softFail then
        verdict = "GREEN"
    else
        verdict = "YELLOW"
    end
    return { score = score, verdict = verdict, reasons = reasons }
end

-- ============================================================================
-- LEADER SIDE: does this applicant fit my listing?
-- applicant: {name, role, class, spec, gs, ilvl, weekly, raid?}
-- listing:   GUI.MyGroup / CS.Groups shape: {raid, gsMin, ilvlMin, roleSpecs,
--            tanks/healers/mdps/rdps = {current, needed}, weekly}
-- ============================================================================
function Fit.ScoreApplicant(applicant, listing, opts)
    local reasons = {}
    local score = 50
    local hardFail, softFail = false, false
    if not applicant then return finalize(0, { "no applicant data" }, true) end
    listing = listing or {}
    opts = opts or {}

    -- Blacklist is an absolute no - unless the caller handles blacklist
    -- policy itself (the smart-invite gate: blacklistMode "flag" means
    -- blacklisted players still queue, just marked)
    if not opts.ignoreBlacklist and applicant.name and AIP.IsBlacklisted and AIP.IsBlacklisted(applicant.name) then
        addReason(reasons, "blacklisted")
        return finalize(0, reasons, true)
    end

    -- Raid match (only when both sides name one, e.g. an LFG player's target raid)
    if applicant.raid and listing.raid and applicant.raid ~= "" and listing.raid ~= "" then
        if applicant.raid:upper() ~= listing.raid:upper() then
            addReason(reasons, "wants " .. applicant.raid .. ", not " .. listing.raid)
            hardFail = true
        end
    end

    -- GearScore vs listing minimum
    local gsMin = tonumber(listing.gsMin) or 0
    local gs = tonumber(applicant.gs) or 0
    if gsMin > 0 then
        if gs <= 0 then
            addReason(reasons, "no GS info")
            softFail = true
        elseif gs < gsMin then
            addReason(reasons, "GS " .. gs .. " below " .. gsMin .. "+ requirement")
            hardFail = true
        else
            score = score + 15
            if gs >= gsMin + 300 then score = score + 5 end
            addReason(reasons, "GS " .. gs .. " meets " .. gsMin .. "+")
        end
    end

    -- Item level vs listing minimum (soft unless clearly stated and failed)
    local ilvlMin = tonumber(listing.ilvlMin) or 0
    local ilvl = tonumber(applicant.ilvl) or 0
    if ilvlMin > 0 and ilvl > 0 and ilvl < ilvlMin then
        addReason(reasons, "iLvl " .. ilvl .. " below " .. ilvlMin .. "+")
        hardFail = true
    end

    -- Role need against live composition counts
    local slots = roleSlots(applicant.role)
    local roleHasOpenSlot -- nil = unknown, used below to keep the classNeeds reason non-contradictory
    if slots then
        local anyOpen, anyKnown = false, false
        for _, key in ipairs(slots) do
            local open = roleOpen(listing, key)
            if open ~= nil then anyKnown = true end
            if open then anyOpen = true end
        end
        if anyKnown then roleHasOpenSlot = anyOpen end
        if anyKnown and not anyOpen then
            addReason(reasons, (applicant.role or "role") .. " slots already full")
            hardFail = true
        elseif anyOpen then
            score = score + 20
            addReason(reasons, (applicant.role or "role") .. " needed")
        end
    else
        addReason(reasons, "no role stated")
        softFail = true
    end

    -- Spec match against the listing's Looking-For array (neutral when absent)
    if listing.roleSpecs and applicant.class then
        local hasAny = false
        for _, specs in pairs(listing.roleSpecs) do
            if specs and #specs > 0 then hasAny = true break end
        end
        if hasAny and AIP.Parsers and AIP.Parsers.MatchesLookingFor then
            local roleUpper = applicant.role and applicant.role:upper() or nil
            if AIP.Parsers.MatchesLookingFor(applicant.class:upper(), nil, roleUpper, listing.roleSpecs) then
                score = score + 10
                addReason(reasons, "class/spec is on the Looking-For list")
            else
                score = score - 20
                addReason(reasons, "class/spec not on the Looking-For list")
                softFail = true
            end
        end
    end

    -- Class-need coverage from the composition tandem (listing.classNeeds =
    -- {{class, role, count}} from Comp.GetClassNeeds). Being on the need list
    -- is a strong plus; a class with zero open need means that position is
    -- already covered by another player - a soft concern only, because the
    -- role-full check above already hard-fails when the whole role is closed.
    if listing.classNeeds and #listing.classNeeds > 0 and applicant.class then
        local cls = applicant.class:upper()
        -- nil role stays nil (no role filter); anything else folds to T/H/D
        local roleUpper = applicant.role and AIP.Utils.FoldRole(applicant.role) or nil
        local needed = 0
        for _, n in ipairs(listing.classNeeds) do
            if n.class and n.class:upper() == cls
                and (not roleUpper or not n.role or n.role == roleUpper) then
                needed = needed + (n.count or 0)
            end
        end
        local prettyClass = cls:sub(1, 1) .. cls:sub(2):lower()
        if needed > 0 then
            score = score + 15
            addReason(reasons, needed .. "x " .. prettyClass .. " needed")
        elseif roleHasOpenSlot == false then
            -- The role itself has no open slots at all - "position covered" is
            -- accurate here and matches the hard-fail reason already added above.
            score = score - 5
            addReason(reasons, "no open " .. prettyClass .. " need right now - position covered")
        else
            -- Informational only: class needs come from the composition
            -- TEMPLATE and can lag the leader's hand-edited role counts, so a
            -- missing class must never block GREEN (no softFail) - the role
            -- gate above already hard-fails when the role is truly full. The
            -- role itself is still open (or unknown), so don't claim "covered"
            -- - that would contradict the "<role> needed" reason in the same
            -- whisper.
            score = score - 5
            addReason(reasons, prettyClass .. " isn't the current recruiting pick, but " .. (applicant.role or "the role") .. " is still open")
        end
    end

    -- Social signals
    if applicant.name then
        if AIP.IsPlayerFavorite and AIP.IsPlayerFavorite(applicant.name) then
            score = score + 15
            addReason(reasons, "favorite")
        end
        if AIP.IsPlayerInGuild and AIP.IsPlayerInGuild(applicant.name) then
            score = score + 10
            addReason(reasons, "guildmate")
        end
    end

    -- Weekly overlap: they still need the weekly this listing runs
    if listing.weekly and applicant.weekly
        and listing.weekly:lower() == applicant.weekly:lower() then
        score = score + 10
        addReason(reasons, "needs this weekly too")
    end

    return finalize(score, reasons, hardFail, softFail)
end

-- ============================================================================
-- SEEKER SIDE: does this listing fit me?
-- listing: CS.Groups shape (see above) + leader
-- me:      {role, class, spec, gs, ilvl} (defaults from my enrollment)
-- ============================================================================
function Fit.ScoreListing(listing, me)
    local reasons = {}
    local score = 50
    local hardFail, softFail = false, false
    if not listing then return finalize(0, { "no listing" }, true) end
    me = me or {}

    -- Leader on my blacklist
    if listing.leader and AIP.IsBlacklisted and AIP.IsBlacklisted(listing.leader) then
        addReason(reasons, "leader is blacklisted")
        return finalize(0, reasons, true)
    end

    -- Saved to that instance already
    if listing.raid and AIP.TreeBrowser and AIP.TreeBrowser.IsLockedToInstance then
        if AIP.TreeBrowser.IsLockedToInstance(listing.raid) then
            addReason(reasons, "you are saved to " .. listing.raid)
            hardFail = true
        end
    end

    -- My GS vs their requirement
    local gsMin = tonumber(listing.gsMin) or 0
    local myGs = tonumber(me.gs) or 0
    if gsMin > 0 then
        if myGs <= 0 then
            addReason(reasons, "your GS unknown")
            softFail = true
        elseif myGs < gsMin then
            addReason(reasons, "your GS " .. myGs .. " below their " .. gsMin .. "+")
            hardFail = true
        else
            score = score + 15
            addReason(reasons, "you meet the " .. gsMin .. "+ requirement")
        end
    end

    -- Do they need my role?
    local slots = roleSlots(me.role)
    local roleHasOpenSlot -- nil = unknown, reused below by the classNeeds check
    if slots then
        local anyOpen, anyKnown = false, false
        for _, key in ipairs(slots) do
            local open = roleOpen(listing, key)
            if open ~= nil then anyKnown = true end
            if open then anyOpen = true end
        end
        if anyKnown then roleHasOpenSlot = anyOpen end
        if anyKnown and not anyOpen then
            addReason(reasons, "their " .. (me.role or "role") .. " slots are full")
            hardFail = true
        elseif anyOpen then
            score = score + 20
            addReason(reasons, "they need a " .. (me.role or "player"))
        end
    end

    -- Class-need coverage from the composition tandem, symmetric with
    -- ScoreApplicant's classNeeds block: listing.classNeeds = {{class, role,
    -- count}} rides the listing (ChatScanner/DataBus), so a browser/match-alert
    -- viewer gets the same "they specifically need your class" signal a leader
    -- already sees for an incoming applicant.
    if listing.classNeeds and #listing.classNeeds > 0 and me.class then
        local cls = me.class:upper()
        local roleUpper = me.role and AIP.Utils.FoldRole(me.role) or nil
        local needed = 0
        for _, n in ipairs(listing.classNeeds) do
            if n.class and n.class:upper() == cls
                and (not roleUpper or not n.role or n.role == roleUpper) then
                needed = needed + (n.count or 0)
            end
        end
        if needed > 0 then
            score = score + 15
            addReason(reasons, "they need " .. needed .. "x your class")
        elseif roleHasOpenSlot == false then
            score = score - 5
            addReason(reasons, "no open need for your class right now - position covered")
        else
            score = score - 5
            addReason(reasons, "your class isn't their current recruiting pick, but " .. (me.role or "the role") .. " is still open")
        end
    end

    -- Am I on their Looking-For list?
    if listing.roleSpecs and me.class then
        local hasAny = false
        for _, specs in pairs(listing.roleSpecs) do
            if specs and #specs > 0 then hasAny = true break end
        end
        if hasAny and AIP.Parsers and AIP.Parsers.MatchesLookingFor then
            local roleUpper = me.role and me.role:upper() or nil
            if AIP.Parsers.MatchesLookingFor(me.class:upper(), nil, roleUpper, listing.roleSpecs) then
                score = score + 10
                addReason(reasons, "they want your class/spec")
            else
                score = score - 20
                addReason(reasons, "your class/spec is not on their list")
                softFail = true
            end
        end
    end

    -- Weekly: this listing runs a weekly I still need
    if listing.weekly and AIP.Weekly and AIP.Weekly.IsWanted and AIP.Weekly.IsWanted(listing.weekly) then
        score = score + 15
        addReason(reasons, "runs a weekly you still need")
    end

    -- Favorite leader
    if listing.leader and AIP.IsPlayerFavorite and AIP.IsPlayerFavorite(listing.leader) then
        score = score + 10
        addReason(reasons, "favorite leader")
    end

    return finalize(score, reasons, hardFail, softFail)
end

-- ============================================================================
-- DISPLAY HELPERS
-- ============================================================================

Fit.Colors = {
    GREEN = "|cFF00FF00",
    YELLOW = "|cFFFFD100",
    RED = "|cFFFF4444",
}

-- Compact colored chip for row prefixes: "|cFF00FF00[85]|r"
function Fit.Chip(result)
    if not result then return "" end
    local color = Fit.Colors[result.verdict] or "|cFFAAAAAA"
    return color .. "[" .. tostring(result.score) .. "]|r"
end

-- Multi-line reasons text for tooltips
function Fit.ReasonsText(result)
    if not result or not result.reasons or #result.reasons == 0 then return "" end
    return table.concat(result.reasons, "\n")
end

-- Build a "me" table for ScoreListing from the active enrollment (or live stats)
function Fit.Me()
    local GUI = AIP.CentralGUI
    local enr = GUI and GUI.MyEnrollment
    if enr then
        return { role = enr.role, class = enr.class, spec = enr.spec, gs = enr.gs, ilvl = enr.ilvl }
    end
    local _, class = UnitClass("player")
    return {
        role = GUI and GUI.DetectPlayerRole and GUI.DetectPlayerRole() or nil,
        class = class,
        spec = GUI and GUI.GetPlayerSpecName and GUI.GetPlayerSpecName() or nil,
        gs = GUI and GUI.CalculatePlayerGS and GUI.CalculatePlayerGS() or 0,
        ilvl = GUI and GUI.CalculatePlayerIlvl and GUI.CalculatePlayerIlvl() or 0,
    }
end

-- /aip fit <name>: print the verdict for a queued/scanned player against my
-- listing, or (with no active listing) a scanned listing's fit for me.
function Fit.SlashHandler(rest)
    local name = (rest or ""):trim()
    if name == "" then
        AIP.Print("Usage: /aip fit <player or leader name>")
        return
    end
    local GUI = AIP.CentralGUI

    -- Applicant against my listing
    if GUI and GUI.MyGroup then
        local applicant
        if AIP.db and AIP.db.queue then
            for _, e in ipairs(AIP.db.queue) do
                if e.name and e.name:lower() == name:lower() then applicant = e break end
            end
        end
        if not applicant and AIP.ChatScanner and AIP.ChatScanner.Players then
            for pname, p in pairs(AIP.ChatScanner.Players) do
                if pname:lower() == name:lower() then applicant = p break end
            end
        end
        if applicant then
            local r = Fit.ScoreApplicant(applicant, GUI.MyGroup)
            AIP.Print(Fit.Chip(r) .. " " .. name .. " vs your " .. (GUI.MyGroup.raid or "listing") .. ":")
            for _, reason in ipairs(r.reasons) do AIP.Print("   - " .. reason) end
            return
        end
    end

    -- Listing fit for me
    if AIP.ChatScanner and AIP.ChatScanner.Groups then
        for leader, group in pairs(AIP.ChatScanner.Groups) do
            if leader:lower() == name:lower() then
                local r = Fit.ScoreListing(group, Fit.Me())
                AIP.Print(Fit.Chip(r) .. " " .. leader .. "'s " .. (group.raid or "?") .. " for you:")
                for _, reason in ipairs(r.reasons) do AIP.Print("   - " .. reason) end
                return
            end
        end
    end

    AIP.Print("No queued player or scanned listing named '" .. name .. "' found.")
end
