-- AutoInvite Plus - Message Composer Module (v4.1)
-- LFM message generation with templates

local AIP = AutoInvitePlus
AIP.MessageComposer = {}
local MC = AIP.MessageComposer

-- ============================================================================
-- LFM MESSAGE PROTOCOL
-- ============================================================================
-- Format: LFM <RAID> [T:<cur>/<need> H:<cur>/<need> D:<cur>/<need>] <GS>k+ {AIP:<ver>}
-- Example: LFM ICC25HC [T:1/2 H:3/6 D:10/17] 5.8k+ {AIP:4.1}
-- ============================================================================

-- Version for protocol
MC.Version = "5.1"

-- Default templates for common raids
MC.DefaultTemplates = {
    ["ICC10"] = {
        name = "ICC 10 Normal",
        raid = "ICC10",
        tanks = {current = 0, needed = 2},
        healers = {current = 0, needed = 2},
        dps = {current = 0, needed = 6},
        gsMin = 5000,
        ilvlMin = 232,
        includeAddonLink = true,
        includeAchievements = false,
        customNote = "",
    },
    ["ICC10HC"] = {
        name = "ICC 10 Heroic",
        raid = "ICC10HC",
        tanks = {current = 0, needed = 2},
        healers = {current = 0, needed = 3},
        dps = {current = 0, needed = 5},
        gsMin = 5800,
        ilvlMin = 264,
        includeAddonLink = true,
        includeAchievements = true,
        customNote = "",
    },
    ["ICC25"] = {
        name = "ICC 25 Normal",
        raid = "ICC25",
        tanks = {current = 0, needed = 3},
        healers = {current = 0, needed = 6},
        dps = {current = 0, needed = 16},
        gsMin = 5200,
        ilvlMin = 245,
        includeAddonLink = true,
        includeAchievements = false,
        customNote = "",
    },
    ["ICC25HC"] = {
        name = "ICC 25 Heroic",
        raid = "ICC25HC",
        tanks = {current = 0, needed = 3},
        healers = {current = 0, needed = 7},
        dps = {current = 0, needed = 15},
        gsMin = 6000,
        ilvlMin = 264,
        includeAddonLink = true,
        includeAchievements = true,
        customNote = "",
    },
    ["TOC10"] = {
        name = "TOC 10",
        raid = "TOC10",
        tanks = {current = 0, needed = 2},
        healers = {current = 0, needed = 2},
        dps = {current = 0, needed = 6},
        gsMin = 4500,
        ilvlMin = 219,
        includeAddonLink = true,
        includeAchievements = false,
        customNote = "",
    },
    ["TOC25"] = {
        name = "TOC 25",
        raid = "TOC25",
        tanks = {current = 0, needed = 2},
        healers = {current = 0, needed = 5},
        dps = {current = 0, needed = 18},
        gsMin = 4800,
        ilvlMin = 232,
        includeAddonLink = true,
        includeAchievements = false,
        customNote = "",
    },
    ["VOA10"] = {
        name = "VOA 10",
        raid = "VOA10",
        tanks = {current = 0, needed = 2},
        healers = {current = 0, needed = 2},
        dps = {current = 0, needed = 6},
        gsMin = 4000,
        ilvlMin = 200,
        includeAddonLink = true,
        includeAchievements = false,
        customNote = "",
    },
    ["VOA25"] = {
        name = "VOA 25",
        raid = "VOA25",
        tanks = {current = 0, needed = 2},
        healers = {current = 0, needed = 5},
        dps = {current = 0, needed = 18},
        gsMin = 4500,
        ilvlMin = 213,
        includeAddonLink = true,
        includeAchievements = false,
        customNote = "",
    },
    ["RS10"] = {
        name = "RS 10",
        raid = "RS10",
        tanks = {current = 0, needed = 2},
        healers = {current = 0, needed = 2},
        dps = {current = 0, needed = 6},
        gsMin = 5500,
        ilvlMin = 251,
        includeAddonLink = true,
        includeAchievements = false,
        customNote = "",
    },
    ["RS25"] = {
        name = "RS 25",
        raid = "RS25",
        tanks = {current = 0, needed = 3},
        healers = {current = 0, needed = 6},
        dps = {current = 0, needed = 16},
        gsMin = 5800,
        ilvlMin = 264,
        includeAddonLink = true,
        includeAchievements = false,
        customNote = "",
    },
    ["ULDUAR10"] = {
        name = "Ulduar 10",
        raid = "ULD10",
        tanks = {current = 0, needed = 2},
        healers = {current = 0, needed = 2},
        dps = {current = 0, needed = 6},
        gsMin = 4000,
        ilvlMin = 200,
        includeAddonLink = true,
        includeAchievements = false,
        customNote = "",
    },
    ["ULDUAR25"] = {
        name = "Ulduar 25",
        raid = "ULD25",
        tanks = {current = 0, needed = 3},
        healers = {current = 0, needed = 6},
        dps = {current = 0, needed = 16},
        gsMin = 4500,
        ilvlMin = 213,
        includeAddonLink = true,
        includeAchievements = false,
        customNote = "",
    },
    ["NAXX10"] = {
        name = "Naxx 10",
        raid = "NAXX10",
        tanks = {current = 0, needed = 2},
        healers = {current = 0, needed = 2},
        dps = {current = 0, needed = 6},
        gsMin = 3500,
        ilvlMin = 187,
        includeAddonLink = true,
        includeAchievements = false,
        customNote = "",
    },
    ["NAXX25"] = {
        name = "Naxx 25",
        raid = "NAXX25",
        tanks = {current = 0, needed = 3},
        healers = {current = 0, needed = 6},
        dps = {current = 0, needed = 16},
        gsMin = 4000,
        ilvlMin = 200,
        includeAddonLink = true,
        includeAchievements = false,
        customNote = "",
    },
    ["ONYXIA10"] = {
        name = "Onyxia 10",
        raid = "ONY10",
        tanks = {current = 0, needed = 1},
        healers = {current = 0, needed = 2},
        dps = {current = 0, needed = 7},
        gsMin = 4000,
        ilvlMin = 200,
        includeAddonLink = true,
        includeAchievements = false,
        customNote = "",
    },
    ["ONYXIA25"] = {
        name = "Onyxia 25",
        raid = "ONY25",
        tanks = {current = 0, needed = 2},
        healers = {current = 0, needed = 5},
        dps = {current = 0, needed = 18},
        gsMin = 4500,
        ilvlMin = 213,
        includeAddonLink = true,
        includeAchievements = false,
        customNote = "",
    },
    ["WEEKLY"] = {
        name = "Weekly Raid",
        raid = "WEEKLY",
        tanks = {current = 0, needed = 2},
        healers = {current = 0, needed = 2},
        dps = {current = 0, needed = 6},
        gsMin = 4000,
        ilvlMin = 200,
        includeAddonLink = true,
        includeAchievements = false,
        customNote = "",
    },
}

-- Current editing template
MC.CurrentTemplate = nil

-- ============================================================================
-- MESSAGE GENERATION
-- ============================================================================

-- Format GearScore for display (e.g., 5800 -> "5.8k")
function MC.FormatGS(gs)
    if not gs or gs < 1000 then return tostring(gs or 0) end
    return string.format("%.1fk", gs / 1000):gsub("%.0k", "k")
end

-- Generate LFM message from template
function MC.GenerateMessage(template)
    if not template then
        template = MC.CurrentTemplate or MC.DefaultTemplates["ICC25HC"]
    end

    local parts = {}

    -- Raid name
    table.insert(parts, "LFM " .. template.raid)

    -- Composition if any slots still needed
    local tankNeed = (template.tanks.needed or 0) - (template.tanks.current or 0)
    local healNeed = (template.healers.needed or 0) - (template.healers.current or 0)
    local dpsNeed = (template.dps.needed or 0) - (template.dps.current or 0)

    if tankNeed > 0 or healNeed > 0 or dpsNeed > 0 then
        local comp = {}
        if tankNeed > 0 then
            table.insert(comp, tankNeed .. "T")
        end
        if healNeed > 0 then
            table.insert(comp, healNeed .. "H")
        end
        if dpsNeed > 0 then
            table.insert(comp, dpsNeed .. "D")
        end
        table.insert(parts, table.concat(comp, " "))
    end

    -- GS requirement
    if template.gsMin and template.gsMin > 0 then
        table.insert(parts, MC.FormatGS(template.gsMin) .. "+")
    end

    -- Custom note
    if template.customNote and template.customNote ~= "" then
        table.insert(parts, template.customNote)
    end

    -- Addon link
    if template.includeAddonLink then
        table.insert(parts, "{AIP:" .. MC.Version .. "}")
    end

    return table.concat(parts, " ")
end

-- Generate detailed LFM message (longer format)
function MC.GenerateDetailedMessage(template)
    if not template then
        template = MC.CurrentTemplate or MC.DefaultTemplates["ICC25HC"]
    end

    local parts = {}

    -- Raid name
    table.insert(parts, "LFM " .. template.raid)

    -- Full composition breakdown
    local tankCur = template.tanks.current or 0
    local tankNeed = template.tanks.needed or 0
    local healCur = template.healers.current or 0
    local healNeed = template.healers.needed or 0
    local dpsCur = template.dps.current or 0
    local dpsNeed = template.dps.needed or 0

    table.insert(parts, string.format("[T:%d/%d H:%d/%d D:%d/%d]",
        tankCur, tankNeed, healCur, healNeed, dpsCur, dpsNeed))

    -- GS requirement
    if template.gsMin and template.gsMin > 0 then
        table.insert(parts, MC.FormatGS(template.gsMin) .. "+")
    end

    -- Custom note
    if template.customNote and template.customNote ~= "" then
        table.insert(parts, template.customNote)
    end

    -- Addon link
    if template.includeAddonLink then
        table.insert(parts, "{AIP:" .. MC.Version .. "}")
    end

    return table.concat(parts, " ")
end

-- ============================================================================
-- MESSAGE PARSING
-- ============================================================================

-- Parse AIP-formatted LFM message
function MC.ParseMessage(message)
    if not message then return nil end

    -- Full format: LFM <RAID> [T:<cur>/<need> H:<cur>/<need> D:<cur>/<need>] <GS>k+ {AIP:<ver>}
    local pattern = "LFM%s+(%S+)%s+%[T:(%d+)/(%d+)%s+H:(%d+)/(%d+)%s+D:(%d+)/(%d+)%]%s*([%d%.]+)k?%+?%s*{AIP:([%d%.]+)}"
    local raid, tankCur, tankNeed, healCur, healNeed, dpsCur, dpsNeed, gs, version = message:match(pattern)

    if raid then
        local gsNum = tonumber(gs)
        return {
            raid = raid,
            tanks = {current = tonumber(tankCur), needed = tonumber(tankNeed)},
            healers = {current = tonumber(healCur), needed = tonumber(healNeed)},
            dps = {current = tonumber(dpsCur), needed = tonumber(dpsNeed)},
            gsMin = gsNum and (gsNum * 1000) or 0,
            version = version,
            isAIPFormat = true,
        }
    end

    -- Simple format: LFM <RAID> <slots>T <slots>H <slots>D <GS>k+
    local simplePattern = "LFM%s+(%S+)%s+(%d+)T%s+(%d+)H%s+(%d+)D%s*([%d%.]+)k?%+?"
    raid, tankNeed, healNeed, dpsNeed, gs = message:match(simplePattern)

    if raid then
        local gsNum = tonumber(gs)
        return {
            raid = raid,
            tanks = {current = 0, needed = tonumber(tankNeed)},
            healers = {current = 0, needed = tonumber(healNeed)},
            dps = {current = 0, needed = tonumber(dpsNeed)},
            gsMin = gsNum and (gsNum * 1000) or 0,
            isAIPFormat = false,
        }
    end

    -- Basic format: LFM <RAID> <GS>+
    local basicPattern = "LFM%s+(%S+).-([%d%.]+)k?%+?"
    raid, gs = message:match(basicPattern)

    if raid then
        return {
            raid = raid,
            tanks = {current = 0, needed = 0},
            healers = {current = 0, needed = 0},
            dps = {current = 0, needed = 0},
            gsMin = tonumber(gs) and tonumber(gs) * 1000 or 0,
            isAIPFormat = false,
        }
    end

    return nil
end

-- ============================================================================
-- TEMPLATE MANAGEMENT
-- ============================================================================

-- Initialize templates database
local function EnsureTemplatesDB()
    if not AIP.db then return false end
    if not AIP.db.lfmTemplates then
        AIP.db.lfmTemplates = {}
    end
    return true
end

-- Get template by name (checks custom first, then defaults)
function MC.GetTemplate(name)
    if not name then return nil end

    -- Check custom templates first
    if AIP.db and AIP.db.lfmTemplates and AIP.db.lfmTemplates[name] then
        return AIP.db.lfmTemplates[name]
    end

    -- Fall back to defaults
    return MC.DefaultTemplates[name]
end

-- Get all available templates
function MC.GetAllTemplates()
    local templates = {}

    -- Add defaults
    for name, template in pairs(MC.DefaultTemplates) do
        templates[name] = {
            name = template.name,
            raid = template.raid,
            isCustom = false,
        }
    end

    -- Add/override with custom
    if AIP.db and AIP.db.lfmTemplates then
        for name, template in pairs(AIP.db.lfmTemplates) do
            templates[name] = {
                name = template.name,
                raid = template.raid,
                isCustom = true,
            }
        end
    end

    return templates
end

-- Save custom template
function MC.SaveTemplate(name, template)
    if not EnsureTemplatesDB() then return false end
    if not name or not template then return false end

    AIP.db.lfmTemplates[name] = {
        name = template.name or name,
        raid = template.raid,
        tanks = {
            current = template.tanks.current or 0,
            needed = template.tanks.needed or 2,
        },
        healers = {
            current = template.healers.current or 0,
            needed = template.healers.needed or 6,
        },
        dps = {
            current = template.dps.current or 0,
            needed = template.dps.needed or 17,
        },
        gsMin = template.gsMin or 5000,
        ilvlMin = template.ilvlMin or 232,
        includeAddonLink = template.includeAddonLink ~= false,
        includeAchievements = template.includeAchievements or false,
        customNote = template.customNote or "",
    }

    AIP.Print("Saved template: " .. name)
    return true
end

-- Delete custom template
function MC.DeleteTemplate(name)
    if not AIP.db or not AIP.db.lfmTemplates then return false end
    if not AIP.db.lfmTemplates[name] then return false end

    AIP.db.lfmTemplates[name] = nil
    AIP.Print("Deleted template: " .. name)
    return true
end

-- ============================================================================
-- COMPOSITION SYNC
-- ============================================================================

-- Update current template with actual raid composition
function MC.SyncWithRaid()
    if not MC.CurrentTemplate then return end
    if not AIP.Composition or not AIP.Composition.ScanRaid then return end

    -- Scan current raid
    AIP.Composition.ScanRaid()
    local raid = AIP.Composition.CurrentRaid

    -- Update current values
    MC.CurrentTemplate.tanks.current = raid.roleCounts.TANK or 0
    MC.CurrentTemplate.healers.current = raid.roleCounts.HEALER or 0
    MC.CurrentTemplate.dps.current = raid.roleCounts.DPS or 0

    AIP.Print("Synced composition: T:" .. MC.CurrentTemplate.tanks.current ..
        "/" .. MC.CurrentTemplate.tanks.needed ..
        " H:" .. MC.CurrentTemplate.healers.current ..
        "/" .. MC.CurrentTemplate.healers.needed ..
        " D:" .. MC.CurrentTemplate.dps.current ..
        "/" .. MC.CurrentTemplate.dps.needed)

    -- Update UI if available
    if AIP.UpdateMessageComposerUI then
        AIP.UpdateMessageComposerUI()
    end
end

-- ============================================================================
-- SET CURRENT TEMPLATE
-- ============================================================================

-- Set the current editing template
function MC.SetCurrentTemplate(templateName)
    local template = MC.GetTemplate(templateName)
    if not template then
        AIP.Print("Template not found: " .. tostring(templateName))
        return false
    end

    -- Deep copy to avoid modifying original
    MC.CurrentTemplate = {
        name = template.name,
        raid = template.raid,
        tanks = {
            current = template.tanks.current or 0,
            needed = template.tanks.needed or 2,
        },
        healers = {
            current = template.healers.current or 0,
            needed = template.healers.needed or 6,
        },
        dps = {
            current = template.dps.current or 0,
            needed = template.dps.needed or 17,
        },
        gsMin = template.gsMin or 5000,
        ilvlMin = template.ilvlMin or 232,
        includeAddonLink = template.includeAddonLink ~= false,
        includeAchievements = template.includeAchievements or false,
        customNote = template.customNote or "",
    }

    -- Update UI if available
    if AIP.UpdateMessageComposerUI then
        AIP.UpdateMessageComposerUI()
    end

    return true
end

-- ============================================================================
-- BROADCAST
-- ============================================================================

-- Broadcast current message
function MC.Broadcast()
    if not MC.CurrentTemplate then
        AIP.Print("No template selected")
        return
    end

    local message = MC.GenerateMessage(MC.CurrentTemplate)

    -- Use the existing spam system from Core.lua for chat
    if AIP.db then
        local oldMessage = AIP.db.spamMessage
        AIP.db.spamMessage = message
        AIP.SpamInvite()
        AIP.db.spamMessage = oldMessage
    end

    -- Also broadcast via DataBus to other addon users
    MC.BroadcastToDataBus()
end

-- Broadcast LFM data to DataBus (other addon users)
function MC.BroadcastToDataBus()
    if not MC.CurrentTemplate then return false end
    if not AIP.DataBus then return false end

    local template = MC.CurrentTemplate

    -- Build DataBus event data
    local lfmData = {
        raid = template.raid,
        tanks = template.tanks,
        healers = template.healers,
        dps = template.dps,
        gsMin = template.gsMin,
        ilvlMin = template.ilvlMin,
        note = template.customNote,
        triggerKey = AIP.db and AIP.db.triggers or "inv",
        achievementsRequired = template.includeAchievements or false,
    }

    -- Publish via DataBus
    local success = AIP.DataBus.BroadcastLFM(lfmData)

    if success then
        AIP.Debug("MessageComposer: LFM broadcast to DataBus")
    end

    return success
end

-- Copy message to clipboard (via editbox)
function MC.CopyToChat(message)
    if not message then
        message = MC.GenerateMessage(MC.CurrentTemplate)
    end

    -- Open chat with the message pre-typed
    ChatFrame_OpenChat(message)
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

-- Initialize with default template
local function Initialize()
    if not MC.CurrentTemplate then
        MC.SetCurrentTemplate("ICC25HC")
    end
end

-- Delay initialization to ensure db is ready
local initFrame = CreateFrame("Frame")
local initStarted = false
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- Guard against multiple initialization attempts
        if initStarted then return end
        initStarted = true

        -- Short delay to ensure all modules loaded
        local delayFrame = CreateFrame("Frame")
        delayFrame.elapsed = 0
        delayFrame:SetScript("OnUpdate", function(df, elapsed)
            df.elapsed = df.elapsed + elapsed
            if df.elapsed >= 1 then
                Initialize()
                df:SetScript("OnUpdate", nil)
                df:Hide()
            end
        end)

        -- Unregister event after first trigger
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
