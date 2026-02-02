-- AutoInvite Plus - Queue Module (Enhanced v4.1)
-- Manages the player invite queue with blacklist integration and response messages

local AIP = AutoInvitePlus

-- ============================================================================
-- DATA STRUCTURE
-- ============================================================================
-- AIP.db.queue = {
--     {
--         name = "PlayerName",
--         message = "inv pls",
--         time = timestamp,
--         isBlacklisted = false,   -- Auto-checked on add
--         blacklistReason = nil,   -- If blacklisted, shows reason
--         class = "WARRIOR",       -- If detectable
--         gs = 5500,               -- If available
--     }
-- }
-- AIP.db.blacklistMode = "flag" | "reject"  -- Defined in Blacklist.lua
-- AIP.db.responseInvite = "You have been invited!"
-- AIP.db.responseReject = "Sorry, the raid is full."
-- AIP.db.responseWaitlist = "Added to waitlist, position: #%d"
-- ============================================================================

-- Initialize queue defaults
local function EnsureQueueDefaults()
    if not AIP.db then return false end
    if not AIP.db.queue then
        AIP.db.queue = {}
    end
    -- Response messages
    if not AIP.db.responseInvite then
        AIP.db.responseInvite = "[AutoInvite+] You have been invited!"
    end
    if not AIP.db.responseReject then
        AIP.db.responseReject = "[AutoInvite+] Sorry, the raid is full."
    end
    if not AIP.db.responseWaitlist then
        AIP.db.responseWaitlist = "[AutoInvite+] Added to waitlist, position: #%d"
    end
    return true
end

-- ============================================================================
-- CORE FUNCTIONS
-- ============================================================================

-- Check if player is in queue
function AIP.IsInQueue(name)
    if not AIP.db or not AIP.db.queue or not name then return false, nil, nil end

    local lowerName = name:lower()
    for i, entry in ipairs(AIP.db.queue) do
        if entry.name:lower() == lowerName then
            return true, entry, i
        end
    end
    return false, nil, nil
end

-- Add player to queue (with optional role, gs, class info)
function AIP.AddToQueue(name, message, role, gs, class)
    if not EnsureQueueDefaults() then return false end
    if not name or name:trim() == "" then return false end

    name = name:trim()

    -- Check if already in queue
    if AIP.IsInQueue(name) then
        AIP.Debug(name .. " is already in queue")
        return false
    end

    -- Check blacklist
    local isBlacklisted, blacklistEntry = false, nil
    if AIP.IsBlacklisted then
        isBlacklisted, blacklistEntry = AIP.IsBlacklisted(name)
    end

    -- If blacklist mode is "reject", auto-reject blacklisted players
    if isBlacklisted and AIP.db.blacklistMode == "reject" then
        AIP.Debug(name .. " is blacklisted and mode is reject, auto-rejecting")
        local reason = blacklistEntry and blacklistEntry.reason or "blacklisted"
        SendChatMessage("[AutoInvite+] Auto-declined: " .. reason, "WHISPER", nil, name)
        return false
    end

    -- Proper name capitalization
    local properName = name:sub(1,1):upper() .. name:sub(2):lower()

    -- Check if player is a favorite
    local isFavorite = AIP.IsPlayerFavorite and AIP.IsPlayerFavorite(name) or false

    -- Check if guild member
    local isGuildMember = AIP.IsPlayerInGuild and AIP.IsPlayerInGuild(name) or false

    -- Try to get class and GS if not provided
    local playerClass = class
    local playerGS = gs
    if not playerGS and AIP.Integrations and AIP.Integrations.GetPlayerGS then
        playerGS = AIP.Integrations.GetPlayerGS(name)
    end

    -- Create queue entry
    local entry = {
        name = properName,
        message = message or "",
        time = time(),
        role = role,
        isBlacklisted = isBlacklisted,
        blacklistReason = blacklistEntry and blacklistEntry.reason or nil,
        isFavorite = isFavorite,
        isGuildMember = isGuildMember,
        class = playerClass,
        gs = playerGS,
    }

    -- Determine position (favorites and guild members can be prioritized)
    local insertPos = #AIP.db.queue + 1
    if isFavorite or isGuildMember then
        -- Insert after other favorites/guild members but before regular players
        for i, existing in ipairs(AIP.db.queue) do
            if not existing.isFavorite and not existing.isGuildMember then
                insertPos = i
                break
            end
        end
    end

    table.insert(AIP.db.queue, insertPos, entry)

    -- Build status message
    local queueMsg = properName .. " added to queue (position #" .. insertPos .. ", " .. #AIP.db.queue .. " total)"
    if isFavorite then
        queueMsg = queueMsg .. " |cFF00FF00[FAVORITE]|r"
    elseif isGuildMember then
        queueMsg = queueMsg .. " |cFF00CCFF[GUILD]|r"
    end
    if isBlacklisted then
        queueMsg = queueMsg .. " |cFFFF0000[BLACKLISTED]|r"
    end
    if role then
        queueMsg = queueMsg .. " [" .. role:upper() .. "]"
    end
    if playerGS then
        queueMsg = queueMsg .. " [GS:" .. playerGS .. "]"
    end
    AIP.Print(queueMsg)

    -- Send queue position notification
    if AIP.db.queueNotifyPosition then
        local posMsg = "[AutoInvite+] Added to queue, position: #" .. insertPos
        if AIP.db.queueTimeout and AIP.db.queueTimeout > 0 then
            posMsg = posMsg .. " (expires in " .. AIP.db.queueTimeout .. " min)"
        end
        SendChatMessage(posMsg, "WHISPER", nil, properName)
    end

    -- Notify other players of position changes if they moved down
    -- Use pcall to prevent errors from breaking the queue operation
    if insertPos < #AIP.db.queue and AIP.db.queueNotifyPosition then
        for i = insertPos + 1, #AIP.db.queue do
            local movedEntry = AIP.db.queue[i]
            if movedEntry and movedEntry.name then
                pcall(SendChatMessage, "[AutoInvite+] Your queue position changed to: #" .. i, "WHISPER", nil, movedEntry.name)
            end
        end
    end

    -- Update UI - show queue panel with new entry
    AIP.ShowQueueWithEntry()

    return true
end

-- Show the queue panel and switch to queue sub-tab
function AIP.ShowQueueWithEntry()
    -- Legacy UI update
    if AIP.UpdateQueueUI then
        AIP.UpdateQueueUI()
    end

    -- CentralGUI update
    if not AIP.CentralGUI then return end

    -- Ensure frame exists
    if not AIP.CentralGUI.Frame then
        AIP.CentralGUI.CreateFrame()
    end

    -- Get the LFM container
    local container = AIP.CentralGUI.Frame and AIP.CentralGUI.Frame.tabContents and AIP.CentralGUI.Frame.tabContents["lfm"]
    if not container then return end

    -- Switch to Queue sub-tab so the new entry is visible
    container.queueSubTab = "queue"

    -- Update tab visuals (active tab)
    if container.queueTabBtn and container.queueTabBtn.bg then
        container.queueTabBtn.bg:SetTexture(0.3, 0.3, 0.4, 1)
        if container.queueTabBtn.text then container.queueTabBtn.text:SetTextColor(1, 0.82, 0) end
    end
    if container.lfgTabBtn and container.lfgTabBtn.bg then
        container.lfgTabBtn.bg:SetTexture(0.15, 0.15, 0.15, 1)
        if container.lfgTabBtn.text then container.lfgTabBtn.text:SetTextColor(0.8, 0.8, 0.8) end
    end
    if container.waitlistTabBtn and container.waitlistTabBtn.bg then
        container.waitlistTabBtn.bg:SetTexture(0.15, 0.15, 0.15, 1)
        if container.waitlistTabBtn.text then container.waitlistTabBtn.text:SetTextColor(0.8, 0.8, 0.8) end
    end

    -- Show queue content, hide others
    if container.queueContent then container.queueContent:Show() end
    if container.lfgContent then container.lfgContent:Hide() end
    if container.waitlistContent then container.waitlistContent:Hide() end

    -- Update the queue panel to show the new entry
    if AIP.CentralGUI.UpdateQueuePanel then
        AIP.CentralGUI.UpdateQueuePanel(container)
    end

    -- Show the main window on LFM tab
    if AIP.CentralGUI.Show then
        AIP.CentralGUI.Show("lfm")
    end
end

-- Remove player from queue by name
function AIP.RemoveFromQueue(name)
    if not name then return false end

    local lowerName = name:lower()
    for i, entry in ipairs(AIP.db.queue) do
        if entry.name:lower() == lowerName then
            table.remove(AIP.db.queue, i)
            AIP.Debug("Removed " .. name .. " from queue")

            if AIP.UpdateQueueUI then
                AIP.UpdateQueueUI()
            end

            return true
        end
    end
    return false
end

-- Remove player from queue by index
function AIP.RemoveFromQueueByIndex(index)
    if index > 0 and index <= #AIP.db.queue then
        local entry = table.remove(AIP.db.queue, index)
        AIP.Debug("Removed " .. entry.name .. " from queue")

        if AIP.UpdateQueueUI then
            AIP.UpdateQueueUI()
        end

        return true
    end
    return false
end

-- Invite player from queue by index
function AIP.InviteFromQueue(index)
    if index > 0 and index <= #AIP.db.queue then
        local entry = AIP.db.queue[index]

        -- Send response message before invite
        if AIP.db.responseInvite and AIP.db.responseInvite ~= "" then
            SendChatMessage(AIP.db.responseInvite, "WHISPER", nil, entry.name)
        end

        if AIP.InvitePlayer(entry.name) then
            AIP.RemoveFromQueueByIndex(index)
            return true
        end
    end
    return false
end

-- Invite player from queue by name (safer for UI callbacks)
function AIP.InviteFromQueueByName(name)
    if not name or not AIP.db or not AIP.db.queue then return false end

    local lowerName = name:lower()
    for i, entry in ipairs(AIP.db.queue) do
        if entry.name and entry.name:lower() == lowerName then
            -- Send response message before invite
            if AIP.db.responseInvite and AIP.db.responseInvite ~= "" then
                SendChatMessage(AIP.db.responseInvite, "WHISPER", nil, entry.name)
            end

            if AIP.InvitePlayer(entry.name) then
                AIP.RemoveFromQueueByIndex(i)
                -- Refresh UI
                AIP.ShowQueueWithEntry()
                return true
            end
            break
        end
    end
    return false
end

-- Reject player from queue by index (with optional blacklist)
function AIP.RejectFromQueue(index, addToBlacklist, reason)
    if index <= 0 or index > #AIP.db.queue then return false end

    local entry = AIP.db.queue[index]
    if not entry then return false end

    -- Send rejection whisper
    if AIP.db.responseReject and AIP.db.responseReject ~= "" then
        SendChatMessage(AIP.db.responseReject, "WHISPER", nil, entry.name)
    end

    -- Optionally add to blacklist
    if addToBlacklist then
        AIP.AddToBlacklist(entry.name, reason or "Rejected from queue", "queue")
    end

    -- Remove from queue
    AIP.RemoveFromQueueByIndex(index)

    AIP.Print("Rejected " .. entry.name .. " from queue" .. (addToBlacklist and " (added to blacklist)" or ""))

    return true
end

-- Reject player from queue by name (safer for UI callbacks)
function AIP.RejectFromQueueByName(name, addToBlacklist, reason)
    if not name or not AIP.db or not AIP.db.queue then return false end

    local lowerName = name:lower()
    for i, entry in ipairs(AIP.db.queue) do
        if entry.name and entry.name:lower() == lowerName then
            -- Send rejection whisper
            if AIP.db.responseReject and AIP.db.responseReject ~= "" then
                SendChatMessage(AIP.db.responseReject, "WHISPER", nil, entry.name)
            end

            -- Optionally add to blacklist
            if addToBlacklist then
                AIP.AddToBlacklist(entry.name, reason or "Rejected from queue", "queue")
            end

            -- Remove from queue
            AIP.RemoveFromQueueByIndex(i)

            AIP.Print("Rejected " .. entry.name .. " from queue" .. (addToBlacklist and " (added to blacklist)" or ""))

            -- Refresh UI
            AIP.ShowQueueWithEntry()
            return true
        end
    end
    return false
end

-- Move player from queue to waitlist
function AIP.MoveToWaitlist(index, role, note)
    if index <= 0 or index > #AIP.db.queue then return false end

    local entry = AIP.db.queue[index]
    if not entry then return false end

    -- Add to waitlist (AddToWaitlist handles the whisper notification internally)
    if AIP.AddToWaitlist then
        local success = AIP.AddToWaitlist(entry.name, role or "DPS", note, entry.class, entry.gs)
        if success then
            -- Remove from queue
            AIP.RemoveFromQueueByIndex(index)
            return true
        end
    else
        AIP.Print("Waitlist module not available")
    end

    return false
end

-- Clear entire queue
function AIP.ClearQueue()
    AIP.db.queue = {}
    AIP.Print("Queue cleared")

    if AIP.UpdateQueueUI then
        AIP.UpdateQueueUI()
    end
end

-- Get queue count
function AIP.GetQueueCount()
    return #(AIP.db.queue or {})
end

-- Get queue entries (optionally filtered)
function AIP.GetQueueEntries(showBlacklisted)
    local entries = {}
    if not AIP.db or not AIP.db.queue then return entries end

    for i, entry in ipairs(AIP.db.queue) do
        if showBlacklisted == nil or showBlacklisted == true or not entry.isBlacklisted then
            table.insert(entries, {
                index = i,
                name = entry.name,
                message = entry.message,
                time = entry.time,
                isBlacklisted = entry.isBlacklisted,
                blacklistReason = entry.blacklistReason,
                class = entry.class,
                gs = entry.gs,
            })
        end
    end

    return entries
end

-- Format time ago for display
function AIP.FormatTimeAgo(timestamp)
    if not timestamp then return "-" end
    local diff = time() - timestamp
    if diff < 60 then
        return diff .. "s"
    elseif diff < 3600 then
        return math.floor(diff / 60) .. "m"
    else
        return math.floor(diff / 3600) .. "h"
    end
end

-- ============================================================================
-- INVITE ALL SYSTEM
-- ============================================================================
local inviteAllRunning = false
local inviteAllIndex = 1
local inviteTimer = CreateFrame("Frame")
local inviteTimerElapsed = 0
local INVITE_DELAY = 0.5

inviteTimer:SetScript("OnUpdate", function(self, elapsed)
    if not inviteAllRunning then return end
    if not AIP.db or not AIP.db.queue then return end

    inviteTimerElapsed = inviteTimerElapsed + elapsed
    if inviteTimerElapsed < INVITE_DELAY then return end

    inviteTimerElapsed = 0

    if #AIP.db.queue == 0 then
        inviteAllRunning = false
        AIP.Print("Finished inviting from queue")
        return
    end

    -- Skip blacklisted players
    local entry = AIP.db.queue[1]
    if entry then
        if entry.isBlacklisted and AIP.db.blacklistMode == "reject" then
            -- Auto-reject blacklisted
            AIP.RejectFromQueue(1, false)
        else
            if AIP.InvitePlayer(entry.name) then
                -- Send invite message
                if AIP.db.responseInvite and AIP.db.responseInvite ~= "" then
                    SendChatMessage(AIP.db.responseInvite, "WHISPER", nil, entry.name)
                end
                table.remove(AIP.db.queue, 1)
            else
                -- Move failed invite to end of queue
                table.remove(AIP.db.queue, 1)
                table.insert(AIP.db.queue, entry)
                inviteAllIndex = inviteAllIndex + 1

                -- Stop if we've tried everyone
                if inviteAllIndex > #AIP.db.queue + 1 then
                    inviteAllRunning = false
                    AIP.Print("Finished inviting from queue (some failed)")
                    return
                end
            end
        end
    end

    if AIP.UpdateQueueUI then
        AIP.UpdateQueueUI()
    end
end)

function AIP.InviteAllFromQueue()
    if #AIP.db.queue == 0 then
        AIP.Print("Queue is empty")
        return
    end

    if inviteAllRunning then
        inviteAllRunning = false
        AIP.Print("Stopped invite all")
        return
    end

    inviteAllRunning = true
    inviteAllIndex = 1
    inviteTimerElapsed = INVITE_DELAY  -- Start immediately
    AIP.Print("Starting to invite " .. #AIP.db.queue .. " players from queue...")
end

-- ============================================================================
-- QUEUE TIMEOUT PROCESSING
-- ============================================================================
local timeoutTimer = CreateFrame("Frame")
local timeoutCheckElapsed = 0
local TIMEOUT_CHECK_INTERVAL = 10  -- Check every 10 seconds

timeoutTimer:SetScript("OnUpdate", function(self, elapsed)
    -- Skip if no timeout configured or queue empty
    if not AIP.db or not AIP.db.queueTimeout or AIP.db.queueTimeout <= 0 then return end
    if not AIP.db.queue or #AIP.db.queue == 0 then return end

    timeoutCheckElapsed = timeoutCheckElapsed + elapsed
    if timeoutCheckElapsed < TIMEOUT_CHECK_INTERVAL then return end
    timeoutCheckElapsed = 0

    local now = time()
    local timeoutSeconds = AIP.db.queueTimeout * 60  -- Convert minutes to seconds
    local removed = {}

    -- Find expired entries (iterate backwards for safe removal)
    for i = #AIP.db.queue, 1, -1 do
        local entry = AIP.db.queue[i]
        if entry and entry.time and (now - entry.time) >= timeoutSeconds then
            -- Notify player before removal
            if AIP.db.queueNotifyPosition then
                SendChatMessage("[AutoInvite+] Your queue position has expired.", "WHISPER", nil, entry.name)
            end
            table.insert(removed, entry.name)
            table.remove(AIP.db.queue, i)
        end
    end

    -- Report removals and update UI
    if #removed > 0 then
        AIP.Print("Removed " .. #removed .. " expired entries from queue: " .. table.concat(removed, ", "))
        if AIP.UpdateQueueUI then
            AIP.UpdateQueueUI()
        end
    end
end)

-- ============================================================================
-- QUEUE AUTO-PROCESSING
-- ============================================================================
local autoProcessTimer = CreateFrame("Frame")
local autoProcessElapsed = 0
local AUTO_PROCESS_INTERVAL = 2  -- Check every 2 seconds
local lastRaidSlots = 0

-- Get current available raid slots
local function GetAvailableRaidSlots()
    local numRaid = GetNumRaidMembers()
    if numRaid > 0 then
        return 40 - numRaid  -- Max raid size minus current members
    end
    local numParty = GetNumPartyMembers()
    if numParty > 0 then
        return 4 - numParty  -- Max party size minus current members (not counting self)
    end
    return 4  -- Solo, can invite 4 to party
end

-- Check if we are group leader
local function IsGroupLeader()
    if GetNumRaidMembers() > 0 then
        return IsRaidLeader()
    elseif GetNumPartyMembers() > 0 then
        return IsPartyLeader()
    end
    return true  -- Solo = leader
end

autoProcessTimer:SetScript("OnUpdate", function(self, elapsed)
    -- Skip if auto-process disabled or not leader
    if not AIP.db or not AIP.db.queueAutoProcess then return end
    if not IsGroupLeader() then return end
    if not AIP.db.queue or #AIP.db.queue == 0 then return end

    autoProcessElapsed = autoProcessElapsed + elapsed
    if autoProcessElapsed < AUTO_PROCESS_INTERVAL then return end
    autoProcessElapsed = 0

    local currentSlots = GetAvailableRaidSlots()

    -- Only process if we gained slots (someone left or raid converted)
    if currentSlots > lastRaidSlots and currentSlots > 0 then
        local slotsGained = currentSlots - lastRaidSlots

        -- Invite up to slotsGained players from the front of the queue
        local invited = 0
        local failures = 0
        local maxAttempts = #AIP.db.queue  -- Track original queue size to prevent infinite loop
        while invited < slotsGained and #AIP.db.queue > 0 and failures < maxAttempts do
            local entry = AIP.db.queue[1]
            if entry then
                -- Skip blacklisted if mode is reject
                if entry.isBlacklisted and AIP.db.blacklistMode == "reject" then
                    AIP.RejectFromQueue(1, false)
                else
                    -- Attempt to invite
                    if AIP.db.responseInvite and AIP.db.responseInvite ~= "" then
                        SendChatMessage(AIP.db.responseInvite, "WHISPER", nil, entry.name)
                    end
                    if AIP.InvitePlayer(entry.name) then
                        AIP.Print("Auto-invited " .. entry.name .. " from queue (slot opened)")
                        table.remove(AIP.db.queue, 1)
                        invited = invited + 1

                        if AIP.UpdateQueueUI then
                            AIP.UpdateQueueUI()
                        end
                    else
                        -- Move failed to end of queue and continue trying others
                        table.remove(AIP.db.queue, 1)
                        table.insert(AIP.db.queue, entry)
                        failures = failures + 1
                    end
                end
            end
        end
    end

    lastRaidSlots = currentSlots
end)

-- Manual trigger for auto-process (called when slots open via other means)
function AIP.TriggerAutoProcess()
    if not AIP.db or not AIP.db.queueAutoProcess then return end
    if not AIP.db.queue or #AIP.db.queue == 0 then return end

    local slots = GetAvailableRaidSlots()
    if slots > 0 then
        -- Force lastRaidSlots to 0 to trigger processing on next tick
        lastRaidSlots = 0
        autoProcessElapsed = AUTO_PROCESS_INTERVAL
        AIP.Debug("Auto-process triggered, " .. slots .. " slots available")
    end
end

-- ============================================================================
-- LEGACY QUEUE UI (standalone window)
-- ============================================================================
local queueFrame = nil
local queueButtons = {}
local QUEUE_BUTTONS_SHOWN = 10

local function CreateQueueUI()
    if queueFrame then return queueFrame end

    -- Main frame
    local frame = CreateFrame("Frame", "AIPQueueFrame", UIParent)
    frame:SetSize(550, 450)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()

    -- Background
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Invite Queue")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Column headers
    local colNum = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colNum:SetPoint("TOPLEFT", 20, -45)
    colNum:SetText("#")
    colNum:SetTextColor(1, 0.82, 0)

    local colPlayer = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colPlayer:SetPoint("TOPLEFT", 40, -45)
    colPlayer:SetText("Player")
    colPlayer:SetTextColor(1, 0.82, 0)

    local colMessage = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colMessage:SetPoint("TOPLEFT", 130, -45)
    colMessage:SetText("Message")
    colMessage:SetTextColor(1, 0.82, 0)

    local colTime = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colTime:SetPoint("TOPLEFT", 280, -45)
    colTime:SetText("Time")
    colTime:SetTextColor(1, 0.82, 0)

    local colBL = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colBL:SetPoint("TOPLEFT", 320, -45)
    colBL:SetText("BL?")
    colBL:SetTextColor(1, 0.82, 0)

    -- Scrollframe for list
    local scrollFrame = CreateFrame("ScrollFrame", "AIPQueueScrollFrame", frame, "FauxScrollFrameTemplate")
    scrollFrame:SetSize(480, 280)
    scrollFrame:SetPoint("TOPLEFT", 20, -60)
    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, 28, AIP.UpdateQueueUI)
    end)

    -- Create list buttons
    for i = 1, QUEUE_BUTTONS_SHOWN do
        local btn = CreateFrame("Frame", "AIPQueueEntry"..i, frame)
        btn:SetSize(470, 28)
        btn:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, -((i-1) * 28))

        -- Highlight
        local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        highlight:SetBlendMode("ADD")

        -- Number
        local numText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        numText:SetPoint("LEFT", 0, 0)
        numText:SetWidth(20)
        numText:SetJustifyH("CENTER")
        btn.numText = numText

        -- Player name
        local nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", 22, 0)
        nameText:SetWidth(85)
        nameText:SetJustifyH("LEFT")
        btn.nameText = nameText

        -- Message
        local msgText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        msgText:SetPoint("LEFT", 110, 0)
        msgText:SetWidth(145)
        msgText:SetJustifyH("LEFT")
        msgText:SetTextColor(0.7, 0.7, 0.7)
        btn.msgText = msgText

        -- Time
        local timeText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        timeText:SetPoint("LEFT", 260, 0)
        timeText:SetWidth(35)
        timeText:SetJustifyH("CENTER")
        timeText:SetTextColor(0.5, 0.5, 0.5)
        btn.timeText = timeText

        -- Blacklist indicator
        local blText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        blText:SetPoint("LEFT", 300, 0)
        blText:SetWidth(25)
        blText:SetJustifyH("CENTER")
        btn.blText = blText

        -- Invite button
        local invBtn = CreateFrame("Button", nil, btn, "UIPanelButtonTemplate")
        invBtn:SetSize(35, 20)
        invBtn:SetPoint("LEFT", 328, 0)
        invBtn:SetText("Inv")
        invBtn.index = i
        invBtn:SetScript("OnClick", function(self)
            local offset = FauxScrollFrame_GetOffset(_G["AIPQueueScrollFrame"])
            AIP.InviteFromQueue(offset + self.index)
        end)
        btn.invBtn = invBtn

        -- Reject button
        local rejBtn = CreateFrame("Button", nil, btn, "UIPanelButtonTemplate")
        rejBtn:SetSize(35, 20)
        rejBtn:SetPoint("LEFT", 365, 0)
        rejBtn:SetText("Rej")
        rejBtn.index = i
        rejBtn:SetScript("OnClick", function(self)
            local offset = FauxScrollFrame_GetOffset(_G["AIPQueueScrollFrame"])
            AIP.RejectFromQueue(offset + self.index, false)
        end)
        btn.rejBtn = rejBtn

        -- Waitlist button
        local waitBtn = CreateFrame("Button", nil, btn, "UIPanelButtonTemplate")
        waitBtn:SetSize(25, 20)
        waitBtn:SetPoint("LEFT", 402, 0)
        waitBtn:SetText("W")
        waitBtn.index = i
        waitBtn:SetScript("OnClick", function(self)
            local offset = FauxScrollFrame_GetOffset(_G["AIPQueueScrollFrame"])
            AIP.MoveToWaitlist(offset + self.index)
        end)
        waitBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Move to Waitlist")
            GameTooltip:Show()
        end)
        waitBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        btn.waitBtn = waitBtn

        -- Blacklist button
        local blBtn = CreateFrame("Button", nil, btn, "UIPanelButtonTemplate")
        blBtn:SetSize(25, 20)
        blBtn:SetPoint("LEFT", 429, 0)
        blBtn:SetText("B")
        blBtn.index = i
        blBtn:SetScript("OnClick", function(self)
            local offset = FauxScrollFrame_GetOffset(_G["AIPQueueScrollFrame"])
            local idx = offset + self.index
            if idx <= #AIP.db.queue then
                local entry = AIP.db.queue[idx]
                StaticPopupDialogs["AIP_QUEUE_BLACKLIST"] = {
                    text = "Reject and blacklist " .. entry.name .. "?",
                    button1 = "Yes",
                    button2 = "No",
                    OnAccept = function()
                        AIP.RejectFromQueue(idx, true, "Rejected from queue")
                    end,
                    timeout = 0,
                    whileDead = true,
                    hideOnEscape = true,
                }
                StaticPopup_Show("AIP_QUEUE_BLACKLIST")
            end
        end)
        blBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Reject + Blacklist")
            GameTooltip:Show()
        end)
        blBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        btn.blBtn = blBtn

        btn:Hide()
        queueButtons[i] = btn
    end

    -- Bottom buttons
    local inviteAllBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    inviteAllBtn:SetSize(100, 22)
    inviteAllBtn:SetPoint("BOTTOMLEFT", 20, 55)
    inviteAllBtn:SetText("Invite All")
    inviteAllBtn:SetScript("OnClick", function()
        AIP.InviteAllFromQueue()
    end)

    local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearBtn:SetSize(80, 22)
    clearBtn:SetPoint("LEFT", inviteAllBtn, "RIGHT", 10, 0)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        StaticPopupDialogs["AIP_CLEAR_QUEUE"] = {
            text = "Clear entire queue?",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
                AIP.ClearQueue()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("AIP_CLEAR_QUEUE")
    end)

    local waitlistBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    waitlistBtn:SetSize(90, 22)
    waitlistBtn:SetPoint("LEFT", clearBtn, "RIGHT", 10, 0)
    waitlistBtn:SetText("Waitlist")
    waitlistBtn:SetScript("OnClick", function()
        if AIP.ToggleWaitlistUI then
            AIP.ToggleWaitlistUI()
        end
    end)

    -- Queue count display
    local countText = frame:CreateFontString("AIPQueueCount", "OVERLAY", "GameFontNormal")
    countText:SetPoint("BOTTOMRIGHT", -25, 60)
    countText:SetText("0 in queue")
    frame.countText = countText

    -- Blacklist mode indicator
    local modeText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    modeText:SetPoint("BOTTOMLEFT", 20, 25)
    modeText:SetText("Blacklist Mode: Flag")
    frame.modeText = modeText

    -- Mode toggle button
    local modeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    modeBtn:SetSize(100, 20)
    modeBtn:SetPoint("LEFT", modeText, "RIGHT", 10, 0)
    modeBtn:SetText("Toggle Mode")
    modeBtn:SetScript("OnClick", function()
        if AIP.db.blacklistMode == "flag" then
            AIP.db.blacklistMode = "reject"
        else
            AIP.db.blacklistMode = "flag"
        end
        AIP.UpdateQueueUI()
        AIP.Print("Blacklist mode: " .. AIP.db.blacklistMode)
    end)

    -- Make closeable with Escape
    tinsert(UISpecialFrames, frame:GetName())

    queueFrame = frame
    return frame
end

-- Update the queue UI (both legacy and CentralGUI)
function AIP.UpdateQueueUI()
    -- Update CentralGUI queue panel if it exists
    if AIP.CentralGUI and AIP.CentralGUI.UpdateQueuePanel and AIP.CentralGUI.Frame then
        local container = AIP.CentralGUI.Frame.tabContents and AIP.CentralGUI.Frame.tabContents["lfm"]
        if container then
            AIP.CentralGUI.UpdateQueuePanel(container)
        end
    end

    if not queueFrame then
        CreateQueueUI()
    end

    if not queueFrame:IsVisible() then return end

    local queue = AIP.db.queue or {}
    local numEntries = #queue

    FauxScrollFrame_Update(_G["AIPQueueScrollFrame"], numEntries, QUEUE_BUTTONS_SHOWN, 28)

    local offset = FauxScrollFrame_GetOffset(_G["AIPQueueScrollFrame"])

    for i = 1, QUEUE_BUTTONS_SHOWN do
        local index = offset + i
        local btn = queueButtons[i]
        btn.invBtn.index = i
        btn.rejBtn.index = i
        btn.waitBtn.index = i
        btn.blBtn.index = i

        if index <= numEntries then
            local entry = queue[index]
            btn.numText:SetText(index)
            btn.nameText:SetText(entry.name)
            btn.msgText:SetText((entry.message or ""):sub(1, 25))
            btn.timeText:SetText(AIP.FormatTimeAgo(entry.time))

            -- Blacklist indicator
            if entry.isBlacklisted then
                btn.blText:SetText("YES")
                btn.blText:SetTextColor(1, 0.3, 0.3)
                btn.nameText:SetTextColor(1, 0.5, 0.5)  -- Red tint for blacklisted

                -- Show reason on hover
                btn:SetScript("OnEnter", function(self)
                    if entry.blacklistReason then
                        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                        GameTooltip:AddLine("Blacklisted", 1, 0.3, 0.3)
                        GameTooltip:AddLine(entry.blacklistReason, 1, 1, 1)
                        GameTooltip:Show()
                    end
                end)
                btn:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
            else
                btn.blText:SetText("-")
                btn.blText:SetTextColor(0.5, 0.5, 0.5)
                btn.nameText:SetTextColor(1, 1, 1)
                btn:SetScript("OnEnter", nil)
                btn:SetScript("OnLeave", nil)
            end

            btn:Show()
        else
            btn:Hide()
        end
    end

    queueFrame.countText:SetText(numEntries .. " in queue")

    -- Update blacklist mode display
    local modeDisplay = (AIP.db.blacklistMode == "reject") and "|cFFFF0000Auto-Reject|r" or "|cFFFFFF00Flag Only|r"
    queueFrame.modeText:SetText("Blacklist Mode: " .. modeDisplay)
end

-- Toggle queue UI
function AIP.ToggleQueueUI()
    local frame = CreateQueueUI()

    if frame:IsVisible() then
        frame:Hide()
    else
        frame:Show()
        AIP.UpdateQueueUI()
    end
end
