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

-- UTF-8 safe truncation: keep at most maxChars CHARACTERS (not bytes) so a
-- multi-byte sequence is never cut in half (which renders as a garbage glyph).
function AIP.TruncateUtf8(str, maxChars)
    if type(str) ~= "string" then return "" end
    if not maxChars or maxChars < 0 then return str end
    if #str <= maxChars then return str end   -- bytes >= chars, so this is a safe fast path
    local chars, i, n = 0, 1, #str
    while i <= n do
        local b = str:byte(i)
        local len = 1
        if b >= 240 then len = 4
        elseif b >= 224 then len = 3
        elseif b >= 192 then len = 2 end
        if chars >= maxChars then break end
        -- A truncated trailing sequence is dropped rather than kept half-formed.
        if i + len - 1 > n then break end
        chars = chars + 1
        i = i + len
    end
    return str:sub(1, i - 1)
end

-- Hard limits for imported text (hostile / pasted-garbage input).
AIP.BLACKLIST_IMPORT_LIMITS = {
    MAX_BYTES = 262144,    -- whole paste
    MAX_LINES = 3000,      -- non-empty lines examined
    MAX_ENTRIES = 2000,    -- entries returned
    MAX_LINE_BYTES = 1024, -- a single line
    MAX_NAME_BYTES = 36,   -- 12 letters even at 3 bytes each
    MAX_REASON_CHARS = 100,
    MAX_NOTES_CHARS = 200,
    MAX_SOURCE_CHARS = 16,
    MAX_ERRORS = 20,       -- error strings kept (rest summarized)
}

-- Parse import data and return entries (for preview). Never errors: any
-- non-string input yields an empty result; oversized input is capped.
function AIP.ParseImportData(data)
    local L = AIP.BLACKLIST_IMPORT_LIMITS
    local entries = {}
    local errors = {}
    local format = "unknown"
    local droppedErrors = 0

    local function addError(msg)
        if #errors < L.MAX_ERRORS then
            errors[#errors + 1] = msg
        else
            droppedErrors = droppedErrors + 1
        end
    end
    local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

    if type(data) ~= "string" or data == "" then
        return entries, errors, format
    end

    -- Cap total size, cutting at a line boundary so a half-read line can never
    -- turn into a wrong (truncated) player name.
    if #data > L.MAX_BYTES then
        local cut = data:sub(1, L.MAX_BYTES)
        local lastNl = 0
        for pos in cut:gmatch("()[\r\n]") do lastNl = pos end
        cut = lastNl > 0 and cut:sub(1, lastNl - 1) or ""
        data = cut
        addError("Input too large; only the first " .. L.MAX_BYTES .. " bytes were read")
    end

    -- Strip a UTF-8 BOM (Notepad exports)
    if data:sub(1, 3) == "\239\187\191" then data = data:sub(4) end

    if trim(data) == "" then
        return entries, errors, format
    end

    local lines = {}
    local overLines = false
    for line in data:gmatch("[^\r\n]+") do
        if line:find("%S") then
            if #lines >= L.MAX_LINES then overLines = true; break end
            lines[#lines + 1] = line
        end
    end
    if overLines then
        addError("Too many lines; only the first " .. L.MAX_LINES .. " were read")
    end

    -- Detect format from the first meaningful (non-comment) line
    local firstIdx
    for idx = 1, #lines do
        if not trim(lines[idx]):match("^#") then firstIdx = idx; break end
    end
    if not firstIdx then return entries, errors, format end
    local firstLine = lines[firstIdx]
    if firstLine:match("^%s*Name,Reason,Source,Notes,Date Added") then
        format = "csv"
        table.remove(lines, firstIdx)  -- Remove header
    elseif firstLine:find("|", 1, true) then
        format = "full"
    else
        format = "simple"
    end

    local function parseCSV(str)
        local result = {}
        local buf = {}
        local inQuotes = false
        local i, n = 1, #str
        while i <= n do
            local c = str:sub(i, i)
            if c == '"' then
                if inQuotes and str:sub(i + 1, i + 1) == '"' then
                    buf[#buf + 1] = '"'
                    i = i + 1
                else
                    inQuotes = not inQuotes
                end
            elseif c == ',' and not inQuotes then
                result[#result + 1] = table.concat(buf)
                buf = {}
                if #result >= 6 then return result end  -- columns beyond Notes are ignored
            else
                buf[#buf + 1] = c
            end
            i = i + 1
        end
        result[#result + 1] = table.concat(buf)
        return result
    end

    -- Free text (reason/notes): no control chars, no |-escapes (|c |r |H |T
    -- would render as colors/links in tooltips and Print), bounded length.
    local function cleanText(s, maxChars)
        s = (s or ""):gsub("%c", " "):gsub("|", "/"):gsub("%s+", " ")
        return AIP.TruncateUtf8(trim(s), maxChars)
    end

    -- Player name: optional -Realm suffix dropped; 2+ letters; ASCII must be
    -- A-Z/a-z only (bytes >= 128 are UTF-8 accented letters).
    local function cleanName(s)
        s = trim((s or ""):gsub("%c", ""))
        s = s:match("^([^%-]+)") or s
        if #s < 2 or #s > L.MAX_NAME_BYTES then return nil end
        for i = 1, #s do
            local b = s:byte(i)
            if b < 128 and not ((b >= 65 and b <= 90) or (b >= 97 and b <= 122)) then
                return nil
            end
        end
        return s:sub(1, 1):upper() .. s:sub(2):lower()
    end

    local seen = {}
    for lineNum = 1, #lines do
        if #entries >= L.MAX_ENTRIES then
            addError("Entry limit (" .. L.MAX_ENTRIES .. ") reached; remaining lines ignored")
            break
        end
        local line = trim(lines[lineNum])
        if line ~= "" and not line:match("^#") then  -- Skip empty lines and comments
            if #line > L.MAX_LINE_BYTES then
                addError("Line " .. lineNum .. ": too long, skipped")
            else
                local rawName, reason, source, notes
                if format == "csv" then
                    local fields = parseCSV(line)
                    rawName, reason, source, notes = fields[1], fields[2], fields[3], fields[4]
                elseif format == "full" then
                    -- Name|Reason|Source|Notes|Timestamp (timestamp ignored; import time is used)
                    local parts = {strsplit("|", line, 5)}
                    rawName, reason, source, notes = parts[1], parts[2], parts[3], parts[4]
                else
                    rawName, reason = strsplit(";", line, 2)
                end

                if not rawName or trim(rawName) == "" then
                    addError("Line " .. lineNum .. ": Empty name")
                else
                    local name = cleanName(rawName)
                    if not name then
                        addError("Line " .. lineNum .. ": Invalid player name")
                    else
                        local key = name:lower()
                        if seen[key] then
                            addError("Line " .. lineNum .. ": Duplicate name " .. name)
                        else
                            seen[key] = true
                            reason = cleanText(reason, L.MAX_REASON_CHARS)
                            notes = cleanText(notes, L.MAX_NOTES_CHARS)
                            if format == "simple" then
                                source = "import"
                            else
                                source = ((source or ""):gsub("[^%w_]", "")):sub(1, L.MAX_SOURCE_CHARS):lower()
                            end
                            if reason == "" then reason = "Imported" end
                            if source == "" then source = "import" end
                            entries[#entries + 1] = {
                                name = name,
                                reason = reason,
                                source = source,
                                notes = notes,
                            }
                        end
                    end
                end
            end
        end
    end

    if droppedErrors > 0 then
        errors[#errors + 1] = "(" .. droppedErrors .. " more errors not shown)"
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
-- Peer blacklist sharing (on demand, over the DataBus). Push model: you Share
-- your blacklist to peers; each peer gets a prompt and merges it EXPLICITLY
-- (never silent - it mutates their saved data). Paged to fit the 255-char cap.
-- ============================================================================
local pendingShares = {}   -- sender -> { entries = {{name,reason},...}, ts, total, promptArmed }

-- Broadcast your blacklist to all peers (target=nil) or one peer (target=name).
function AIP.ShareBlacklist(target)
    if not (AIP.DataBus and AIP.DataBus.CreateEvent and AIP.DataBus.Broadcast) then
        AIP.Print("DataBus not available - can't share the blacklist."); return
    end
    local list = {}
    for _, entry in pairs(AIP.db.blacklist or {}) do
        list[#list + 1] = { n = entry.name, r = (entry.reason or ""):gsub("[;|\n\r]", " "):sub(1, 40) }
    end
    if #list == 0 then AIP.Print("Your blacklist is empty - nothing to share."); return end
    local PAGE = 2   -- keeps a page well under DB.EffectiveLimit() (~251) at 40-char reasons
    local total = math.ceil(#list / PAGE)
    local pages = {}
    for i = 1, #list, PAGE do
        local page = {}
        for j = i, math.min(i + PAGE - 1, #list) do page[#page + 1] = list[j] end
        pages[#pages + 1] = page
    end
    local function sendPage(idx)
        local ev = AIP.DataBus.CreateEvent("BLACKLIST", { seq = idx, total = total, entries = pages[idx] })
        if ev then
            local ok, why = AIP.DataBus.Broadcast(ev, target)
            if ok == false then
                AIP.Print(string.format("Blacklist share page %d/%d failed to send (%s).", idx, total, tostring(why or "unknown")))
            end
        end
    end
    sendPage(1)
    -- Stagger remaining pages 5.5s apart: must clear the DataBus CHANNEL rate
    -- limit (5s, DB.Config.channelRateLimit) - not just the 2s per-event-type
    -- gate - or cross-guild peers silently lose pages 2..N (same failure the
    -- CharacterCard pages had at 2.2s).
    for idx = 2, total do
        if AIP.Utils and AIP.Utils.DelayedCall then
            AIP.Utils.DelayedCall(5.5 * (idx - 1), function() sendPage(idx) end)
        else
            sendPage(idx)
        end
    end
    AIP.Print(string.format("Sharing %d blacklist entr%s to %s...", #list, #list == 1 and "y" or "ies", target or "peers"))
end

-- Receive a page: accumulate, then (debounced) prompt the user to accept.
local function onBlacklistShared(event)
    if not (event and event.sender and event.data) then return end
    if event.sender == UnitName("player") then return end
    local buf = pendingShares[event.sender] or { entries = {}, ts = time() }
    pendingShares[event.sender] = buf
    for _, en in ipairs(event.data.entries or {}) do
        if en.n then buf.entries[#buf.entries + 1] = { name = en.n, reason = en.r or "" } end
    end
    buf.ts = time()
    buf.total = event.data.total
    buf.got = (buf.got or 0) + 1
    buf.promptArmed = true
    local function prompt()
        if buf.promptArmed and #buf.entries > 0 then
            buf.promptArmed = false
            buf.got = 0
            AIP.Print(string.format("|cFF33CCFF%s|r offers %d blacklist entr%s. Type |cFFFFD100/aip bl accept %s|r to merge them in.",
                event.sender, #buf.entries, #buf.entries == 1 and "y" or "ies", event.sender))
        end
    end
    -- Prompt as soon as every page has arrived; otherwise fall back to a debounce
    -- longer than the 5.5s page interval so a lost page can't stall the prompt.
    if tonumber(buf.total) and buf.got >= buf.total then
        prompt()
    elseif AIP.Utils and AIP.Utils.DelayedCall then
        AIP.Utils.DelayedCall(7, prompt)
    end
end

-- Merge a received share into your blacklist (explicit, from the prompt or button).
function AIP.AcceptSharedBlacklist(sender)
    local key = sender
    if not key or key == "" then
        local best, bestTs
        for s, b in pairs(pendingShares) do
            if #b.entries > 0 and (not bestTs or b.ts > bestTs) then best, bestTs = s, b.ts end
        end
        key = best
    end
    local buf = key and pendingShares[key]
    if not (buf and #buf.entries > 0) then AIP.Print("No shared blacklist waiting to accept."); return end
    local lines = {}
    for _, en in ipairs(buf.entries) do
        lines[#lines + 1] = en.name .. ";" .. (en.reason ~= "" and en.reason or ("shared by " .. key))
    end
    AIP.ImportBlacklist(table.concat(lines, "\n"), "merge")
    pendingShares[key] = nil
end

function AIP.HasPendingBlacklistShare()
    for _, b in pairs(pendingShares) do if #b.entries > 0 then return true end end
    return false
end

-- Subscribe on login (DataBus loads before this module, but guard anyway).
local blShareFrame = CreateFrame("Frame")
blShareFrame:RegisterEvent("PLAYER_LOGIN")
blShareFrame:SetScript("OnEvent", function()
    if AIP.DataBus and AIP.DataBus.Subscribe then
        AIP.DataBus.Subscribe("BLACKLIST", onBlacklistShared, "Blacklist")
    end
end)

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
    if AIP.UI and AIP.UI.StyleEditBox then AIP.UI.StyleEditBox(searchBox) end
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
    if AIP.UI and AIP.UI.StyleEditBox then AIP.UI.StyleEditBox(inputBox) end

    local reasonBox = CreateFrame("EditBox", "AIPBlacklistReason", frame, "InputBoxTemplate")
    reasonBox:SetSize(120, 20)
    reasonBox:SetPoint("LEFT", inputBox, "RIGHT", 5, 0)
    reasonBox:SetAutoFocus(false)
    if AIP.UI and AIP.UI.StyleEditBox then AIP.UI.StyleEditBox(reasonBox) end

    local reasonPlaceholder = reasonBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    reasonPlaceholder:SetPoint("LEFT", 5, 0)
    reasonPlaceholder:SetText("Reason...")
    reasonPlaceholder:SetTextColor(0.5, 0.5, 0.5)
    reasonBox.placeholder = reasonPlaceholder

    reasonBox:SetScript("OnTextChanged", function(self)
        if self:GetText() == "" then
            self.placeholder:Show()
        else
            self.placeholder:Hide()
        end
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
