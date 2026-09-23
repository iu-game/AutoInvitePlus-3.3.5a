-- AutoInvite Plus - ChatGate
-- The single choke point for ALL non-whisper outbound chat.
--
-- Why this exists: servers (Warmane especially) mute accounts that send
-- repeated/bursty channel messages. Every CHANNEL/SAY/YELL/GUILD send in the
-- addon must go through ChatGate.Send so one central budget can guarantee we
-- never exceed a safe rate, no matter how many features want to talk.
--
-- Lanes:
--   group  (RAID/RAID_WARNING/PARTY/BATTLEGROUND) - BYPASS. Mechanic call-outs
--          and loot dumps are time-critical and group chat is not flood-
--          punished for a leader; they send immediately and stay contiguous.
--   guild  (GUILD)                                - queued, light budget.
--   public (CHANNEL/SAY/YELL)                     - queued, strict budget.
--
-- Queue records carry the channel NAME, never the numeric id: channel indices
-- shift when the user joins/leaves channels, so ids are resolved at DRAIN
-- time and unresolvable records are dropped rather than sent to a wrong
-- channel. Records also carry an owner tag (so StopBroadcast can cancel
-- everything it queued), a staleAfter, and an optional validate() closure
-- re-checked at drain time (a queued LFM must never fire after the user
-- already joined a group).
--
-- Whispers are NOT gated (sent via raw SendChatMessage - no pacing layer
-- currently sits in front of them), and the DataBus AIPSync channel is NOT
-- gated (it has its own limiter; a public blackout must not freeze peer
-- discovery).

local AIP = AutoInvitePlus
AIP.ChatGate = AIP.ChatGate or {}
local CG = AIP.ChatGate

-- ============================================================================
-- PROFILES & STATE
-- ============================================================================

-- publicGap:   min seconds between ANY two public sends
-- channelGap:  min seconds between two sends to the SAME channel/chat type
-- perMinute:   max public sends in any rolling 60s window
-- guildGap:    min seconds between guild sends
CG.Profiles = {
    relaxed  = { publicGap = 4,  channelGap = 60,  perMinute = 8, guildGap = 30 },
    safe     = { publicGap = 6,  channelGap = 90,  perMinute = 6, guildGap = 60 },
    paranoid = { publicGap = 10, channelGap = 150, perMinute = 4, guildGap = 90 },
}

CG.State = {
    queue = {},            -- FIFO of pending records
    lastPublic = 0,        -- GetTime() of last public send
    lastGuild = 0,         -- GetTime() of last guild send
    lastAnySend = 0,       -- GetTime() of last gated send (for throttle scoping)
    perChannel = {},       -- [key] = GetTime() of last send to that channel/type
    recent = {},           -- ring of recent public send times (rolling minute)
    backoff = 1,           -- interval multiplier, grows on server throttle
    blackoutUntil = 0,     -- no public sends before this GetTime()
    sent = 0,              -- lifetime counters for /aip gate
    dropped = 0,
}

-- Compatibility surface: older UI code (broadcast status footer) reads these.
-- ChatGate now owns and maintains this table; Core no longer defines it.
AIP.ChatBan = AIP.ChatBan or {
    detected = false,
    lastBanTime = 0,
    banCount = 0,
    channelDelay = 2,
    maxDelay = 5,
}

local function dbg(msg)
    if AIP.Debug then AIP.Debug("[ChatGate] " .. tostring(msg)) end
    if AIP.Log then AIP.Log("[ChatGate] " .. tostring(msg)) end
end

local function say(msg)
    if AIP.Print then
        AIP.Print(msg)
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[AutoInvite+]|r " .. tostring(msg))
    end
end

function CG.GetProfile()
    local key = (AIP.db and AIP.db.chatGateProfile) or "safe"
    return CG.Profiles[key] or CG.Profiles.safe, key
end

-- Effective budget values (profile scaled by throttle backoff). The user's
-- "Cooldown (sec)" setting (db.spamChannelCooldown) acts as a floor on the
-- per-channel gap, so raising it beyond the profile slows same-channel posts.
local function budgets()
    local p = CG.GetProfile()
    local b = CG.State.backoff
    local channelGap = p.channelGap * b
    local userFloor = AIP.db and tonumber(AIP.db.spamChannelCooldown) or 0
    if userFloor > channelGap then channelGap = userFloor end
    return p.publicGap * b, channelGap, p.perMinute, p.guildGap * b
end

-- ============================================================================
-- CHANNEL RESOLUTION (always by name, always at drain time)
-- ============================================================================

-- Resolve a channel name to its CURRENT numeric id. Exact match first, then
-- a fuzzy scan (the same behavior as AIP.FindChannelId, which loads later).
function CG.ResolveChannel(channelName)
    if not channelName or channelName == "" then return nil end
    local id = GetChannelName(channelName)
    if id and id > 0 then return id end
    local search = channelName:lower()
    for i = 1, (MAX_CHANNEL_BUTTONS or 20) do
        local cid, cname = GetChannelName(i)
        if cid and cid > 0 and cname and cname:lower():find(search, 1, true) then
            return cid
        end
    end
    return nil
end

-- Cooldown key: channel name for CHANNEL, chat type otherwise. Takes
-- primitive (chatType, channelName) args rather than a record table so the
-- two call sites that only have those two values loose (IsEligible,
-- NextEligibleIn) can share this instead of re-inlining the same "ch:" ..
-- lower() expression.
local function channelKey(chatType, channelName)
    if chatType == "CHANNEL" then
        return "ch:" .. (channelName or ""):lower()
    end
    return chatType
end

-- ============================================================================
-- ELIGIBILITY
-- ============================================================================

local GROUP_TYPES = { RAID = true, RAID_WARNING = true, PARTY = true, BATTLEGROUND = true }

local function isPublicType(chatType)
    return chatType == "CHANNEL" or chatType == "SAY" or chatType == "YELL"
end

-- Prune the rolling-minute window and return how many public sends remain in it
local function recentPublicCount(now)
    local recent = CG.State.recent
    local kept = {}
    for i = 1, #recent do
        if now - recent[i] < 60 then kept[#kept + 1] = recent[i] end
    end
    CG.State.recent = kept
    return #kept
end

-- Can a send of this shape go out right now?
function CG.IsEligible(chatType, channelName)
    local now = GetTime()
    local publicGap, channelGap, perMinute, guildGap = budgets()

    if chatType == "GUILD" then
        return (now - CG.State.lastGuild) >= guildGap
    end

    if isPublicType(chatType) then
        if now < CG.State.blackoutUntil then return false end
        if (now - CG.State.lastPublic) < publicGap then return false end
        if recentPublicCount(now) >= perMinute then return false end
        local last = CG.State.perChannel[channelKey(chatType, channelName)]
        if last and (now - last) < channelGap then return false end
        if chatType == "CHANNEL" and not CG.ResolveChannel(channelName) then return false end
        return true
    end

    return true  -- group lane is always eligible (it bypasses anyway)
end

-- Seconds until the given shape could send (rough, for status display)
function CG.NextEligibleIn(chatType, channelName)
    local now = GetTime()
    local publicGap, channelGap = budgets()
    local waits = {}
    if isPublicType(chatType) then
        if now < CG.State.blackoutUntil then waits[#waits + 1] = CG.State.blackoutUntil - now end
        waits[#waits + 1] = publicGap - (now - CG.State.lastPublic)
        local last = CG.State.perChannel[channelKey(chatType, channelName)]
        if last then waits[#waits + 1] = channelGap - (now - last) end
    end
    local maxWait = 0
    for _, w in ipairs(waits) do if w > maxWait then maxWait = w end end
    return maxWait
end

-- ============================================================================
-- SEND / QUEUE
-- ============================================================================

local function doSend(record)
    local now = GetTime()
    if record.chatType == "CHANNEL" then
        local id = CG.ResolveChannel(record.channelName)
        if not id then
            CG.State.dropped = CG.State.dropped + 1
            dbg("dropped (channel gone): " .. tostring(record.channelName))
            return false
        end
        SendChatMessage(record.msg, "CHANNEL", nil, id)
    else
        SendChatMessage(record.msg, record.chatType)
    end

    CG.State.lastAnySend = now
    CG.State.sent = CG.State.sent + 1
    CG.State.perChannel[channelKey(record.chatType, record.channelName)] = now
    if isPublicType(record.chatType) then
        CG.State.lastPublic = now
        local recent = CG.State.recent
        recent[#recent + 1] = now
    elseif record.chatType == "GUILD" then
        CG.State.lastGuild = now
    end
    dbg("sent [" .. record.chatType .. (record.channelName and (":" .. record.channelName) or "") .. "] " .. (record.owner or "?"))
    return true
end

-- Public API. opts = {
--   channelName = "Trade"          (required for CHANNEL sends; NEVER pass an id)
--   owner       = "broadcast"      (tag for CancelOwner)
--   staleAfter  = 120              (seconds; queued longer than this -> dropped)
--   validate    = function() end   (re-checked at drain; false -> dropped)
-- }
-- Returns true if sent or queued, false if refused outright.
function CG.Send(msg, chatType, _legacyTarget, opts)
    if not msg or msg == "" or not chatType then return false end
    opts = opts or {}

    if #msg > 255 then
        say("|cFFFF6666Message not sent:|r " .. #msg .. " characters (chat limit is 255). Shorten the note/reserved items.")
        return false
    end

    -- Group lane: send immediately, keep multi-line dumps contiguous.
    if GROUP_TYPES[chatType] then
        SendChatMessage(msg, chatType)
        return true
    end

    -- SAY used as a solo fallback for group announcements (RaidTools.Send when
    -- ungrouped) is time-critical, not promotional - let it through directly.
    if chatType == "SAY" and opts.groupFallback then
        SendChatMessage(msg, "SAY")
        return true
    end

    local record = {
        msg = msg,
        chatType = chatType,
        channelName = opts.channelName,
        owner = opts.owner or "misc",
        validate = opts.validate,
        enqueuedAt = GetTime(),
        staleAfter = opts.staleAfter or 120,
    }

    if chatType == "CHANNEL" and not record.channelName then
        -- Refuse id-based channel sends: ids go stale in the queue.
        dbg("refused CHANNEL send without channelName from " .. record.owner)
        return false
    end

    table.insert(CG.State.queue, record)
    CG.StartPump()
    return true
end

-- Remove every queued record belonging to an owner (StopBroadcast etc.)
function CG.CancelOwner(owner)
    if not owner then return 0 end
    local queue = CG.State.queue
    local removed = 0
    for i = #queue, 1, -1 do
        if queue[i].owner == owner then
            table.remove(queue, i)
            removed = removed + 1
        end
    end
    if removed > 0 then dbg("cancelled " .. removed .. " queued for " .. owner) end
    return removed
end

-- ============================================================================
-- PUMP (single OnUpdate, at most one send per pass)
-- ============================================================================

function CG.StartPump()
    if not CG.frame then
        CG.frame = CreateFrame("Frame", "AIPChatGateFrame", UIParent)
    end
    if CG.pumping then return end
    CG.pumping = true
    CG.frame.elapsed = 0
    CG.frame:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed < 0.5 then return end
        self.elapsed = 0
        CG.Pump()
    end)
end

function CG.StopPump()
    CG.pumping = false
    if CG.frame then CG.frame:SetScript("OnUpdate", nil) end
end

function CG.Pump()
    local queue = CG.State.queue
    if #queue == 0 then
        CG.StopPump()
        return
    end

    local now = GetTime()

    -- Drop stale / invalidated records first (whole queue, cheap)
    for i = #queue, 1, -1 do
        local r = queue[i]
        local stale = (now - r.enqueuedAt) > r.staleAfter
        local invalid = r.validate and not r.validate()
        if stale or invalid then
            table.remove(queue, i)
            CG.State.dropped = CG.State.dropped + 1
            dbg("dropped (" .. (stale and "stale" or "invalidated") .. ") from " .. (r.owner or "?"))
        end
    end

    -- Send the FIRST eligible record (FIFO with skip-over, one per pass)
    for i = 1, #queue do
        local r = queue[i]
        if CG.IsEligible(r.chatType, r.channelName) then
            table.remove(queue, i)
            doSend(r)
            break
        end
    end

    if #CG.State.queue == 0 then CG.StopPump() end
end

-- ============================================================================
-- SERVER THROTTLE DETECTION (scoped to our own sends)
-- ============================================================================

-- Only chat-specific squelch wording. Deliberately NOT matching the old bare
-- "you must wait" / "you are not permitted" - those false-trip on summon,
-- duel and quest system messages and would blackout broadcasting for nothing.
local THROTTLE_PATTERNS = {
    "squelched",
    "silenced",
    "wait before sending",
    "chat has been disabled",
    "too many messages",
    "cannot send more",
    "throttled",
    "sending messages too quickly",
}

function CG.OnThrottleDetected(message, pattern)
    local now = GetTime()
    CG.State.backoff = math.min(4, CG.State.backoff * 1.5)
    CG.State.blackoutUntil = now + 60

    -- Maintain the compat surface the broadcast footer reads
    AIP.ChatBan.detected = true
    AIP.ChatBan.lastBanTime = time()
    AIP.ChatBan.banCount = (AIP.ChatBan.banCount or 0) + 1
    local publicGap = budgets()
    AIP.ChatBan.channelDelay = math.ceil(publicGap)

    say("|cFFFF6666Server chat throttle detected|r (matched: \"" .. pattern .. "\"). Pausing public sends 60s, slowing to " .. string.format("%.1f", CG.State.backoff) .. "x intervals.")
    dbg("throttle msg: " .. tostring(message))
end

-- Decay ticker: every 5 minutes without a new throttle, relax the backoff
local function decayTick()
    if CG.State.backoff > 1 then
        local sinceBan = time() - (AIP.ChatBan.lastBanTime or 0)
        if sinceBan >= 300 then
            CG.State.backoff = math.max(1, CG.State.backoff / 1.5)
            if CG.State.backoff <= 1.01 then
                CG.State.backoff = 1
                AIP.ChatBan.detected = false
                AIP.ChatBan.banCount = 0
                AIP.ChatBan.channelDelay = 2
                say("Chat throttle backoff cleared - normal pacing restored.")
            end
        end
    end
end

do
    local watcher = CreateFrame("Frame", "AIPChatGateWatcher", UIParent)
    watcher:RegisterEvent("CHAT_MSG_SYSTEM")
    watcher:SetScript("OnEvent", function(self, event, message)
        if not message then return end
        -- Only meaningful within 10s of one of OUR gated sends; otherwise it's
        -- someone else's problem (or an unrelated system message).
        if (GetTime() - CG.State.lastAnySend) > 10 then return end
        local lower = message:lower()
        for _, pattern in ipairs(THROTTLE_PATTERNS) do
            if lower:find(pattern, 1, true) then
                CG.OnThrottleDetected(message, pattern)
                break
            end
        end
    end)

    -- 30s decay-check cadence, self-rescheduled via the shared one-shot
    -- helper instead of a permanent per-frame OnUpdate (see CLAUDE.md: use
    -- AIP.Utils.DelayedCall for delayed/periodic work, not raw OnUpdate).
    local function scheduleDecayTick()
        AIP.Utils.DelayedCall(30, function()
            decayTick()
            scheduleDecayTick()
        end)
    end
    scheduleDecayTick()
end

-- ============================================================================
-- STATUS (for /aip gate)
-- ============================================================================

function CG.Status()
    local profile, key = CG.GetProfile()
    local publicGap, channelGap, perMinute, guildGap = budgets()
    local now = GetTime()
    say("|cFFFFD700ChatGate status|r")
    say("  Profile: " .. key .. (CG.State.backoff > 1 and (" |cFFFF6666(backoff " .. string.format("%.1f", CG.State.backoff) .. "x)|r") or ""))
    say(string.format("  Budget: 1 public msg / %.0fs, same channel every %.0fs, max %d/min, guild every %.0fs", publicGap, channelGap, perMinute, guildGap))
    if now < CG.State.blackoutUntil then
        say("  |cFFFF6666BLACKOUT|r: public sends resume in " .. math.ceil(CG.State.blackoutUntil - now) .. "s")
    end
    say("  Queue: " .. #CG.State.queue .. " pending | sent " .. CG.State.sent .. " | dropped " .. CG.State.dropped)
    local rate = 60 / math.max(publicGap, 60 / perMinute)
    say(string.format("  Worst-case rate: ~%.1f public msgs/min - %s", rate, rate <= 6 and "|cFF00FF00SAFE|r" or "|cFFFFFF00aggressive|r"))
    for keyName, t in pairs(CG.State.perChannel) do
        local rem = channelGap - (now - t)
        if rem > 0 then
            say(string.format("    %s: ready in %.0fs", keyName, rem))
        end
    end
end
