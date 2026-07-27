-- AutoInvite Plus - Applications (the matchmaking loop's transport + state)
-- Structured seeker->leader applications over the DataBus, with truthful
-- status ACKs back (seen -> queued #N -> invited/declined), plus the
-- seeker-side match alerts and the opt-in green auto-actions.
--
-- Everything here rides DIRECTED addon messages (DataBus whisper path) or
-- normal whispers - never the ChatGate public budget, so the anti-mute
-- guarantee is untouched.

local AIP = AutoInvitePlus
AIP.Apply = AIP.Apply or {}
local Apply = AIP.Apply

-- Seeker side: my applications, keyed by leader name.
-- {raid, status = "sent"|"whispered"|"seen"|"queued"|"invited"|"declined",
--  position, time}
Apply.mine = {}

-- Leader side: applicants we received an APPLY from (so ACKs only go to
-- players who actually applied through the protocol), keyed by name.
Apply.incoming = {}

-- Seeker side: leaders we already alerted about, to throttle match alerts.
Apply.alerted = {}

local ALERT_THROTTLE = 600   -- seconds between alerts for the same leader
local APP_TTL = 3600         -- forget applications/state after an hour

local function prune(store, ttl)
    local now = time()
    for k, v in pairs(store) do
        if (now - (v.time or 0)) > ttl then store[k] = nil end
    end
end

local function pruneAll()
    prune(Apply.mine, APP_TTL)
    prune(Apply.incoming, APP_TTL)
    local now = time()
    for k, t in pairs(Apply.alerted) do
        if (now - t) > ALERT_THROTTLE then Apply.alerted[k] = nil end
    end
end

-- ============================================================================
-- SEEKER SIDE
-- ============================================================================

-- Apply to an AIP-peer listing over the DataBus. Returns true if sent.
-- Non-peer listings return false - the caller falls back to the Quick-Req
-- whisper and then calls Apply.MarkWhispered.
function Apply.SendApply(listing, note)
    if not listing or not listing.leader then return false end
    if not listing.isDataBus then return false end
    if not (AIP.DataBus and AIP.DataBus.CreateEvent and AIP.DataBus.Broadcast) then return false end

    local GUI = AIP.CentralGUI or {}
    local me = AIP.FitEngine and AIP.FitEngine.Me() or {}

    -- Only advertise a weekly need when this listing actually runs it
    local weekly = nil
    if listing.weekly and AIP.Weekly and AIP.Weekly.IsWanted and AIP.Weekly.IsWanted(listing.weekly) then
        weekly = listing.weekly
    end

    local ev = AIP.DataBus.CreateEvent("APPLY", {
        raid = listing.raid,
        role = me.role or "DPS",
        class = me.class,
        spec = me.spec,
        gs = me.gs or 0,
        ilvl = me.ilvl or 0,
        weekly = weekly,
        note = note,
    })
    if not ev then return false end
    AIP.DataBus.Broadcast(ev, listing.leader)

    Apply.mine[listing.leader] = { raid = listing.raid, status = "sent", time = time() }
    AIP.Print("Applied to |cFFFFD100" .. listing.leader .. "|r (" .. (listing.raid or "?") .. ") - status updates will appear here.")
    pruneAll()
    if AIP.UpdateCentralGUI then AIP.UpdateCentralGUI() end
    return true
end

-- Record a whisper-based application to a non-AIP leader (no ACKs possible)
function Apply.MarkWhispered(leader, raid)
    if not leader then return end
    Apply.mine[leader] = { raid = raid, status = "whispered", time = time() }
    if AIP.UpdateCentralGUI then AIP.UpdateCentralGUI() end
end

-- Status text for the details panel ("Applied - queued #4")
function Apply.StatusFor(leader)
    local app = leader and Apply.mine[leader]
    if not app then return nil end
    if app.status == "sent" then return "|cFFFFD100Applied - waiting for response|r" end
    if app.status == "whispered" then return "|cFFAAAAAAWhispered (leader has no AIP)|r" end
    if app.status == "seen" then return "|cFFFFD100Application seen|r" end
    if app.status == "queued" then
        return "|cFF00FF00Queued" .. (app.position and (" #" .. app.position) or "") .. "|r"
    end
    if app.status == "invited" then return "|cFF00FF00Invited!|r" end
    if app.status == "declined" then return "|cFFFF6666Declined|r" end
    return nil
end

-- Called by ChatScanner when a NEW listing appears: match alert + auto-apply.
function Apply.OnNewListing(group)
    if not group or not group.leader or group.isOwn then return end
    if not (AIP.db and AIP.db.matchAlerts) then return end
    local GUI = AIP.CentralGUI
    if not (GUI and GUI.MyEnrollment) then return end          -- only while enrolled
    if not (AIP.FitEngine and AIP.FitEngine.ScoreListing) then return end

    local fit = AIP.FitEngine.ScoreListing(group, AIP.FitEngine.Me())
    if fit.verdict ~= "GREEN" then return end

    -- Throttle per leader
    local now = time()
    if Apply.alerted[group.leader] and (now - Apply.alerted[group.leader]) < ALERT_THROTTLE then
        return
    end
    Apply.alerted[group.leader] = now

    local weeklyNote = ""
    if group.weekly and AIP.Weekly and AIP.Weekly.IsWanted and AIP.Weekly.IsWanted(group.weekly) then
        local q = AIP.Weekly.ForToken(group.weekly)
        weeklyNote = " - |cFF33CCFFruns YOUR weekly (" .. (q and q.boss or group.weekly) .. ")|r"
    end
    AIP.Print(string.format("%s |cFF00FF00Match:|r %s is forming %s%s - open the browser to apply.",
        AIP.FitEngine.Chip(fit), group.leader, group.raid or "?", weeklyNote))
    if GUI.ShowMinimapBubble then
        GUI.ShowMinimapBubble("Match: " .. (group.raid or "?") .. " by " .. group.leader)
    end

    -- Opt-in auto-apply, AIP peers only (auto-whispering non-addon strangers
    -- reads as botting and was deliberately rejected)
    if AIP.db.autoApplyGreen and group.isDataBus and not Apply.mine[group.leader] then
        if Apply.SendApply(group) then
            AIP.Print("|cFF00FF00Auto-applied|r (autoApplyGreen is on).")
        end
    end
end

-- ============================================================================
-- LEADER SIDE
-- ============================================================================

local function sendAck(applicant, status, position)
    if not (AIP.DataBus and AIP.DataBus.CreateEvent and AIP.DataBus.Broadcast) then return end
    local ev = AIP.DataBus.CreateEvent("APPLYACK", {
        applicant = applicant,
        status = status,
        position = position,
    })
    if ev then AIP.DataBus.Broadcast(ev, applicant) end
end

-- Personalized applicant feedback: waitlist position + the concrete FitEngine
-- verdict drivers (GS vs minimum, role full / class position covered, ...).
-- FitEngine is the ONLY judge - this just words its reasons; never add checks
-- here. Kept under the 255-byte whisper cap.
local FEEDBACK_MAX_REASONS = 4

function Apply.BuildFeedback(applicant, fit, position, listing)
    -- Wording must match the APPLYACK status the applicant's own client just
    -- printed ("application queued #N", from onApplyAck) - saying "waitlist"
    -- here contradicted that even though it's the same event.
    local head = "[AIP] " .. ((listing and listing.raid) or (applicant and applicant.raid) or "Raid")
        .. ": queued #" .. tostring(position or "?")
    if not (fit and fit.reasons and #fit.reasons > 0) then return head end

    local picked = {}
    for _, reason in ipairs(fit.reasons) do
        if #picked >= FEEDBACK_MAX_REASONS then break end
        table.insert(picked, reason)
    end
    local msg = head .. " (" .. table.concat(picked, "; ") .. ")"
    if #msg > 255 then
        msg = msg:sub(1, 252) .. "...)"
        if #msg > 255 then msg = msg:sub(1, 255) end
    end
    return msg
end

-- Whisper-only (never the ChatGate public budget), same as the waitlist sender.
function Apply.SendFeedbackWhisper(name, applicant, fit, position, listing)
    if not name then return end
    if AIP.db and AIP.db.applyFeedbackWhisper == false then return end
    local msg = Apply.BuildFeedback(applicant, fit, position, listing)
    if msg and msg ~= "" then
        pcall(SendChatMessage, msg, "WHISPER", nil, name)
    end
end

local function onApply(event)
    if not (event and event.sender and event.data) then return end
    if event.sender == UnitName("player") then return end
    local d = event.data
    local GUI = AIP.CentralGUI

    -- No active listing: acknowledge sighting so the seeker isn't left hanging
    if not (GUI and GUI.MyGroup) then
        sendAck(event.sender, "seen")
        return
    end

    Apply.incoming[event.sender] = { time = time() }
    pruneAll()

    -- Blacklist: decline immediately (truthful, no queue noise)
    if AIP.IsBlacklisted and AIP.IsBlacklisted(event.sender) then
        sendAck(event.sender, "declined")
        return
    end

    -- Fit verdict against the live listing
    local applicant = {
        name = event.sender,
        raid = d.raid,
        role = d.role,
        class = d.class,
        spec = d.spec,
        gs = d.gs,
        ilvl = d.ilvl,
        weekly = d.weekly,
    }
    local fit = AIP.FitEngine and AIP.FitEngine.ScoreApplicant(applicant, GUI.MyGroup)

    -- Green fast-lane: favorites always (existing prioritize behavior),
    -- anyone GREEN when the leader opted into autoInviteGreen
    local isFavorite = AIP.IsPlayerFavorite and AIP.IsPlayerFavorite(event.sender)
    local smart = AIP.db and AIP.db.smartInvite
    local favoriteLane = isFavorite and smart and smart.prioritizeFavorites
    local greenLane = AIP.db and AIP.db.autoInviteGreen and fit and fit.verdict == "GREEN"
    if (favoriteLane or greenLane) and AIP.InvitePlayer then
        -- Don't sendAck here: AIP.InvitePlayer, on success, already calls
        -- Apply.NotifyInvited (Apply.incoming[event.sender] was set above),
        -- which sends the "invited" ACK. Sending it again here double-whispers
        -- the applicant with two identical APPLYACKs.
        if AIP.InvitePlayer(event.sender) then
            return
        end
    end

    local applyNote = "[Apply] " .. (d.raid or "?") .. (d.note and (" - " .. d.note) or "")

    -- Waitlist routing (the composition-tandem default): the applicant holds a
    -- waitlist slot and gets a personalized whisper verdict (GS vs minimum,
    -- role full, class position covered). RED applications are held too - the
    -- leader decides; nothing here auto-declines. applyToWaitlist=false keeps
    -- the legacy queue routing below.
    local useWaitlist = not (AIP.db and AIP.db.applyToWaitlist == false)
        and AIP.AddToWaitlist and AIP.IsOnWaitlist
    if useWaitlist then
        -- The waitlist store/UI only understands TANK/HEALER/DPS; peers may
        -- send the four-way MDPS/RDPS split (Fit.Me role detection)
        local wlRole = AIP.Utils.FoldRole(d.role)
        local existed = AIP.IsOnWaitlist(event.sender)
        if not existed then
            -- silent: the richer feedback whisper below replaces the generic one
            AIP.AddToWaitlist(event.sender, wlRole, applyNote, d.class, d.gs, true)
        end
        -- Enrich the waitlist entry with structured fields the manual path lacks
        local onList, entry, position = AIP.IsOnWaitlist(event.sender)
        if onList and entry then
            entry.spec = d.spec or entry.spec
            entry.ilvl = d.ilvl or entry.ilvl
            entry.weekly = d.weekly or entry.weekly
            entry.gs = d.gs or entry.gs
            entry.class = d.class or entry.class
            entry.isApplication = true
            sendAck(event.sender, "queued", position)
            Apply.SendFeedbackWhisper(event.sender, applicant, fit, position, GUI.MyGroup)
            AIP.Print(string.format("%s |cFFFFD100Application:|r %s (%s %s, GS %s) -> waitlist #%d",
                (fit and AIP.FitEngine.Chip(fit)) or "",
                event.sender, d.class or "?", d.role or "?", tostring(d.gs or "?"), position or 0))
            if AIP.UpdateWaitlistUI then AIP.UpdateWaitlistUI() end
            if AIP.UpdateCentralGUI then AIP.UpdateCentralGUI() end
        else
            sendAck(event.sender, "seen")
        end
        return
    end

    -- Legacy queue routing (applyToWaitlist = false)
    if AIP.AddToQueue then
        local existed = AIP.IsInQueue and AIP.IsInQueue(event.sender)
        if not existed then
            AIP.AddToQueue(event.sender, applyNote, d.role, d.gs, d.class)
        end
        -- Enrich the queue entry with structured fields the whisper path lacks
        local inQueue, entry, position = AIP.IsInQueue(event.sender)
        if inQueue and entry then
            entry.spec = d.spec or entry.spec
            entry.ilvl = d.ilvl or entry.ilvl
            entry.weekly = d.weekly or entry.weekly
            entry.isApplication = true
            sendAck(event.sender, "queued", position)
            Apply.SendFeedbackWhisper(event.sender, applicant, fit, position, GUI.MyGroup)
            AIP.Print(string.format("%s |cFFFFD100Application:|r %s (%s %s, GS %s) -> queue #%d",
                (fit and AIP.FitEngine.Chip(fit)) or "",
                event.sender, d.class or "?", d.role or "?", tostring(d.gs or "?"), position or 0))
            if AIP.UpdateQueueUI then AIP.UpdateQueueUI() end
            if AIP.UpdateCentralGUI then AIP.UpdateCentralGUI() end
        else
            sendAck(event.sender, "seen")
        end
    else
        sendAck(event.sender, "seen")
    end
end

local function onApplyAck(event)
    if not (event and event.sender and event.data) then return end
    local d = event.data
    -- The ACK is about ME (directed), from the leader I applied to
    local app = Apply.mine[event.sender]
    if not app then return end
    app.status = d.status or app.status
    app.position = d.position
    app.time = time()

    if d.status == "invited" then
        AIP.Print("|cFF00FF00" .. event.sender .. " invited you!|r Accept the invite window.")
        local GUI = AIP.CentralGUI
        if GUI and GUI.ShowMinimapBubble then GUI.ShowMinimapBubble("Invited by " .. event.sender .. "!") end
    elseif d.status == "queued" then
        AIP.Print(event.sender .. ": application queued" .. (d.position and (" |cFF00FF00#" .. d.position .. "|r") or "") .. ".")
    elseif d.status == "declined" then
        AIP.Print(event.sender .. ": |cFFFF6666application declined|r.")
    elseif d.status == "seen" then
        AIP.Print(event.sender .. ": application seen (no active listing right now).")
    end
    if AIP.UpdateCentralGUI then AIP.UpdateCentralGUI() end
end

-- Truthful ACKs no matter which UI path invited/declined the applicant.
-- Called (guarded) from Core.InvitePlayer and the queue reject paths.
function Apply.NotifyInvited(name)
    if name and Apply.incoming[name] then
        sendAck(name, "invited")
        Apply.incoming[name] = nil
    end
end

function Apply.NotifyDeclined(name)
    if name and Apply.incoming[name] then
        sendAck(name, "declined")
        Apply.incoming[name] = nil
    end
end

-- ============================================================================
-- WIRING
-- ============================================================================

local f = CreateFrame("Frame", "AIPApplicationsFrame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if AIP.DataBus and AIP.DataBus.Subscribe then
        AIP.DataBus.Subscribe("APPLY", onApply, "Applications")
        AIP.DataBus.Subscribe("APPLYACK", onApplyAck, "Applications")
    end
end)
