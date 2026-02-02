-- AutoInvite Plus - Roster Manager Module
-- Save/load rosters, attendance tracking, player notes, waitlist

local AIP = AutoInvitePlus
AIP.Roster = {}
local Roster = AIP.Roster

-- Default roster data structure (saved in DB)
local defaultRosterDB = {
    savedRosters = {},    -- {name = {players = {}, template = "", created = time}}
    playerNotes = {},     -- {playerName = {note = "", rating = 5, tags = {}}}
    attendance = {},      -- {playerName = {raids = {}, totalRaids = 0, attended = 0}}
    waitlist = {},        -- {name, role, class, time, priority}
}

-- Initialize roster DB
function Roster.InitDB()
    if not AIP.db then return end

    if not AIP.db.rosters then
        AIP.db.rosters = {}
    end

    for k, v in pairs(defaultRosterDB) do
        if AIP.db.rosters[k] == nil then
            AIP.db.rosters[k] = v
        end
    end
end

-- ==========================================
-- ROSTER SAVE/LOAD
-- ==========================================

-- Save current raid roster
function Roster.SaveRoster(name)
    if not name or name:trim() == "" then
        AIP.Print("Please provide a roster name")
        return false
    end

    Roster.InitDB()
    name = name:trim()

    local players = {}
    local numRaid = GetNumRaidMembers()
    local isRaid = numRaid > 0

    if isRaid then
        for i = 1, numRaid do
            local pName, rank, subgroup, level, class, fileName, zone, online = GetRaidRosterInfo(i)
            if pName then
                table.insert(players, {
                    name = pName,
                    class = fileName,
                    group = subgroup,
                    rank = rank,
                })
            end
        end
    else
        -- Party
        local pName = UnitName("player")
        local _, pClass = UnitClass("player")
        table.insert(players, {name = pName, class = pClass, group = 1})

        for i = 1, GetNumPartyMembers() do
            local unit = "party" .. i
            if UnitExists(unit) then
                local name = UnitName(unit)
                local _, class = UnitClass(unit)
                table.insert(players, {name = name, class = class, group = 1})
            end
        end
    end

    if #players == 0 then
        AIP.Print("No players to save")
        return false
    end

    AIP.db.rosters.savedRosters[name] = {
        players = players,
        template = AIP.Composition and AIP.Composition.CurrentRaid.template or nil,
        created = time(),
        count = #players,
    }

    AIP.Print("Saved roster '" .. name .. "' with " .. #players .. " players")
    return true
end

-- Load a saved roster into queue
function Roster.LoadRoster(name)
    Roster.InitDB()

    local roster = AIP.db.rosters.savedRosters[name]
    if not roster then
        AIP.Print("Roster '" .. name .. "' not found")
        return false
    end

    local added = 0
    for _, player in ipairs(roster.players) do
        if player.name ~= UnitName("player") then
            if not UnitInRaid(player.name) and not UnitInParty(player.name) then
                if AIP.AddToQueue then
                    AIP.AddToQueue(player.name, "Roster: " .. name)
                    added = added + 1
                end
            end
        end
    end

    -- Set template if available
    if roster.template and AIP.Composition then
        AIP.Composition.SetTemplate(roster.template)
    end

    AIP.Print("Loaded roster '" .. name .. "': " .. added .. " players added to queue")
    return true
end

-- Delete a saved roster
function Roster.DeleteRoster(name)
    Roster.InitDB()

    if AIP.db.rosters.savedRosters[name] then
        AIP.db.rosters.savedRosters[name] = nil
        AIP.Print("Deleted roster: " .. name)
        return true
    end

    AIP.Print("Roster '" .. name .. "' not found")
    return false
end

-- Get list of saved rosters
function Roster.GetSavedRosters()
    Roster.InitDB()
    local list = {}
    if not AIP.db.rosters or not AIP.db.rosters.savedRosters then return list end

    for name, data in pairs(AIP.db.rosters.savedRosters) do
        table.insert(list, {
            name = name,
            count = data.count,
            template = data.template,
            created = data.created,
        })
    end

    table.sort(list, function(a, b) return a.created > b.created end)
    return list
end

-- ==========================================
-- PLAYER NOTES
-- ==========================================

-- Set note for a player
function Roster.SetPlayerNote(playerName, note)
    Roster.InitDB()

    if not AIP.db.rosters.playerNotes[playerName] then
        AIP.db.rosters.playerNotes[playerName] = {note = "", rating = 5, tags = {}}
    end

    AIP.db.rosters.playerNotes[playerName].note = note or ""
    AIP.Print("Note saved for " .. playerName)
end

-- Get player note
function Roster.GetPlayerNote(playerName)
    Roster.InitDB()
    local data = AIP.db.rosters.playerNotes[playerName]
    return data and data.note or ""
end

-- Set player rating (1-5)
function Roster.SetPlayerRating(playerName, rating)
    Roster.InitDB()
    rating = math.max(1, math.min(5, tonumber(rating) or 5))

    if not AIP.db.rosters.playerNotes[playerName] then
        AIP.db.rosters.playerNotes[playerName] = {note = "", rating = 5, tags = {}}
    end

    AIP.db.rosters.playerNotes[playerName].rating = rating
    AIP.Print("Rating for " .. playerName .. ": " .. rating .. "/5")
end

-- Get player rating
function Roster.GetPlayerRating(playerName)
    Roster.InitDB()
    local data = AIP.db.rosters.playerNotes[playerName]
    return data and data.rating or 5
end

-- Add tag to player
function Roster.AddPlayerTag(playerName, tag)
    Roster.InitDB()

    if not AIP.db.rosters.playerNotes[playerName] then
        AIP.db.rosters.playerNotes[playerName] = {note = "", rating = 5, tags = {}}
    end

    local tags = AIP.db.rosters.playerNotes[playerName].tags
    for _, t in ipairs(tags) do
        if t == tag then
            return -- Already has tag
        end
    end

    table.insert(tags, tag)
    AIP.Print("Added tag '" .. tag .. "' to " .. playerName)
end

-- Remove tag from player
function Roster.RemovePlayerTag(playerName, tag)
    Roster.InitDB()

    local data = AIP.db.rosters.playerNotes[playerName]
    if not data then return end

    for i, t in ipairs(data.tags) do
        if t == tag then
            table.remove(data.tags, i)
            AIP.Print("Removed tag '" .. tag .. "' from " .. playerName)
            return
        end
    end
end

-- Get player tags
function Roster.GetPlayerTags(playerName)
    Roster.InitDB()
    local data = AIP.db.rosters.playerNotes[playerName]
    return data and data.tags or {}
end

-- Common tags
Roster.CommonTags = {
    "Reliable", "Unreliable", "Good DPS", "Good Healer", "Good Tank",
    "Often Late", "Drama", "Friend", "Alt of Main", "New Player",
    "Experienced", "Knows Fights", "Needs Gear", "Well Geared",
}

-- ==========================================
-- ATTENDANCE TRACKING
-- ==========================================

-- Record attendance for current raid
function Roster.RecordAttendance(raidName)
    Roster.InitDB()
    raidName = raidName or "Unknown Raid"

    local numRaid = GetNumRaidMembers()
    if numRaid == 0 then
        AIP.Print("Not in a raid")
        return false
    end

    local timestamp = time()
    local recorded = 0

    for i = 1, numRaid do
        local pName = GetRaidRosterInfo(i)
        if pName then
            if not AIP.db.rosters.attendance[pName] then
                AIP.db.rosters.attendance[pName] = {raids = {}, totalRaids = 0, attended = 0}
            end

            local att = AIP.db.rosters.attendance[pName]
            table.insert(att.raids, {
                name = raidName,
                time = timestamp,
                present = true,
            })
            att.totalRaids = att.totalRaids + 1
            att.attended = att.attended + 1
            recorded = recorded + 1
        end
    end

    AIP.Print("Recorded attendance for " .. recorded .. " players in " .. raidName)
    return true
end

-- Get attendance percentage for a player
function Roster.GetAttendancePercent(playerName)
    Roster.InitDB()
    local data = AIP.db.rosters.attendance[playerName]
    if not data or data.totalRaids == 0 then
        return nil
    end
    return math.floor((data.attended / data.totalRaids) * 100)
end

-- Get attendance stats for a player
function Roster.GetAttendanceStats(playerName)
    Roster.InitDB()
    return AIP.db.rosters.attendance[playerName]
end

-- ==========================================
-- WAITLIST
-- ==========================================

-- Add to waitlist
function Roster.AddToWaitlist(name, role, priority)
    Roster.InitDB()

    -- Check if already on waitlist
    for i, entry in ipairs(AIP.db.rosters.waitlist) do
        if entry.name:lower() == name:lower() then
            AIP.Print(name .. " is already on the waitlist")
            return false
        end
    end

    table.insert(AIP.db.rosters.waitlist, {
        name = name,
        role = role or "DPS",
        time = time(),
        priority = priority or 1,
    })

    AIP.Print("Added " .. name .. " to waitlist (priority " .. (priority or 1) .. ")")

    if AIP.UpdateWaitlistUI then
        AIP.UpdateWaitlistUI()
    end

    return true
end

-- Remove from waitlist
function Roster.RemoveFromWaitlist(name)
    Roster.InitDB()

    for i, entry in ipairs(AIP.db.rosters.waitlist) do
        if entry.name:lower() == name:lower() then
            table.remove(AIP.db.rosters.waitlist, i)
            AIP.Print("Removed " .. name .. " from waitlist")
            if AIP.UpdateWaitlistUI then
                AIP.UpdateWaitlistUI()
            end
            return true
        end
    end

    return false
end

-- Get waitlist sorted by priority then time
function Roster.GetWaitlist()
    Roster.InitDB()

    local list = {}
    for _, entry in ipairs(AIP.db.rosters.waitlist) do
        table.insert(list, entry)
    end

    table.sort(list, function(a, b)
        if a.priority ~= b.priority then
            return a.priority < b.priority  -- Lower priority number = higher priority
        end
        return a.time < b.time  -- Earlier time first
    end)

    return list
end

-- Clear waitlist
function Roster.ClearWaitlist()
    Roster.InitDB()
    AIP.db.rosters.waitlist = {}
    AIP.Print("Waitlist cleared")
    if AIP.UpdateWaitlistUI then
        AIP.UpdateWaitlistUI()
    end
end

-- Invite next from waitlist
function Roster.InviteFromWaitlist(role)
    local list = Roster.GetWaitlist()

    for _, entry in ipairs(list) do
        if not role or entry.role == role then
            if AIP.InvitePlayer(entry.name) then
                Roster.RemoveFromWaitlist(entry.name)
                return entry.name
            end
        end
    end

    AIP.Print("No suitable players on waitlist")
    return nil
end

-- ==========================================
-- UI
-- ==========================================

local rosterFrame = nil

function Roster.CreateUI()
    if rosterFrame then return rosterFrame end

    local frame = CreateFrame("Frame", "AIPRosterFrame", UIParent)
    frame:SetSize(500, 450)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()

    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Roster Manager")

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Tabs (custom buttons for WotLK compatibility)
    local tabs = {"Saved Rosters", "Waitlist", "Player Notes"}
    local tabFrames = {}
    local tabButtons = {}
    local currentTab = 1

    for i, tabName in ipairs(tabs) do
        local tab = CreateFrame("Button", "AIPRosterTab"..i, frame)
        tab:SetSize(110, 24)
        tab:SetID(i)
        tab:SetPoint("TOPLEFT", 15 + (i-1)*115, -35)

        -- Tab background
        local tabBg = tab:CreateTexture(nil, "BACKGROUND")
        tabBg:SetAllPoints()
        if i == 1 then
            tabBg:SetTexture(0.25, 0.25, 0.35, 1)
        else
            tabBg:SetTexture(0.15, 0.15, 0.15, 0.9)
        end
        tab.bg = tabBg

        -- Tab border
        local tabBorder = tab:CreateTexture(nil, "BORDER")
        tabBorder:SetPoint("TOPLEFT", -1, 1)
        tabBorder:SetPoint("BOTTOMRIGHT", 1, -1)
        tabBorder:SetTexture(0.4, 0.4, 0.4, 1)

        -- Tab text
        local tabText = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tabText:SetPoint("CENTER", 0, 0)
        tabText:SetText(tabName)
        if i == 1 then
            tabText:SetTextColor(1, 0.82, 0)
        else
            tabText:SetTextColor(0.8, 0.8, 0.8)
        end
        tab.text = tabText

        -- Highlight
        local highlight = tab:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture(1, 1, 1, 0.15)

        tab:SetScript("OnClick", function(self)
            currentTab = self:GetID()
            for j, tf in ipairs(tabFrames) do
                local btn = tabButtons[j]
                if j == currentTab then
                    tf:Show()
                    if btn and btn.bg then btn.bg:SetTexture(0.25, 0.25, 0.35, 1) end
                    if btn and btn.text then btn.text:SetTextColor(1, 0.82, 0) end
                else
                    tf:Hide()
                    if btn and btn.bg then btn.bg:SetTexture(0.15, 0.15, 0.15, 0.9) end
                    if btn and btn.text then btn.text:SetTextColor(0.8, 0.8, 0.8) end
                end
            end
        end)

        tabButtons[i] = tab
    end

    -- Tab content frames
    for i = 1, 3 do
        local content = CreateFrame("Frame", "AIPRosterContent"..i, frame)
        content:SetSize(460, 350)
        content:SetPoint("TOPLEFT", 20, -70)
        if i > 1 then content:Hide() end
        tabFrames[i] = content
    end

    -- ===== Tab 1: Saved Rosters =====
    local tab1 = tabFrames[1]

    local saveNameLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    saveNameLabel:SetPoint("TOPLEFT", 0, 0)
    saveNameLabel:SetText("Roster Name:")

    local saveNameInput = CreateFrame("EditBox", "AIPRosterSaveName", tab1, "InputBoxTemplate")
    saveNameInput:SetSize(150, 20)
    saveNameInput:SetPoint("LEFT", saveNameLabel, "RIGHT", 10, 0)
    saveNameInput:SetAutoFocus(false)

    local saveBtn = CreateFrame("Button", nil, tab1, "UIPanelButtonTemplate")
    saveBtn:SetSize(100, 22)
    saveBtn:SetPoint("LEFT", saveNameInput, "RIGHT", 10, 0)
    saveBtn:SetText("Save Current")
    saveBtn:SetScript("OnClick", function()
        Roster.SaveRoster(saveNameInput:GetText())
        saveNameInput:SetText("")
        Roster.UpdateRosterList()
    end)

    -- Roster list scroll frame
    local rosterListLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rosterListLabel:SetPoint("TOPLEFT", 0, -40)
    rosterListLabel:SetText("Saved Rosters:")
    rosterListLabel:SetTextColor(1, 0.82, 0)

    local rosterScrollFrame = CreateFrame("ScrollFrame", "AIPRosterScrollFrame", tab1, "FauxScrollFrameTemplate")
    rosterScrollFrame:SetSize(420, 200)
    rosterScrollFrame:SetPoint("TOPLEFT", 0, -60)
    rosterScrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, 25, Roster.UpdateRosterList)
    end)

    -- Roster list buttons
    Roster.rosterButtons = {}
    for i = 1, 8 do
        local row = CreateFrame("Frame", "AIPRosterRow"..i, tab1)
        row:SetSize(420, 25)
        row:SetPoint("TOPLEFT", rosterScrollFrame, "TOPLEFT", 0, -((i-1) * 25))

        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", 5, 0)
        nameText:SetWidth(150)
        nameText:SetJustifyH("LEFT")
        row.nameText = nameText

        local infoText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        infoText:SetPoint("LEFT", 160, 0)
        infoText:SetWidth(100)
        infoText:SetJustifyH("LEFT")
        infoText:SetTextColor(0.7, 0.7, 0.7)
        row.infoText = infoText

        local loadBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        loadBtn:SetSize(50, 20)
        loadBtn:SetPoint("LEFT", 270, 0)
        loadBtn:SetText("Load")
        row.loadBtn = loadBtn

        local delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        delBtn:SetSize(50, 20)
        delBtn:SetPoint("LEFT", 325, 0)
        delBtn:SetText("Delete")
        row.delBtn = delBtn

        row:Hide()
        Roster.rosterButtons[i] = row
    end

    -- ===== Tab 2: Waitlist =====
    local tab2 = tabFrames[2]

    local waitAddLabel = tab2:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    waitAddLabel:SetPoint("TOPLEFT", 0, 0)
    waitAddLabel:SetText("Add to Waitlist:")

    local waitNameInput = CreateFrame("EditBox", "AIPWaitlistName", tab2, "InputBoxTemplate")
    waitNameInput:SetSize(100, 20)
    waitNameInput:SetPoint("LEFT", waitAddLabel, "RIGHT", 10, 0)
    waitNameInput:SetAutoFocus(false)

    local waitAddBtn = CreateFrame("Button", nil, tab2, "UIPanelButtonTemplate")
    waitAddBtn:SetSize(50, 22)
    waitAddBtn:SetPoint("LEFT", waitNameInput, "RIGHT", 10, 0)
    waitAddBtn:SetText("Add")
    waitAddBtn:SetScript("OnClick", function()
        Roster.AddToWaitlist(waitNameInput:GetText())
        waitNameInput:SetText("")
    end)

    local waitClearBtn = CreateFrame("Button", nil, tab2, "UIPanelButtonTemplate")
    waitClearBtn:SetSize(70, 22)
    waitClearBtn:SetPoint("LEFT", waitAddBtn, "RIGHT", 10, 0)
    waitClearBtn:SetText("Clear All")
    waitClearBtn:SetScript("OnClick", Roster.ClearWaitlist)

    -- Waitlist display
    local waitListLabel = tab2:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    waitListLabel:SetPoint("TOPLEFT", 0, -40)
    waitListLabel:SetText("Current Waitlist:")
    waitListLabel:SetTextColor(1, 0.82, 0)

    Roster.waitlistButtons = {}
    for i = 1, 10 do
        local row = CreateFrame("Frame", "AIPWaitlistRow"..i, tab2)
        row:SetSize(420, 22)
        row:SetPoint("TOPLEFT", 0, -60 - ((i-1) * 22))

        local numText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        numText:SetPoint("LEFT", 0, 0)
        numText:SetWidth(20)
        numText:SetText(i .. ".")
        row.numText = numText

        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", 25, 0)
        nameText:SetWidth(120)
        nameText:SetJustifyH("LEFT")
        row.nameText = nameText

        local roleText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        roleText:SetPoint("LEFT", 150, 0)
        roleText:SetWidth(50)
        row.roleText = roleText

        local invBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        invBtn:SetSize(50, 18)
        invBtn:SetPoint("LEFT", 210, 0)
        invBtn:SetText("Invite")
        row.invBtn = invBtn

        local remBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        remBtn:SetSize(20, 18)
        remBtn:SetPoint("LEFT", 265, 0)
        remBtn:SetText("X")
        row.remBtn = remBtn

        row:Hide()
        Roster.waitlistButtons[i] = row
    end

    -- ===== Tab 3: Player Notes =====
    local tab3 = tabFrames[3]

    local notesLabel = tab3:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    notesLabel:SetPoint("TOPLEFT", 0, 0)
    notesLabel:SetText("Player Name:")

    local notesNameInput = CreateFrame("EditBox", "AIPNotesName", tab3, "InputBoxTemplate")
    notesNameInput:SetSize(120, 20)
    notesNameInput:SetPoint("LEFT", notesLabel, "RIGHT", 10, 0)
    notesNameInput:SetAutoFocus(false)

    local notesSearchBtn = CreateFrame("Button", nil, tab3, "UIPanelButtonTemplate")
    notesSearchBtn:SetSize(60, 22)
    notesSearchBtn:SetPoint("LEFT", notesNameInput, "RIGHT", 10, 0)
    notesSearchBtn:SetText("Search")

    local noteLabel = tab3:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    noteLabel:SetPoint("TOPLEFT", 0, -40)
    noteLabel:SetText("Note:")

    local noteInput = CreateFrame("EditBox", "AIPNotesNote", tab3, "InputBoxTemplate")
    noteInput:SetSize(350, 20)
    noteInput:SetPoint("LEFT", noteLabel, "RIGHT", 10, 0)
    noteInput:SetAutoFocus(false)

    local noteSaveBtn = CreateFrame("Button", nil, tab3, "UIPanelButtonTemplate")
    noteSaveBtn:SetSize(50, 22)
    noteSaveBtn:SetPoint("LEFT", noteInput, "RIGHT", 10, 0)
    noteSaveBtn:SetText("Save")
    noteSaveBtn:SetScript("OnClick", function()
        local name = notesNameInput:GetText()
        local note = noteInput:GetText()
        if name ~= "" then
            Roster.SetPlayerNote(name, note)
        end
    end)

    notesSearchBtn:SetScript("OnClick", function()
        local name = notesNameInput:GetText()
        if name ~= "" then
            noteInput:SetText(Roster.GetPlayerNote(name))
        end
    end)

    -- Rating
    local ratingLabel = tab3:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ratingLabel:SetPoint("TOPLEFT", 0, -80)
    ratingLabel:SetText("Rating (1-5):")

    for i = 1, 5 do
        local starBtn = CreateFrame("Button", "AIPNotesRating"..i, tab3)
        starBtn:SetSize(20, 20)
        starBtn:SetPoint("TOPLEFT", 80 + (i-1)*22, -77)
        starBtn:SetNormalTexture("Interface\\RAIDFRAME\\ReadyCheck-Waiting")
        starBtn:SetScript("OnClick", function()
            local name = notesNameInput:GetText()
            if name ~= "" then
                Roster.SetPlayerRating(name, i)
                Roster.UpdateNotesDisplay(name)
            end
        end)
    end

    -- Attendance display
    local attLabel = tab3:CreateFontString("AIPNotesAttendance", "OVERLAY", "GameFontNormal")
    attLabel:SetPoint("TOPLEFT", 0, -120)
    attLabel:SetText("Attendance: N/A")

    -- Tags display
    local tagsLabel = tab3:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tagsLabel:SetPoint("TOPLEFT", 0, -150)
    tagsLabel:SetText("Tags:")
    tagsLabel:SetTextColor(1, 0.82, 0)

    local tagsDisplay = tab3:CreateFontString("AIPNotesTags", "OVERLAY", "GameFontNormalSmall")
    tagsDisplay:SetPoint("TOPLEFT", 0, -170)
    tagsDisplay:SetWidth(400)
    tagsDisplay:SetJustifyH("LEFT")

    tinsert(UISpecialFrames, frame:GetName())
    rosterFrame = frame

    -- First tab is already selected by default (set in creation)
    return frame
end

-- Update roster list display
function Roster.UpdateRosterList()
    if not rosterFrame or not rosterFrame:IsVisible() then return end

    local rosters = Roster.GetSavedRosters()
    local numRosters = #rosters

    FauxScrollFrame_Update(_G["AIPRosterScrollFrame"], numRosters, 8, 25)
    local offset = FauxScrollFrame_GetOffset(_G["AIPRosterScrollFrame"])

    for i = 1, 8 do
        local index = offset + i
        local row = Roster.rosterButtons[i]

        if index <= numRosters then
            local data = rosters[index]
            row.nameText:SetText(data.name)
            row.infoText:SetText(data.count .. " players")

            row.loadBtn:SetScript("OnClick", function()
                Roster.LoadRoster(data.name)
            end)

            row.delBtn:SetScript("OnClick", function()
                StaticPopupDialogs["AIP_DELETE_ROSTER"] = {
                    text = "Delete roster '" .. data.name .. "'?",
                    button1 = "Yes",
                    button2 = "No",
                    OnAccept = function()
                        Roster.DeleteRoster(data.name)
                        Roster.UpdateRosterList()
                    end,
                    timeout = 0,
                    whileDead = true,
                    hideOnEscape = true,
                }
                StaticPopup_Show("AIP_DELETE_ROSTER")
            end)

            row:Show()
        else
            row:Hide()
        end
    end
end

-- Update waitlist display (local to Roster module)
function Roster.UpdateWaitlistUI()
    if not rosterFrame or not rosterFrame:IsVisible() then return end

    local list = Roster.GetWaitlist()

    for i = 1, 10 do
        local row = Roster.waitlistButtons[i]
        if i <= #list then
            local entry = list[i]
            row.nameText:SetText(entry.name)
            row.roleText:SetText(entry.role or "")

            row.invBtn:SetScript("OnClick", function()
                AIP.InvitePlayer(entry.name)
                Roster.RemoveFromWaitlist(entry.name)
            end)

            row.remBtn:SetScript("OnClick", function()
                Roster.RemoveFromWaitlist(entry.name)
            end)

            row:Show()
        else
            row:Hide()
        end
    end
end

-- Update notes display for a player
function Roster.UpdateNotesDisplay(name)
    if not rosterFrame then return end

    local rating = Roster.GetPlayerRating(name)
    for i = 1, 5 do
        local star = _G["AIPNotesRating"..i]
        if star then
            if i <= rating then
                star:SetNormalTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")
            else
                star:SetNormalTexture("Interface\\RAIDFRAME\\ReadyCheck-Waiting")
            end
        end
    end

    local attPercent = Roster.GetAttendancePercent(name)
    local attText = attPercent and (attPercent .. "%") or "N/A"
    _G["AIPNotesAttendance"]:SetText("Attendance: " .. attText)

    local tags = Roster.GetPlayerTags(name)
    _G["AIPNotesTags"]:SetText(#tags > 0 and table.concat(tags, ", ") or "No tags")
end

-- Toggle roster UI
function AIP.ToggleRosterUI()
    local frame = Roster.CreateUI()

    if frame:IsVisible() then
        frame:Hide()
    else
        frame:Show()
        Roster.UpdateRosterList()
        Roster.UpdateWaitlistUI()
    end
end

-- Slash command handler
function Roster.SlashHandler(msg)
    msg = (msg or ""):lower():trim()

    if msg == "" or msg == "show" then
        AIP.ToggleRosterUI()
    elseif msg:find("^save ") then
        Roster.SaveRoster(msg:sub(6))
    elseif msg:find("^load ") then
        Roster.LoadRoster(msg:sub(6))
    elseif msg:find("^delete ") then
        Roster.DeleteRoster(msg:sub(8))
    elseif msg == "list" then
        local rosters = Roster.GetSavedRosters()
        AIP.Print("Saved rosters:")
        for _, r in ipairs(rosters) do
            AIP.Print("  " .. r.name .. " (" .. r.count .. " players)")
        end
    elseif msg:find("^waitlist ") then
        local subcmd = msg:sub(10)
        if subcmd == "clear" then
            Roster.ClearWaitlist()
        elseif subcmd:find("^add ") then
            Roster.AddToWaitlist(subcmd:sub(5))
        elseif subcmd:find("^remove ") then
            Roster.RemoveFromWaitlist(subcmd:sub(8))
        elseif subcmd == "invite" then
            Roster.InviteFromWaitlist()
        end
    elseif msg == "attendance" then
        Roster.RecordAttendance("Manual Record")
    else
        AIP.Print("Roster commands:")
        AIP.Print("  /aip roster - Show roster manager")
        AIP.Print("  /aip roster save <name> - Save current raid")
        AIP.Print("  /aip roster load <name> - Load roster to queue")
        AIP.Print("  /aip roster list - List saved rosters")
        AIP.Print("  /aip roster waitlist add/remove/invite/clear")
    end
end
