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
    dungeons = {}, proposal = nil, roles = nil }

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
    return {
        instanceName = asStr(instanceName), instanceType = instanceType,
        needs  = { leader = leaderNeeds, tank = tankNeeds, healer = healerNeeds, dps = dpsNeeds },
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
    pcall(GetLFGQueuedList, queuedScratch)
    for id, state in pairs(queuedScratch) do
        if state then
            local name = asStr(GetLFGDungeonInfo(id))
            out[#out + 1] = { id = id, name = name or ("Dungeon " .. tostring(id)) }
        end
    end
    return out
end

local function readProposal()
    if not GetLFGProposal then return nil end
    local exists, id, _typeID, _subtypeID, name, _texture, role, hasResponded,
        totalEncounters, completedEncounters, numMembers, isLeader = GetLFGProposal()
    if not exists then return nil end
    local members = {}
    -- Some 3.3.5a cores return numMembers as a non-number; tonumber-guard so it
    -- can never be used as a raw 'for' limit (which errors). Dungeon proposals are
    -- always 5, so fall back to 5 (members past the real count just read as nil).
    local n = tonumber(numMembers) or 5
    if GetLFGProposalMember then
        for i = 1, n do
            local _mLeader, mRole, _mLevel, mResponded, mAccepted = GetLFGProposalMember(i)
            members[i] = { role = asStr(mRole), responded = mResponded, accepted = mAccepted }
        end
    end
    return { id = id, name = asStr(name), role = asStr(role), hasResponded = hasResponded,
        bosses = { done = tonumber(completedEncounters) or 0, total = tonumber(totalEncounters) or 0 },
        numMembers = n, isLeader = isLeader, members = members }
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
    if GetLFGMode then LW.State.mode, LW.State.submode = GetLFGMode() else LW.State.mode = nil end
    LW.State.stats = readStats()
    LW.State.dungeons = readDungeons()
    LW.State.proposal = readProposal()
    LW.State.roles = readRoles()
    if LW.State.stats and LW.State.stats.queuedTime and GetTime then
        LW.State.elapsed = math.max(0, GetTime() - LW.State.stats.queuedTime)
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
        if line ~= "" and AIP.Print then AIP.Print("|cff66bbff[LFG]|r " .. line) end
    end
    local peers = LW.PeerSummary and LW.PeerSummary()
    if peers and #peers > 0 and AIP.Print then
        AIP.Print("|cff66bbff[LFG]|r |cffffd100Peers in queue:|r")
        for _, p in ipairs(peers) do AIP.Print("|cff66bbff[LFG]|r   " .. p) end
    end
end

-- ============================================================================
-- Phase 2 widget: a compact movable status box, auto-shown while in the queue.
-- ============================================================================
function LW.CreateWidget()
    if LW.widget then return LW.widget end
    local f = CreateFrame("Frame", "AIPLFGWatch", UIParent)
    f:SetSize(230, 66)
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
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.02, 0.02, 0.05, 0.86); f:SetBackdropBorderColor(0.35, 0.35, 0.42, 0.95)
    local strip = f:CreateTexture(nil, "ARTWORK")
    strip:SetPoint("TOPLEFT", 5, -5); strip:SetPoint("TOPRIGHT", -5, -5); strip:SetHeight(16)
    strip:SetTexture(0.16, 0.16, 0.24, 0.95)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.title:SetPoint("LEFT", strip, "LEFT", 6, 0); f.title:SetText("|cff66bbffDungeon Finder|r")
    f.line1 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.line1:SetPoint("TOPLEFT", 8, -24); f.line1:SetPoint("RIGHT", -8, 0); f.line1:SetJustifyH("LEFT")
    f.line2 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.line2:SetPoint("TOPLEFT", 8, -44); f.line2:SetPoint("RIGHT", -8, 0); f.line2:SetJustifyH("LEFT")
    f:Hide()
    LW.widget = f
    return f
end

function LW.UpdateWidget()
    if not (AIP.db and AIP.db.lfgWatch) then if LW.widget then LW.widget:Hide() end return end
    local s = LW.State
    local f = LW.CreateWidget()
    -- When enabled the window stays visible (idle state when not queued), so the
    -- toggle / button / settings checkbox have immediate visible feedback.
    if not s.mode or s.mode == "abandonedInDungeon" then
        f.title:SetText("|cff66bbffDungeon Finder|r")
        f.line1:SetText("|cff888888Not in a queue|r")
        f.line2:SetText("|cff666666queue a dungeon to see live status|r")
        f:Show(); return
    end

    if s.mode == "proposal" and s.proposal then
        local p = s.proposal
        local acc = 0
        for _, m in ipairs(p.members) do if m.accepted then acc = acc + 1 end end
        f.title:SetText("|cff55ff55READY:|r " .. (p.name or "?"))
        f.line1:SetText(string.format("Accepted %d / %d", acc, p.numMembers or 5))
        f.line2:SetText(p.hasResponded and ("Role: " .. (p.role or "?") .. " (responded)")
            or "|cffff5555ACCEPT the queue pop!|r")
    elseif s.mode == "queued" or s.mode == "suspended" then
        local st = s.stats
        local names = {}
        for _, d in ipairs(s.dungeons) do names[#names + 1] = d.name end
        f.title:SetText("|cff66bbffQueued:|r " .. ((#names > 0 and names[1]) or (st and st.instanceName) or "Dungeon"))
        local l1 = "In queue " .. fmtTime(s.elapsed)
        if st and st.wait and st.wait.mine and st.wait.mine > 0 then l1 = l1 .. "  ~" .. fmtTime(st.wait.mine) .. " wait" end
        if s.submode == "empowered" then l1 = "|cff55ff55Next up!|r  " .. l1 end
        f.line1:SetText(l1)
        local need = {}
        if st and st.needs.tank then need[#need + 1] = "Tank" end
        if st and st.needs.healer then need[#need + 1] = "Healer" end
        if st and st.needs.dps then need[#need + 1] = "DPS" end
        local l2 = #need > 0 and ("Needs: " .. table.concat(need, ", ")) or "Group filling..."
        if AIP.db and AIP.db.lfgAutoRequeue then
            local left = math.max(0, (LW.REQUEUE_AFTER or 120) - (s.elapsed or 0))
            l2 = l2 .. string.format("  |cff888888(re-queue %s)|r", fmtTime(left))
        end
        f.line2:SetText(l2)
    elseif s.mode == "rolecheck" then
        f.title:SetText("|cffffcc55Role check|r")
        f.line1:SetText("Confirm your role."); f.line2:SetText("")
    elseif s.mode == "lfgparty" then
        f.title:SetText("|cff66bbffLFG group|r")
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
    return AIP.db and AIP.db.lfgWatch
end

-- Auto leave + re-queue if no group is found within the threshold. Opt-in
-- (lfgAutoRequeue), and ONLY while purely waiting (mode == "queued") - never while
-- a group is forming (rolecheck/proposal) or the queue is paused (suspended).
-- Verified 3.3.5a: LeaveLFG() then LFDQueueFrame_Join() re-queues the same
-- selection; leaving the QUEUE gives no Deserter (that's only for formed groups).
LW.REQUEUE_AFTER = 120   -- seconds
local lastRequeueAt = 0
function LW.CheckAutoRequeue()
    if not (AIP.db and AIP.db.lfgAutoRequeue) then return end
    if LW.State.mode ~= "queued" then return end
    if (LW.State.elapsed or 0) < LW.REQUEUE_AFTER then return end
    local now = (GetTime and GetTime()) or 0
    if (now - lastRequeueAt) < 30 then return end   -- guard the leave/rejoin transition
    lastRequeueAt = now
    if LeaveLFG then pcall(LeaveLFG) end
    -- Re-queue after the leave is confirmed server-side (LeaveLFG is async).
    local function rejoin() if LFDQueueFrame_Join then pcall(LFDQueueFrame_Join) end end
    if AIP.Utils and AIP.Utils.DelayedCall then AIP.Utils.DelayedCall(2, rejoin) else rejoin() end
    if AIP.Print then AIP.Print("|cff66bbff[LFG]|r No group after " ..
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
    if LW.State.stats and LW.State.stats.queuedTime and GetTime then
        LW.State.elapsed = math.max(0, GetTime() - LW.State.stats.queuedTime)
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
