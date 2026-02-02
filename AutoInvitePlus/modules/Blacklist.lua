-- AutoInvite Plus - Blacklist Module (Enhanced v4.1)
-- Manages the player blacklist with reason, source, and notes

local AIP = AutoInvitePlus

-- ============================================================================
-- DATA STRUCTURE
-- ============================================================================
-- AIP.db.blacklist = {
--     ["PlayerName"] = {
--         name = "PlayerName",
--         reason = "Ninja looter",
--         addedTime = timestamp,
--         source = "manual" | "queue" | "lfm" | "roster",
--         notes = "Additional details..."
--     }
-- }
-- AIP.db.blacklistMode = "flag" | "reject"
-- ============================================================================

-- Migrate old blacklist format (array of names) to new format (keyed table)
local function MigrateBlacklistData()
    if not AIP.db or not AIP.db.blacklist then return end

    -- Check if migration is needed (old format is array)
    if #AIP.db.blacklist > 0 and type(AIP.db.blacklist[1]) == "string" then
        local oldList = AIP.db.blacklist
        AIP.db.blacklist = {}

        for _, name in ipairs(oldList) do
            AIP.db.blacklist[name:lower()] = {
                name = name,
                reason = "Migrated from old blacklist",
                addedTime = time(),
                source = "manual",
                notes = "",
            }
        end

        AIP.Debug("Migrated " .. #oldList .. " blacklist entries to new format")
    end
end

-- Initialize blacklist on load
local initFrame = CreateFrame("Frame")
local blacklistInitialized = false
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, arg1)
    if arg1 == "AutoInvitePlus" then
        -- Guard against multiple initialization attempts
        if blacklistInitialized then return end
        blacklistInitialized = true

        -- Unregister to prevent future triggers
        self:UnregisterEvent("ADDON_LOADED")

        -- Delay migration to ensure db is ready
        local delayFrame = CreateFrame("Frame")
        delayFrame.elapsed = 0
        delayFrame:SetScript("OnUpdate", function(df, elapsed)
            df.elapsed = df.elapsed + elapsed
            if df.elapsed >= 0.5 then
                MigrateBlacklistData()
                -- Initialize blacklistMode if not set
                if AIP.db and AIP.db.blacklistMode == nil then
                    AIP.db.blacklistMode = "flag"
                end
                df:SetScript("OnUpdate", nil)
                df:Hide()
            end
        end)
    end
end)

-- ============================================================================
-- CORE FUNCTIONS
-- ============================================================================

-- Check if a player is blacklisted (returns entry or nil)
function AIP.IsBlacklisted(name)
    if not AIP.db or not AIP.db.blacklist then return false end
    if not name then return false end

    local entry = AIP.db.blacklist[name:lower()]
    return entry ~= nil, entry
end

-- Get blacklist entry for a player
function AIP.GetBlacklistEntry(name)
    if not AIP.db or not AIP.db.blacklist or not name then return nil end
    return AIP.db.blacklist[name:lower()]
end

-- Add player to blacklist
function AIP.AddToBlacklist(name, reason, source, notes)
    if not name or name:trim() == "" then
        AIP.Print("Please specify a player name")
        return false
    end
    if not AIP.db or not AIP.db.blacklist then return false end

    name = name:trim()
    local lowerName = name:lower()

    -- Check if already blacklisted
    if AIP.db.blacklist[lowerName] then
        AIP.Print(name .. " is already blacklisted")
        return false
    end

    -- Create entry with proper capitalization
    local properName = name:sub(1,1):upper() .. name:sub(2):lower()

    AIP.db.blacklist[lowerName] = {
        name = properName,
        reason = reason or "No reason specified",
        addedTime = time(),
        source = source or "manual",
        notes = notes or "",
    }

    AIP.Print("Added " .. properName .. " to blacklist" .. (reason and (" (" .. reason .. ")") or ""))

    -- Update UI if open
    if AIP.UpdateBlacklistUI then
        AIP.UpdateBlacklistUI()
    end
    if AIP.Panels and AIP.Panels.Blacklist and AIP.Panels.Blacklist.Update then
        AIP.Panels.Blacklist.Update()
    end

    return true
end

-- Update existing blacklist entry
function AIP.UpdateBlacklistEntry(name, reason, notes)
    if not name then return false end
    if not AIP.db or not AIP.db.blacklist then return false end

    local lowerName = name:lower()
    local entry = AIP.db.blacklist[lowerName]

    if not entry then
        AIP.Print(name .. " is not blacklisted")
        return false
    end

    if reason then entry.reason = reason end
    if notes then entry.notes = notes end

    AIP.Print("Updated blacklist entry for " .. entry.name)

    if AIP.UpdateBlacklistUI then
        AIP.UpdateBlacklistUI()
    end
    if AIP.Panels and AIP.Panels.Blacklist and AIP.Panels.Blacklist.Update then
        AIP.Panels.Blacklist.Update()
    end

    return true
end

-- Remove player from blacklist
function AIP.RemoveFromBlacklist(name)
    if not name or name:trim() == "" then
        AIP.Print("Please specify a player name")
        return false
    end
    if not AIP.db or not AIP.db.blacklist then return false end

    local lowerName = name:lower():trim()
    local entry = AIP.db.blacklist[lowerName]

    if not entry then
        AIP.Print(name .. " was not found in blacklist")
        return false
    end

    local displayName = entry.name
    AIP.db.blacklist[lowerName] = nil
    AIP.Print("Removed " .. displayName .. " from blacklist")

    -- Update UI if open
    if AIP.UpdateBlacklistUI then
        AIP.UpdateBlacklistUI()
    end
    if AIP.Panels and AIP.Panels.Blacklist and AIP.Panels.Blacklist.Update then
        AIP.Panels.Blacklist.Update()
    end

    return true
end

-- Clear entire blacklist
function AIP.ClearBlacklist()
    AIP.db.blacklist = {}
    AIP.Print("Blacklist cleared")

    if AIP.UpdateBlacklistUI then
        AIP.UpdateBlacklistUI()
    end
    if AIP.Panels and AIP.Panels.Blacklist and AIP.Panels.Blacklist.Update then
        AIP.Panels.Blacklist.Update()
    end
end

-- Get blacklist count
function AIP.GetBlacklistCount()
    if not AIP.db or not AIP.db.blacklist then return 0 end

    local count = 0
    for _ in pairs(AIP.db.blacklist) do
        count = count + 1
    end
    return count
end

-- Get all blacklist entries as sorted array
function AIP.GetBlacklistEntries(searchFilter, sourceFilter)
    local entries = {}

    if not AIP.db or not AIP.db.blacklist then return entries end

    for _, entry in pairs(AIP.db.blacklist) do
        local include = true

        -- Apply search filter
        if searchFilter and searchFilter ~= "" then
            local search = searchFilter:lower()
            local matchName = entry.name:lower():find(search, 1, true)
            local matchReason = entry.reason and entry.reason:lower():find(search, 1, true)
            local matchNotes = entry.notes and entry.notes:lower():find(search, 1, true)
            include = matchName or matchReason or matchNotes
        end

        -- Apply source filter
        if include and sourceFilter and sourceFilter ~= "all" then
            include = entry.source == sourceFilter
        end

        if include then
            table.insert(entries, entry)
        end
    end

    -- Sort by addedTime (newest first)
    table.sort(entries, function(a, b)
        return (a.addedTime or 0) > (b.addedTime or 0)
    end)

    return entries
end

-- ============================================================================
-- EXPORT/IMPORT FUNCTIONS (Enhanced v4.3)
-- ============================================================================

-- Export format constants
AIP.ExportFormats = {
    SIMPLE = "simple",     -- Name;Reason (backwards compatible)
    FULL = "full",         -- Name|Reason|Source|Notes|Timestamp
    CSV = "csv",           -- CSV with headers
}

-- Export blacklist as string (for sharing)
-- format: "simple" = Name;Reason, "full" = Name|Reason|Source|Notes|Time, "csv" = CSV with headers
function AIP.ExportBlacklist(format)
    format = format or "simple"
    local lines = {}

    if format == "csv" then
        -- CSV header
        table.insert(lines, "Name,Reason,Source,Notes,Date Added")
    end

    -- Sort entries by name
    local sortedEntries = {}
    for _, entry in pairs(AIP.db.blacklist) do
        table.insert(sortedEntries, entry)
    end
    table.sort(sortedEntries, function(a, b)
        return (a.name or "") < (b.name or "")
    end)

    for _, entry in ipairs(sortedEntries) do
        local line
        if format == "simple" then
            -- Simple format: Name;Reason (backwards compatible)
            line = entry.name
            if entry.reason and entry.reason ~= "" and entry.reason ~= "No reason specified" then
                line = line .. ";" .. entry.reason
            end
        elseif format == "full" then
            -- Full format: Name|Reason|Source|Notes|Timestamp
            local reason = (entry.reason or ""):gsub("|", "/")  -- Escape pipe chars
            local notes = (entry.notes or ""):gsub("|", "/")
            local source = entry.source or "manual"
            local timestamp = entry.addedTime or 0
            line = string.format("%s|%s|%s|%s|%d", entry.name, reason, source, notes, timestamp)
        elseif format == "csv" then
            -- CSV format with proper escaping
            local function escapeCSV(str)
                if not str then return "" end
                if str:find('[,"\n]') then
                    return '"' .. str:gsub('"', '""') .. '"'
                end
                return str
            end
            local dateStr = entry.addedTime and date("%Y-%m-%d %H:%M", entry.addedTime) or ""
            line = string.format("%s,%s,%s,%s,%s",
                escapeCSV(entry.name),
                escapeCSV(entry.reason or ""),
                escapeCSV(entry.source or "manual"),
                escapeCSV(entry.notes or ""),
                escapeCSV(dateStr))
        end
        table.insert(lines, line)
    end

    return table.concat(lines, "\n")
end

-- Parse import data and return entries (for preview)
function AIP.ParseImportData(data)
    local entries = {}
    local errors = {}
    local format = "unknown"

    if not data or data:trim() == "" then
        return entries, errors, format
    end

    local lines = {}
    for line in data:gmatch("[^\n]+") do
        table.insert(lines, line)
    end

    -- Detect format based on first line
    local firstLine = lines[1] or ""
    if firstLine:match("^Name,Reason,Source,Notes,Date Added") then
        format = "csv"
        table.remove(lines, 1)  -- Remove header
    elseif firstLine:find("|") then
        format = "full"
    else
        format = "simple"
    end

    for lineNum, line in ipairs(lines) do
        line = line:trim()
        if line ~= "" and not line:match("^#") then  -- Skip empty lines and comments
            local entry = nil

            if format == "csv" then
                -- Parse CSV (simple parsing, handles quoted fields)
                local function parseCSV(str)
                    local result = {}
                    local field = ""
                    local inQuotes = false
                    local i = 1
                    while i <= #str do
                        local c = str:sub(i, i)
                        if c == '"' then
                            if inQuotes and str:sub(i+1, i+1) == '"' then
                                field = field .. '"'
                                i = i + 1
                            else
                                inQuotes = not inQuotes
                            end
                        elseif c == ',' and not inQuotes then
                            table.insert(result, field)
                            field = ""
                        else
                            field = field .. c
                        end
                        i = i + 1
                    end
                    table.insert(result, field)
                    return result
                end
                local fields = parseCSV(line)
                if fields[1] and fields[1] ~= "" then
                    entry = {
                        name = fields[1]:trim(),
                        reason = (fields[2] or ""):trim(),
                        source = (fields[3] or "import"):trim(),
                        notes = (fields[4] or ""):trim(),
                        -- Ignore date from import, use current time
                    }
                else
                    table.insert(errors, "Line " .. lineNum .. ": Empty name")
                end
            elseif format == "full" then
                -- Parse full format: Name|Reason|Source|Notes|Timestamp
                local parts = {strsplit("|", line)}
                if parts[1] and parts[1] ~= "" then
                    entry = {
                        name = parts[1]:trim(),
                        reason = (parts[2] or ""):trim(),
                        source = (parts[3] or "import"):trim(),
                        notes = (parts[4] or ""):trim(),
                        -- parts[5] is timestamp, ignored on import
                    }
                else
                    table.insert(errors, "Line " .. lineNum .. ": Empty name")
                end
            else
                -- Parse simple format: Name;Reason
                local name, reason = strsplit(";", line, 2)
                name = name and name:trim() or ""
                if name ~= "" then
                    entry = {
                        name = name,
                        reason = reason and reason:trim() or "",
                        source = "import",
                        notes = "",
                    }
                else
                    table.insert(errors, "Line " .. lineNum .. ": Empty name")
                end
            end

            if entry then
                -- Normalize name (handle single-char names safely)
                if #entry.name >= 2 then
                    entry.name = entry.name:sub(1,1):upper() .. entry.name:sub(2):lower()
                elseif #entry.name == 1 then
                    entry.name = entry.name:upper()
                end
                if entry.reason == "" then entry.reason = "Imported" end
                if entry.source == "" then entry.source = "import" end
                table.insert(entries, entry)
            end
        end
    end

    return entries, errors, format
end

-- Import blacklist from string (with options)
-- mode: "merge" = only add new entries, "replace" = clear and import all
function AIP.ImportBlacklist(data, mode)
    mode = mode or "merge"

    local entries, errors, format = AIP.ParseImportData(data)

    if #entries == 0 then
        if #errors > 0 then
            AIP.Print("Import failed: " .. errors[1])
        else
            AIP.Print("No valid entries found to import")
        end
        return 0, 0, errors
    end

    if mode == "replace" then
        AIP.db.blacklist = {}
    end

    local imported = 0
    local skipped = 0

    for _, entry in ipairs(entries) do
        local lowerName = entry.name:lower()
        if not AIP.db.blacklist[lowerName] then
            AIP.db.blacklist[lowerName] = {
                name = entry.name,
                reason = entry.reason,
                addedTime = time(),
                source = entry.source,
                notes = entry.notes,
            }
            imported = imported + 1
        else
            skipped = skipped + 1
        end
    end

    if imported > 0 then
        AIP.Print("Imported " .. imported .. " players" ..
                  (skipped > 0 and " (" .. skipped .. " duplicates skipped)" or ""))
    else
        AIP.Print("No new players imported (" .. skipped .. " already in blacklist)")
    end

    if AIP.UpdateBlacklistUI then
        AIP.UpdateBlacklistUI()
    end
    if AIP.Panels and AIP.Panels.Blacklist and AIP.Panels.Blacklist.Update then
        AIP.Panels.Blacklist.Update()
    end

    return imported, skipped, errors
end

-- Get export statistics for preview
function AIP.GetBlacklistStats()
    local count = 0
    local sources = {}
    for _, entry in pairs(AIP.db.blacklist) do
        count = count + 1
        local source = entry.source or "manual"
        sources[source] = (sources[source] or 0) + 1
    end
    return count, sources
end

-- Format date for display
function AIP.FormatBlacklistDate(timestamp)
    if not timestamp then return "Unknown" end
    return date("%Y-%m-%d", timestamp)
end

-- ============================================================================
-- LEGACY UI (standalone window)
-- ============================================================================
local blacklistFrame = nil
local blacklistButtons = {}
local blacklistScrollOffset = 0
local BLACKLIST_BUTTONS_SHOWN = 10

local function CreateBlacklistUI()
    if blacklistFrame then return blacklistFrame end

    -- Main frame
    local frame = CreateFrame("Frame", "AIPBlacklistFrame", UIParent)
    frame:SetSize(400, 450)
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
    title:SetText("Blacklist")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Search box
    local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", 15, -40)
    searchLabel:SetText("Search:")

    local searchBox = CreateFrame("EditBox", "AIPBlacklistSearch", frame, "InputBoxTemplate")
    searchBox:SetSize(150, 20)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 5, 0)
    searchBox:SetAutoFocus(false)
    frame.searchBox = searchBox
    frame.searchFilter = ""

    searchBox:SetScript("OnTextChanged", function(self)
        frame.searchFilter = self:GetText():lower()
        AIP.UpdateBlacklistUI()
    end)
    searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)

    -- Add player section
    local addLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addLabel:SetPoint("TOPLEFT", 15, -65)
    addLabel:SetText("Add:")

    local inputBox = CreateFrame("EditBox", "AIPBlacklistInput", frame, "InputBoxTemplate")
    inputBox:SetSize(100, 20)
    inputBox:SetPoint("LEFT", addLabel, "RIGHT", 5, 0)
    inputBox:SetAutoFocus(false)

    local reasonBox = CreateFrame("EditBox", "AIPBlacklistReason", frame, "InputBoxTemplate")
    reasonBox:SetSize(120, 20)
    reasonBox:SetPoint("LEFT", inputBox, "RIGHT", 5, 0)
    reasonBox:SetAutoFocus(false)

    local reasonPlaceholder = reasonBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    reasonPlaceholder:SetPoint("LEFT", 5, 0)
    reasonPlaceholder:SetText("Reason...")
    reasonPlaceholder:SetTextColor(0.5, 0.5, 0.5)
    reasonBox.placeholder = reasonPlaceholder

    reasonBox:SetScript("OnTextChanged", function(self)
        self.placeholder:SetShown(self:GetText() == "")
    end)

    local addBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addBtn:SetSize(50, 22)
    addBtn:SetPoint("LEFT", reasonBox, "RIGHT", 5, 0)
    addBtn:SetText("Add")
    addBtn:SetScript("OnClick", function()
        local name = inputBox:GetText()
        local reason = reasonBox:GetText()
        if reason == "" then reason = nil end
        AIP.AddToBlacklist(name, reason, "manual")
        inputBox:SetText("")
        reasonBox:SetText("")
        inputBox:ClearFocus()
        reasonBox:ClearFocus()
    end)

    inputBox:SetScript("OnEnterPressed", function(self)
        reasonBox:SetFocus()
    end)
    reasonBox:SetScript("OnEnterPressed", function(self)
        local name = inputBox:GetText()
        local reason = self:GetText()
        if reason == "" then reason = nil end
        AIP.AddToBlacklist(name, reason, "manual")
        inputBox:SetText("")
        self:SetText("")
        inputBox:ClearFocus()
        self:ClearFocus()
    end)
    inputBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    reasonBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)

    -- Column headers
    local colName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colName:SetPoint("TOPLEFT", 20, -95)
    colName:SetText("Name")
    colName:SetTextColor(1, 0.82, 0)

    local colReason = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colReason:SetPoint("TOPLEFT", 100, -95)
    colReason:SetText("Reason")
    colReason:SetTextColor(1, 0.82, 0)

    local colDate = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colDate:SetPoint("TOPLEFT", 250, -95)
    colDate:SetText("Added")
    colDate:SetTextColor(1, 0.82, 0)

    -- Scrollframe for list
    local scrollFrame = CreateFrame("ScrollFrame", "AIPBlacklistScrollFrame", frame, "FauxScrollFrameTemplate")
    scrollFrame:SetSize(350, 250)
    scrollFrame:SetPoint("TOPLEFT", 15, -110)
    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, 25, AIP.UpdateBlacklistUI)
    end)

    -- Create list buttons
    for i = 1, BLACKLIST_BUTTONS_SHOWN do
        local btn = CreateFrame("Frame", "AIPBlacklistButton"..i, frame)
        btn:SetSize(340, 25)
        btn:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 5, -((i-1) * 25))

        -- Highlight texture
        local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        highlight:SetBlendMode("ADD")

        -- Name
        local nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", 5, 0)
        nameText:SetWidth(80)
        nameText:SetJustifyH("LEFT")
        btn.nameText = nameText

        -- Reason
        local reasonText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        reasonText:SetPoint("LEFT", 85, 0)
        reasonText:SetWidth(145)
        reasonText:SetJustifyH("LEFT")
        reasonText:SetTextColor(0.7, 0.7, 0.7)
        btn.reasonText = reasonText

        -- Date
        local dateText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dateText:SetPoint("LEFT", 235, 0)
        dateText:SetWidth(70)
        dateText:SetJustifyH("LEFT")
        dateText:SetTextColor(0.5, 0.5, 0.5)
        btn.dateText = dateText

        -- Remove button
        local removeBtn = CreateFrame("Button", nil, btn, "UIPanelCloseButton")
        removeBtn:SetSize(20, 20)
        removeBtn:SetPoint("RIGHT", -2, 0)
        removeBtn:SetScript("OnClick", function()
            local name = btn.playerName
            if name then
                StaticPopupDialogs["AIP_REMOVE_BLACKLIST"] = {
                    text = "Remove " .. name .. " from blacklist?",
                    button1 = "Yes",
                    button2 = "No",
                    OnAccept = function()
                        AIP.RemoveFromBlacklist(name)
                    end,
                    timeout = 0,
                    whileDead = true,
                    hideOnEscape = true,
                }
                StaticPopup_Show("AIP_REMOVE_BLACKLIST")
            end
        end)
        btn.removeBtn = removeBtn

        btn:Hide()
        blacklistButtons[i] = btn
    end

    -- Bottom buttons
    local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearBtn:SetSize(80, 22)
    clearBtn:SetPoint("BOTTOMLEFT", 20, 15)
    clearBtn:SetText("Clear All")
    clearBtn:SetScript("OnClick", function()
        StaticPopupDialogs["AIP_CLEAR_BLACKLIST"] = {
            text = "Clear entire blacklist?",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
                AIP.ClearBlacklist()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("AIP_CLEAR_BLACKLIST")
    end)

    -- Count display
    local countText = frame:CreateFontString("AIPBlacklistCount", "OVERLAY", "GameFontNormal")
    countText:SetPoint("BOTTOMRIGHT", -25, 20)
    countText:SetText("0 players")
    frame.countText = countText

    -- Make closeable with Escape
    tinsert(UISpecialFrames, frame:GetName())

    blacklistFrame = frame
    return frame
end

-- Update the blacklist UI
function AIP.UpdateBlacklistUI()
    if not blacklistFrame or not blacklistFrame:IsVisible() then return end

    local searchFilter = blacklistFrame.searchFilter or ""
    local entries = AIP.GetBlacklistEntries(searchFilter)
    local numEntries = #entries

    FauxScrollFrame_Update(_G["AIPBlacklistScrollFrame"], numEntries, BLACKLIST_BUTTONS_SHOWN, 25)

    local offset = FauxScrollFrame_GetOffset(_G["AIPBlacklistScrollFrame"])

    for i = 1, BLACKLIST_BUTTONS_SHOWN do
        local index = offset + i
        local btn = blacklistButtons[i]

        if index <= numEntries then
            local entry = entries[index]
            btn.nameText:SetText(entry.name)
            btn.reasonText:SetText((entry.reason or ""):sub(1, 25))
            btn.dateText:SetText(AIP.FormatBlacklistDate(entry.addedTime))
            btn.playerName = entry.name
            btn:Show()
        else
            btn:Hide()
        end
    end

    -- Update count
    local totalCount = AIP.GetBlacklistCount()
    if searchFilter ~= "" then
        blacklistFrame.countText:SetText(numEntries .. "/" .. totalCount .. " players")
    else
        blacklistFrame.countText:SetText(totalCount .. " players")
    end
end

-- Toggle blacklist UI
function AIP.ToggleBlacklistUI()
    local frame = CreateBlacklistUI()

    if frame:IsVisible() then
        frame:Hide()
    else
        frame:Show()
        AIP.UpdateBlacklistUI()
    end
end
