-- AutoInvite Plus - LFGWatch
-- Reads the WotLK 3.3.5a Dungeon Finder (RDF) queue state: which dungeons you're
-- queued for, queue stage, role needs, wait-time estimates, and the ready-check
-- proposal (rolled instance + who's accepted). Uses ONLY APIs confirmed present
-- in 3.3.5a FrameXML; every getter is guarded so a core that stubs LFG can't error.
--
-- Hard limit of the 3.3.5a client: there is NO numeric queue position - Blizzard
-- exposes role needs + wait-time estimates only, so this never fakes a "#N".

local AIP = AutoInvitePlus
if not AIP then return end
AIP.LFGWatch = AIP.LFGWatch or {}
local LW = AIP.LFGWatch

LW.State = { mode = nil, submode = nil, elapsed = 0, stats = nil,
    dungeons = {}, proposal = nil, roles = nil, queueStartTime = nil }

local function fmtTime(s)
    s = math.floor(tonumber(s) or 0)
    if s <= 0 then return "0s" end
    if s < 60 then return s .. "s" end
    return math.floor(s / 60) .. "m " .. (s % 60) .. "s"
end

-- Some 3.3.5a cores return string fields (names/roles) as booleans; coerce to a
-- real string-or-nil so `x or "?"` fallbacks and concatenations can't error.
local function asStr(v) return (type(v) == "string" and v) or nil end

-- ============================================================================
-- Readers (defensive - guarded + pcall'd; return nil when not applicable)
-- ============================================================================
local function readStats()
    if not GetLFGQueueStats then return nil end
    -- 3.3.5a returns 17 values; the exact category arg varies by core, so call
    -- bare and rely on hasData. (No activeID/18th value on 3.3.5a.)
    local ok, hasData, leaderNeeds, tankNeeds, healerNeeds, dpsNeeds,
        totalTanks, totalHealers, totalDPS, instanceType, _instanceSubType,
        instanceName, averageWait, tankWait, healerWait, damageWait, myWait, queuedTime
        = pcall(GetLFGQueueStats)
    if not ok or not hasData then return nil end
    local num = function(v) return tonumber(v) or 0 end
    -- Some 3.3.5a cores return these as a real boolean/1-or-nil, others as a
    -- numeric count still needed - and 0 is TRUTHY in Lua, so a plain
    -- `if tankNeeds then` reads a count of 0 as "still needs a tank" and the
    -- needs list never reflects reality. Normalize both encodings to a real
    -- boolean here instead.
    local function needBool(v) return (v ~= nil and v ~= false and v ~= 0) end
    return {
        instanceName = asStr(instanceName), instanceType = instanceType,
        dpsNeedCount = (type(dpsNeeds) == "number") and dpsNeeds or nil,   -- open DPS slots, when the core reports a count
        needs  = { leader = needBool(leaderNeeds), tank = needBool(tankNeeds),
            healer = needBool(healerNeeds), dps = needBool(dpsNeeds) },
        totals = { tanks = num(totalTanks), healers = num(totalHealers), dps = num(totalDPS) },
        wait   = { average = num(averageWait), tank = num(tankWait), healer = num(healerWait), dps = num(damageWait), mine = num(myWait) },
        queuedTime = tonumber(queuedTime),   -- nil if non-numeric; elapsed math guards for nil
    }
end

local queuedScratch = {}   -- reused table filled in place by GetLFGQueuedList
local function readDungeons()
    local out = {}
    if not (GetLFGQueuedList and GetLFGDungeonInfo) then return out end
    for k in pairs(queuedScratch) do queuedScratch[k] = nil end
    local ok, ret = pcall(GetLFGQueuedList, queuedScratch)
    -- Some cores return the filled table instead of (or as well as) filling the arg.
    local src = (ok and type(ret) == "table") and ret or queuedScratch
    for id, state in pairs(src) do
        if state then
            local name = asStr(GetLFGDungeonInfo(id))
            out[#out + 1] = { id = id, name = name or ("Dungeon " .. tostring(id)) }
        end
    end
    return out
end

-- Pure parser for GetLFGProposal() returns. The signature differs between
-- cores/builds (11 vs 12 values: subtypeID is not always present), so fields are
-- picked by TYPE and position-from-the-end, never by a fixed count:
--   exists, id, typeID, [subtypeID], name, texture, role, hasResponded,
--   totalEncounters, completedEncounters, numMembers, isLeader
-- Never errors on nil/short returns. Returns nil when no proposal exists.
local ROLE_WORDS = { TANK = true, HEALER = true, DAMAGER = true, NONE = true, LEADER = true }
function LW.ParseProposal(...)
    local n = select("#", ...)
    local exists = ...
    if not exists then return nil end
    local nums, strs, bools = {}, {}, {}
    for i = 2, n do
        local v = select(i, ...)
        local t = type(v)
        if t == "number" then nums[#nums + 1] = v
        elseif t == "string" then strs[#strs + 1] = v
        elseif t == "boolean" then bools[#bools + 1] = v end
    end
    local name, role
    for _, v in ipairs(strs) do
        if ROLE_WORDS[v] then role = role or v
        elseif not name and not v:find("\\") then name = v end   -- skip texture paths
    end
    local c = #nums
    local id = nums[1]
    local numMembers, completed, total
    if c >= 4 then
        numMembers, completed, total = nums[c], nums[c - 1], nums[c - 2]
    end
    return { id = id, name = name, role = role, hasResponded = bools[1],
        totalEncounters = total, completedEncounters = completed,
        numMembers = numMembers, isLeader = bools[2] }
end

local function readProposal()
    if not GetLFGProposal then return nil end
    local okc, p = pcall(function() return LW.ParseProposal(GetLFGProposal()) end)
    if not okc or not p then return nil end
    local members = {}
    -- numMembers may be missing/non-number; fall back to 5 (dungeon proposals are
    -- always 5; members past the real count just read as nil) so it's never a raw 'for' limit.
    local n = tonumber(p.numMembers) or 5
    if GetLFGProposalMember then
        for i = 1, n do
            local okm, _mLeader, mRole, _mLevel, mResponded, mAccepted = pcall(GetLFGProposalMember, i)
            if not okm then mRole, mResponded, mAccepted = nil, nil, nil end
            members[i] = { role = asStr(mRole), responded = mResponded, accepted = mAccepted }
        end
    end
    return { id = p.id, name = asStr(p.name), role = asStr(p.role), hasResponded = p.hasResponded,
        bosses = { done = tonumber(p.completedEncounters) or 0, total = tonumber(p.totalEncounters) or 0 },
        numMembers = n, isLeader = p.isLeader, members = members }
end

local function readRoles()
    if not GetLFGRoles then return nil end
    local leader, tank, healer, dps = GetLFGRoles()
    return { leader = leader, tank = tank, healer = healer, dps = dps }
end

-- ============================================================================
-- Refresh + accessors
-- ============================================================================
function LW.Refresh()
    local prevMode = LW.State.mode
    if GetLFGMode then LW.State.mode, LW.State.submode = GetLFGMode() else LW.State.mode = nil end
    LW.State.stats = readStats()
    LW.State.dungeons = readDungeons()
    LW.State.proposal = readProposal()
    LW.State.roles = readRoles()

    -- Elapsed queue time. Some 3.3.5a cores return a `queuedTime` field from
    -- GetLFGQueueStats() that isn't a usable GetTime()-relative timestamp
    -- (nil, misaligned, or otherwise garbage) - trusting it blindly is what
    -- caused the footer to read "In queue 0s" forever, which in turn silently
    -- disabled the auto-requeue timer (it never sees elapsed cross the 120s
    -- threshold). So: track our own start time the moment we first observe
    -- the queued state (cheap, always-available via GetLFGMode()), and only
    -- prefer the server's queuedTime when it produces a sane (0-6h) result -
    -- that path also keeps the timer correct across a /reload while queued,
    -- which our own tracking alone can't (it would restart at 0).
    local inQueue = (LW.State.mode == "queued" or LW.State.mode == "suspended")
    local wasInQueue = (prevMode == "queued" or prevMode == "suspended")
    if inQueue and not wasInQueue then
        LW.State.queueStartTime = GetTime and GetTime() or nil
    elseif not inQueue then
        LW.State.queueStartTime = nil
    end

    if inQueue and GetTime then
        local now = GetTime()
        local st = LW.State.stats
        local viaServer = st and st.queuedTime and (now - st.queuedTime)
        if viaServer and viaServer >= 0 and viaServer < 21600 then
            LW.State.elapsed = viaServer
            -- back-date our own start so the 1s tick stays consistent with it
            LW.State.queueStartTime = now - viaServer
        elseif LW.State.queueStartTime then
            LW.State.elapsed = math.max(0, now - LW.State.queueStartTime)
        end
    end

    if LW.UpdateWidget then LW.UpdateWidget() end
    if LW.BroadcastMine then LW.BroadcastMine() end
end

-- Human-readable multi-line summary of the current queue state.
function LW.Summary()
    local s = LW.State
    local mode = s.mode
    if not mode then return "Not in the Dungeon Finder queue." end
    local lines = {}
    if mode == "queued" or mode == "suspended" then
        local st = s.stats
        local names = {}
        for _, d in ipairs(s.dungeons) do names[#names + 1] = d.name end
        local what = (#names > 0 and table.concat(names, ", ")) or (st and st.instanceName) or "?"
        lines[#lines + 1] = "Queued" .. (mode == "suspended" and " (paused - you hold a group invite)" or "") .. ": " .. what
        if s.submode == "empowered" then lines[#lines + 1] = "You're NEXT UP (a random slot opened)!" end
        local line = "In queue " .. fmtTime(s.elapsed)
        if st and st.wait and st.wait.mine and st.wait.mine > 0 then line = line .. "   |   est. wait ~" .. fmtTime(st.wait.mine) end
        lines[#lines + 1] = line
        if st then
            local need = {}
            if st.needs.tank then need[#need + 1] = "tank" end
            if st.needs.healer then need[#need + 1] = "healer" end
            if st.needs.dps then need[#need + 1] = "dps" end
            if #need > 0 then lines[#lines + 1] = "Group still needs: " .. table.concat(need, ", ") end
        end
    elseif mode == "rolecheck" then
        lines[#lines + 1] = "Role check in progress - confirm your role."
    elseif mode == "proposal" then
        local p = s.proposal
        if p then
            local acc = 0
            for _, m in ipairs(p.members) do if m.accepted then acc = acc + 1 end end
            lines[#lines + 1] = "READY: " .. (p.name or "?") .. "  (" .. acc .. "/" .. (p.numMembers or 5) .. " accepted)"
            lines[#lines + 1] = "Your role: " .. (p.role or "?") .. (p.hasResponded and "  (responded)" or "  - WAITING FOR YOU")
        else
            lines[#lines + 1] = "Dungeon proposal pending."
        end
    elseif mode == "lfgparty" then
        lines[#lines + 1] = "In an LFG group" .. ((s.proposal and s.proposal.name) and (": " .. s.proposal.name) or "") .. "."
    elseif mode == "abandonedInDungeon" then
        lines[#lines + 1] = "You left an LFG dungeon (can requeue)."
    else
        lines[#lines + 1] = "LFG state: " .. tostring(mode)
    end
    return table.concat(lines, "\n")
end

function LW.Print()
    LW.Refresh()
    for line in (LW.Summary() .. "\n"):gmatch("(.-)\n") do
        if line ~= "" and AIP.Print then AIP.Print("|cff33ccff[LFG]|r " .. line) end
    end
    local peers = LW.PeerSummary and LW.PeerSummary()
    if peers and #peers > 0 and AIP.Print then
        AIP.Print("|cff33ccff[LFG]|r |cffffd100Peers in queue:|r")
        for _, p in ipairs(peers) do AIP.Print("|cff33ccff[LFG]|r   " .. p) end
    end
end

-- ============================================================================
-- Phase 2 widget: a compact movable status box, auto-shown while in the queue.
-- ============================================================================
-- Dungeon Finder "Assembling Group..." look: five round role portraits (greyed
-- until that slot is found), gold/white wait + queue time lines, and the roles
-- you queued as.
local ROLE_TEX = "Interface\\LFGFrame\\UI-LFG-ICON-ROLES"
local ROLE_COORDS = {
    TANK    = { 0,          0.26171875, 0.26171875, 0.5234375 },
    HEALER  = { 0.26171875, 0.5234375,  0,          0.26171875 },
    DAMAGER = { 0.26171875, 0.5234375,  0.26171875, 0.5234375 },
}
local SLOT_ROLES = { "TANK", "HEALER", "DAMAGER", "DAMAGER", "DAMAGER" }
local SLOT_SIZE, SLOT_GAP = 34, 6

local function setRole(tex, role)
    local c = ROLE_COORDS[role]
    tex:SetTexture(ROLE_TEX); tex:SetTexCoord(c[1], c[2], c[3], c[4])
end

local function fmtLong(s)
    s = math.floor(tonumber(s) or 0)
    if s < 60 then return s .. " Sec" end
    return math.floor(s / 60) .. " Min " .. (s % 60) .. " Sec"
end

local function fillSlot(tex, on)
    if tex.SetDesaturated then tex:SetDesaturated(not on) end
    local v = on and 1 or 0.55
    tex:SetVertexColor(v, v, v)
    tex:SetAlpha(on and 1 or 0.7)
end

local function placeLine(fs, y)
    fs:ClearAllPoints()
    fs:SetPoint("TOP", 0, y); fs:SetPoint("LEFT", 8, 0); fs:SetPoint("RIGHT", -8, 0)
end

function LW.CreateWidget()
    if LW.widget then return LW.widget end
    local f = CreateFrame("Frame", "AIPLFGWatch", UIParent)
    f:SetSize(250, 152)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        if AIP.db then AIP.db.lfgWatchPos = { point = p, relPoint = rp, x = x, y = y } end
    end)
    local pos = AIP.db and AIP.db.lfgWatchPos
    f:ClearAllPoints()
    if pos then f:SetPoint(pos.point or "TOP", UIParent, pos.relPoint or "TOP", pos.x or 0, pos.y or -180)
    else f:SetPoint("TOP", UIParent, "TOP", 0, -180) end
    f:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.03, 0.03, 0.06, 0.9); f:SetBackdropBorderColor(0.6, 0.55, 0.35, 0.95)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", 0, -10); f.title:SetTextColor(1, 1, 1)
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.sub:SetPoint("TOP", f.title, "BOTTOM", 0, -2); f.sub:SetPoint("LEFT", 10, 0); f.sub:SetPoint("RIGHT", -10, 0)
    f.sub:SetTextColor(0.6, 0.6, 0.65)

    f.slots = {}
    local total = #SLOT_ROLES * SLOT_SIZE + (#SLOT_ROLES - 1) * SLOT_GAP
    for i, role in ipairs(SLOT_ROLES) do
        local t = f:CreateTexture(nil, "ARTWORK")
        t:SetSize(SLOT_SIZE, SLOT_SIZE)
        t:SetPoint("TOPLEFT", f, "TOP", -total / 2 + (i - 1) * (SLOT_SIZE + SLOT_GAP), -40)
        setRole(t, role); fillSlot(t, false)
        f.slots[i] = t
    end

    f.line1 = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")   -- Average Wait Time
    f.line2 = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")   -- Time In Queue
    f.line3 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- auto re-queue note
    f.line3:SetTextColor(0.85, 0.85, 0.9)

    f.queuedAs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.queuedAs:SetPoint("TOPLEFT", 12, -134); f.queuedAs:SetText("You are queued as:")
    f.myRoles = {}
    for i = 1, 3 do
        local t = f:CreateTexture(nil, "ARTWORK")
        t:SetSize(16, 16)
        t:SetPoint("LEFT", f.queuedAs, "RIGHT", 6 + (i - 1) * 18, 0)
        t:Hide()
        f.myRoles[i] = t
    end
    -- Leave + rejoin (bottom right), queue state only.
    local rq = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    rq:SetSize(58, 18); rq:SetPoint("BOTTOMRIGHT", -8, 8)
    rq:SetText("Requeue")
    rq:SetScript("OnClick", function()
        if LW.State.mode ~= "queued" then return end
        local now = GetTime and GetTime() or 0
        if (now - (LW.lastManualRequeue or 0)) < 5 then return end
        LW.lastManualRequeue = now
        LW.Requeue()
        if AIP.Print then AIP.Print("|cff33ccff[LFG]|r Left the queue and re-queuing...") end
    end)
    rq:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Leave and rejoin the queue", 1, 1, 1)
        GameTooltip:AddLine("Resets your time in queue.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    rq:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.requeueBtn = rq
    f:Hide()
    LW.widget = f
    return f
end

-- Queue layout (slots + wait/queue lines + roles) vs the compact text-only layout.
local function layoutWidget(f, queued)
    for _, t in ipairs(f.slots) do if queued then t:Show() else t:Hide() end end
    if queued then
        f:SetHeight(154)
        f.queuedAs:Show()
        f.requeueBtn:Show()
        placeLine(f.line1, -82); placeLine(f.line2, -97); placeLine(f.line3, -112)
    else
        f:SetHeight(86)
        f.queuedAs:Hide()
        f.requeueBtn:Hide()
        for _, t in ipairs(f.myRoles) do t:Hide() end
        placeLine(f.line1, -36); placeLine(f.line2, -53)
        f.line3:SetText("")
    end
end

function LW.UpdateWidget()
    if not (AIP.db and AIP.db.lfgWatch) then if LW.widget then LW.widget:Hide() end return end
    local s = LW.State
    local f = LW.CreateWidget()
    -- When enabled the window stays visible (idle state when not queued), so the
    -- toggle / button / settings checkbox have immediate visible feedback.
    if not s.mode or s.mode == "abandonedInDungeon" then
        layoutWidget(f, false)
        f.title:SetText("Dungeon Finder"); f.sub:SetText("")
        f.line1:SetText("|cff888888Not in a queue|r")
        f.line2:SetText("|cff666666queue a dungeon to see live status|r")
        f:Show(); return
    end

    if s.mode == "proposal" and s.proposal then
        local p = s.proposal
        local acc = 0
        for _, m in ipairs(p.members) do if m.accepted then acc = acc + 1 end end
        layoutWidget(f, false)
        f.title:SetText("|cff55ff55Group Found!|r"); f.sub:SetText(p.name or "?")
        f.line1:SetText(string.format("|cffffd100Accepted:|r %d / %d", acc, p.numMembers or 5))
        f.line2:SetText(p.hasResponded and ("|cffffd100Your role:|r " .. (p.role or "?") .. " (responded)")
            or "|cffff5555ACCEPT the queue pop!|r")
    elseif s.mode == "queued" or s.mode == "suspended" then
        local st = s.stats
        local names = {}
        for _, d in ipairs(s.dungeons) do names[#names + 1] = d.name end
        layoutWidget(f, true)
        f.title:SetText(s.submode == "empowered" and "|cff55ff55Next up!|r Assembling Group..." or "Assembling Group...")
        local what = (#names > 0 and (names[1] .. (#names > 1 and (" +" .. (#names - 1)) or ""))) or (st and st.instanceName) or ""
        f.sub:SetText(s.mode == "suspended" and "(paused - you hold a group invite)" or what)

        -- Slots: found = full colour, still needed = greyed.
        local dpsOpen = 3
        if st then
            if st.dpsNeedCount then dpsOpen = math.max(0, math.min(3, st.dpsNeedCount))
            else dpsOpen = st.needs.dps and 3 or 0 end
        end
        fillSlot(f.slots[1], st ~= nil and not st.needs.tank)
        fillSlot(f.slots[2], st ~= nil and not st.needs.healer)
        for i = 1, 3 do fillSlot(f.slots[2 + i], st ~= nil and i <= (3 - dpsOpen)) end

        local avg = st and st.wait and st.wait.average or 0
        f.line1:SetText("|cffffd100Average Wait Time:|r |cffffffff" .. (avg > 0 and fmtLong(avg) or "Unknown") .. "|r")
        f.line2:SetText("|cffffd100Time In Queue:|r |cffffffff" .. fmtLong(s.elapsed) .. "|r")
        local l3 = ""
        if AIP.db and AIP.db.lfgAutoRequeue then
            local left = math.max(0, (LW.REQUEUE_AFTER or 120) - (s.elapsed or 0))
            l3 = string.format("|cff888888(auto re-queue in %s)|r", fmtTime(left))
        end
        f.line3:SetText(l3)
        -- Only a plain wait can be left safely; paused (holding a group invite) can't.
        if s.mode == "queued" then f.requeueBtn:Enable() else f.requeueBtn:Disable() end

        local r, mine = s.roles, {}
        if r then
            if r.tank then mine[#mine + 1] = "TANK" end
            if r.healer then mine[#mine + 1] = "HEALER" end
            if r.dps then mine[#mine + 1] = "DAMAGER" end
        end
        for i, t in ipairs(f.myRoles) do
            if mine[i] then setRole(t, mine[i]); t:Show() else t:Hide() end
        end
    elseif s.mode == "rolecheck" then
        layoutWidget(f, false)
        f.title:SetText("|cffffcc55Role check|r"); f.sub:SetText("")
        f.line1:SetText("Confirm your role."); f.line2:SetText("")
    elseif s.mode == "lfgparty" then
        layoutWidget(f, false)
        f.title:SetText("LFG group"); f.sub:SetText("")
        f.line1:SetText((s.proposal and s.proposal.name) or "In dungeon group."); f.line2:SetText("")
    else
        f:Hide(); return
    end
    f:Show()
end

-- Enable/disable the floating window (shared by the settings toggle, the title-bar
-- button, and /aip rdf). Pass a boolean to set explicitly, or nil to flip.
function LW.Toggle(on)
    if on == nil then on = not (AIP.db and AIP.db.lfgWatch) end
    if AIP.db then AIP.db.lfgWatch = on and true or false end
    LW.Refresh()   -- re-poll state + show/hide the widget immediately
    -- Keep an already-built Settings checkbox in sync (title-bar button and
    -- /aip rdf flip the flag without going through the checkbox's OnClick).
    local SPn = AIP.Panels and AIP.Panels.Settings
    local chk = SPn and SPn.Frame and SPn.Frame.checks and SPn.Frame.checks.lfgWatch
    if chk and chk.SetChecked then chk:SetChecked(AIP.db and AIP.db.lfgWatch and true or false) end
    return AIP.db and AIP.db.lfgWatch
end

-- Auto leave + re-queue if no group is found within the threshold. Opt-in
-- (lfgAutoRequeue), and ONLY while purely waiting (mode == "queued") - never while
-- a group is forming (rolecheck/proposal) or the queue is paused (suspended).
-- Verified 3.3.5a: LeaveLFG() then LFDQueueFrame_Join() re-queues the same
-- selection; leaving the QUEUE gives no Deserter (that's only for formed groups).
-- Leave the queue and re-submit the dungeon(s) selected in the LFD UI. Shared by
-- the auto re-queue timer and the window's Requeue button.
function LW.Requeue()
    if LeaveLFG then
        local ok = pcall(LeaveLFG)
        if not ok and AIP.Debug then AIP.Debug("[LFGWatch] LeaveLFG() errored during requeue") end
    end
    -- Re-queue after the leave is confirmed server-side (LeaveLFG is async).
    -- LFDQueueFrame_Join() re-submits whatever dungeon(s) are currently
    -- selected in the LFD UI's own saved state - if that pcall fails (e.g.
    -- nothing was ever selected there this session) it used to fail silently.
    local function rejoin()
        if LFDQueueFrame_Join then
            local ok = pcall(LFDQueueFrame_Join)
            if not ok and AIP.Debug then
                AIP.Debug("[LFGWatch] LFDQueueFrame_Join() errored during requeue - open the Dungeon Finder and select a dungeon at least once this session")
            end
        end
    end
    if AIP.Utils and AIP.Utils.DelayedCall then AIP.Utils.DelayedCall(2, rejoin) else rejoin() end
end

LW.REQUEUE_AFTER = 120   -- seconds
local lastRequeueAt = 0
function LW.CheckAutoRequeue()
    if not (AIP.db and AIP.db.lfgAutoRequeue) then return end
    if LW.State.mode ~= "queued" then return end
    if (LW.State.elapsed or 0) < LW.REQUEUE_AFTER then return end
    local now = (GetTime and GetTime()) or 0
    if (now - lastRequeueAt) < 30 then return end   -- guard the leave/rejoin transition
    lastRequeueAt = now
    LW.Requeue()
    if AIP.Print then AIP.Print("|cff33ccff[LFG]|r No group after " ..
        math.floor(LW.REQUEUE_AFTER / 60) .. " min - left and re-queued.") end
end

-- ============================================================================
-- Peer sharing over the DataBus (opt-in via AIP.db.lfgShare) - so an addon-using
-- premade can see each other's Dungeon Finder queue at a glance.
-- ============================================================================
LW.peers = {}   -- sender -> { mode, instance, needTank, needHealer, needDPS, wait, ts }

local lastShareKey, lastShareAt = nil, 0
function LW.BroadcastMine()
    if not (AIP.db and AIP.db.lfgShare) then return end
    if not (AIP.DataBus and AIP.DataBus.Broadcast and AIP.DataBus.CreateEvent) then return end
    local s = LW.State
    -- Only share an active, meaningful queue state.
    if not (s.mode == "queued" or s.mode == "suspended" or s.mode == "rolecheck" or s.mode == "proposal") then return end
    local st = s.stats
    local instance = (s.proposal and s.proposal.name) or (s.dungeons[1] and s.dungeons[1].name)
        or (st and st.instanceName) or "Dungeon"
    local nt = (st and st.needs.tank) or false
    local nh = (st and st.needs.healer) or false
    local nd = (st and st.needs.dps) or false
    -- Throttle: don't re-broadcast an unchanged state more than every 20s.
    local key = table.concat({ s.mode, instance, tostring(nt), tostring(nh), tostring(nd) }, "|")
    local now = (GetTime and GetTime()) or 0
    if key == lastShareKey and (now - lastShareAt) < 20 then return end
    lastShareKey, lastShareAt = key, now
    local ev = AIP.DataBus.CreateEvent("LFGQUEUE", {
        mode = s.mode, instance = instance,
        needTank = nt, needHealer = nh, needDPS = nd,
        wait = (st and st.wait and st.wait.mine) or 0,
    })
    if ev then AIP.DataBus.Broadcast(ev) end
end

local function onPeerQueue(event)
    if not (event and event.sender and event.data) then return end
    LW.peers[event.sender] = {
        mode = event.data.mode, instance = event.data.instance,
        needTank = event.data.needTank, needHealer = event.data.needHealer, needDPS = event.data.needDPS,
        wait = event.data.wait or 0, ts = time(),
    }
end

-- Fresh (<5 min) peers, as display strings.
function LW.PeerSummary()
    local now = time()
    local rows = {}
    for name, p in pairs(LW.peers) do
        if (now - (p.ts or 0)) < 300 and p.mode then
            local needs = {}
            if p.needTank then needs[#needs + 1] = "T" end
            if p.needHealer then needs[#needs + 1] = "H" end
            if p.needDPS then needs[#needs + 1] = "D" end
            rows[#rows + 1] = string.format("%s: %s%s%s", name, p.mode,
                p.instance and (" - " .. p.instance) or "",
                #needs > 0 and ("  (needs " .. table.concat(needs, "/") .. ")") or "")
        end
    end
    return rows
end

-- ============================================================================
-- Events (all confirmed to exist in 3.3.5a; guarded registration)
-- ============================================================================
local ev = CreateFrame("Frame")
local EVENTS = {
    "LFG_UPDATE", "LFG_QUEUE_STATUS_UPDATE", "LFG_UPDATE_RANDOM_INFO",
    "LFG_ROLE_CHECK_SHOW", "LFG_ROLE_CHECK_HIDE", "LFG_ROLE_CHECK_ROLE_CHOSEN",
    "LFG_PROPOSAL_SHOW", "LFG_PROPOSAL_UPDATE", "LFG_PROPOSAL_SUCCEEDED", "LFG_PROPOSAL_FAILED",
    "LFG_ROLE_UPDATE", "LFG_LOCK_INFO_RECEIVED", "PLAYER_ENTERING_WORLD",
}
for _, e in ipairs(EVENTS) do pcall(function() ev:RegisterEvent(e) end) end
ev:SetScript("OnEvent", function() LW.Refresh() end)

-- Tick: 1s updates the elapsed counter smoothly; every 3s a full re-poll keeps
-- role-needs / wait times / proposal-accept states current in real time without
-- waiting for a server event. Also drives the auto-requeue check (below).
ev.acc, ev.slow = 0, 0
ev:SetScript("OnUpdate", function(self, e)
    self.acc = self.acc + e
    if self.acc < 1 then return end
    self.acc = 0
    local m = LW.State.mode
    if not (m == "queued" or m == "suspended" or m == "rolecheck" or m == "proposal") then return end
    -- Cheap per-second nudge from our own tracked start (see LW.Refresh) rather
    -- than re-deriving from the server's queuedTime every tick - the slower
    -- full Refresh below already does the sanity-checked server/local pick.
    if (m == "queued" or m == "suspended") and LW.State.queueStartTime and GetTime then
        LW.State.elapsed = math.max(0, GetTime() - LW.State.queueStartTime)
    end
    self.slow = self.slow + 1
    if self.slow >= 3 then
        self.slow = 0
        if LW.Refresh then LW.Refresh() end        -- full re-poll (needs/wait/accepts)
    elseif LW.UpdateWidget then
        LW.UpdateWidget()                            -- cheap: just repaint elapsed
    end
    if LW.CheckAutoRequeue then LW.CheckAutoRequeue() end
end)

-- Subscribe to peers' queue-status broadcasts once the DataBus is up. PLAYER_LOGIN
-- fires once per session/reload and Lua state resets each reload, so no duplicate
-- subscription accumulates.
local dbf = CreateFrame("Frame")
dbf:RegisterEvent("PLAYER_LOGIN")
dbf:SetScript("OnEvent", function()
    if AIP.DataBus and AIP.DataBus.Subscribe then
        AIP.DataBus.Subscribe("LFGQUEUE", onPeerQueue, "LFGWatch")
    end
end)
