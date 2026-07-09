-- AutoInvite Plus - Raid Tools (core: chat sender, announcements, loot items)
-- Split into RaidTools / RaidToolsRoll / RaidToolsUI / RaidToolsEvents so the
-- WoW client load phase reports failures per-section.

local AIP = AutoInvitePlus
if not AIP then
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[AIP Error]|r RaidTools: namespace not found!")
    return
end

AIP.RaidTools = AIP.RaidTools or {}
local RT = AIP.RaidTools

-- Constants shared across the RaidTools files
RT.LOOT_EXPIRE_SECONDS = 7200   -- BoP trade window (2h)
RT.LOOT_WARN_SECONDS = 900      -- warn when <15m remaining

-- State
RT.rollActive = false
RT.rolls = {}
RT.rollItem = nil
RT.rollItemLink = nil
RT.rollEndTime = nil
RT.manualItems = {}
RT.selectedKey = nil
RT.warnedItems = {}

-- True only inside a 5-man or raid instance. Every encounter call-out (mechanic
-- announcer, debuff announcer, boss-ability timer bars) is gated on this. Without
-- it, generic spell/emote names shared with world and city content ("Frenzy",
-- "Fire Bomb", "Frost Breath", "Overcharge", "Vortex", "Freeze", "Deep Breath")
-- fire call-outs while questing, in town, or in battlegrounds. IsInInstance()
-- exists in 3.3.5a and returns (inInstance, instanceType).
function RT.InPveInstance()
    if not IsInInstance then return false end
    local inInstance, instanceType = IsInInstance()
    if not inInstance then return false end
    return instanceType == "party" or instanceType == "raid"
end

-- ============================================================================
-- CHAT SENDER (smart channel with safe fallbacks)
-- ============================================================================

function RT.Send(msg, channel)
    if not msg or msg == "" then return end
    channel = channel or "RAID_WARNING"
    local inRaid = (GetNumRaidMembers() or 0) > 0
    local inParty = (GetNumPartyMembers() or 0) > 0

    if channel == "RAID_WARNING" then
        if inRaid and (IsRaidLeader() or IsRaidOfficer()) then
            SendChatMessage(msg, "RAID_WARNING")
        elseif inRaid then
            SendChatMessage(msg, "RAID")
        elseif inParty then
            SendChatMessage(msg, "PARTY")
        else
            SendChatMessage(msg, "SAY")
        end
    elseif channel == "RAID" then
        if inRaid then SendChatMessage(msg, "RAID")
        elseif inParty then SendChatMessage(msg, "PARTY")
        else SendChatMessage(msg, "SAY") end
    elseif channel == "PARTY" then
        if inParty or inRaid then SendChatMessage(msg, "PARTY")
        else SendChatMessage(msg, "SAY") end
    elseif channel == "GUILD" then
        if IsInGuild() then SendChatMessage(msg, "GUILD") else SendChatMessage(msg, "SAY") end
    else
        SendChatMessage(msg, channel)
    end
end

-- ============================================================================
-- CUSTOM ANNOUNCEMENTS
-- ============================================================================

-- The floating bar's buttons ARE the raid-warning templates - the two are wired
-- to the same list (AIP.db.raidWarningTemplates), so editing in either place is
-- reflected in the other. Entries are {name, message, channel?}; RM.GetTemplates
-- seeds the defaults on first use.
function RT.GetAnnouncements()
    if not AIP.db then return {} end
    local RM = AIP.Panels and AIP.Panels.RaidMgmt
    if RM and RM.GetTemplates then
        return RM.GetTemplates()
    end
    AIP.db.raidWarningTemplates = AIP.db.raidWarningTemplates or {}
    return AIP.db.raidWarningTemplates
end

function RT.SendAnnouncement(index)
    local list = RT.GetAnnouncements()
    local ann = list[index]
    if ann then RT.Send(ann.message, ann.channel or "RAID_WARNING") end
end

-- ============================================================================
-- READY CHECK
-- ============================================================================

function RT.StartReadyCheck()
    local numRaid = GetNumRaidMembers() or 0
    local numParty = GetNumPartyMembers() or 0
    if numRaid == 0 and numParty == 0 then
        AIP.Print("Not in a group - cannot start a ready check.")
        return
    end
    if numRaid > 0 and not (IsRaidLeader() or IsRaidOfficer()) then
        AIP.Print("You must be raid leader or an assistant to start a ready check.")
        return
    end
    DoReadyCheck()
end

-- ============================================================================
-- BUFF DELEGATION
-- Assigns one distinct buff per same-class caster (Greater Blessings across
-- multiple Paladins, Prayers across Priests), and for classes that only provide
-- a single raid buff (Mage/Druid/etc.) it names ONE caster so two players of the
-- same class don't both burn mana on a redundant cast.
-- ============================================================================

RT.ClassBuffDuties = {
    PALADIN     = {multi = true,  buffs = {"Blessing of Kings", "Blessing of Might", "Blessing of Wisdom", "Blessing of Sanctuary"}},
    PRIEST      = {multi = true,  buffs = {"Prayer of Fortitude", "Prayer of Spirit", "Prayer of Shadow Protection"}},
    MAGE        = {multi = false, buffs = {"Arcane Brilliance"}},
    DRUID       = {multi = false, buffs = {"Gift of the Wild"}},
    DEATHKNIGHT = {multi = false, buffs = {"Horn of Winter"}},
    WARRIOR     = {multi = false, buffs = {"Battle/Commanding Shout"}},
    WARLOCK     = {multi = false, buffs = {"Fel Intelligence (Felhunter)"}},
    SHAMAN      = {perGroup = true, buffs = {"Totems for your group"}},
}

function RT.ClassLabel(class)
    local nice = class:sub(1, 1) .. class:sub(2):lower()
    if class == "DEATHKNIGHT" then nice = "Death Knight" end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, nice) end
    return nice
end

-- Map current group members by class file-name: {CLASS = {name1, name2, ...}}
function RT.GetRaidByClass()
    local byClass = {}
    local function add(class, name)
        if not class or not name then return end
        byClass[class] = byClass[class] or {}
        table.insert(byClass[class], name)
    end

    local numRaid = GetNumRaidMembers() or 0
    if numRaid > 0 then
        for i = 1, numRaid do
            local name, _, _, _, _, fileName = GetRaidRosterInfo(i)
            add(fileName, name)
        end
    else
        local _, pc = UnitClass("player")
        add(pc, UnitName("player"))
        for i = 1, (GetNumPartyMembers() or 0) do
            local _, c = UnitClass("party" .. i)
            add(c, UnitName("party" .. i))
        end
    end
    return byClass
end

-- Build delegation lines: {class = CLASS, text = "PlayerA -> Kings, PlayerB -> Might"}
function RT.GetBuffDelegation()
    local byClass = RT.GetRaidByClass()
    local out = {}
    for class, info in pairs(RT.ClassBuffDuties) do
        local players = byClass[class]
        if players and #players > 0 then
            local text
            if info.perGroup then
                if #players == 1 then
                    text = players[1] .. " -> " .. info.buffs[1]
                else
                    text = table.concat(players, ", ") .. " -> totems (one Shaman per group)"
                end
            elseif info.multi and #players > 1 then
                -- distribute distinct buffs round-robin (priority order)
                local parts = {}
                for idx, p in ipairs(players) do
                    local duty = info.buffs[((idx - 1) % #info.buffs) + 1]
                    parts[#parts + 1] = p .. " -> " .. duty
                end
                text = table.concat(parts, ", ")
            elseif #players > 1 then
                -- single-buff class with multiple players: one caster, rest are backup
                local parts = {players[1] .. " -> " .. info.buffs[1]}
                for idx = 2, #players do parts[#parts + 1] = players[idx] .. " (backup)" end
                text = table.concat(parts, ", ")
            else
                text = players[1] .. " -> " .. table.concat(info.buffs, ", ")
            end
            out[#out + 1] = {class = class, text = text}
        end
    end
    table.sort(out, function(a, b) return a.class < b.class end)
    return out
end

function RT.AnnounceBuffDelegation()
    local numRaid = GetNumRaidMembers() or 0
    local numParty = GetNumPartyMembers() or 0
    if numRaid == 0 and numParty == 0 then
        AIP.Print("Not in a group - nobody to assign buffs to.")
        return
    end

    local lines = RT.GetBuffDelegation()
    if #lines == 0 then
        RT.Send("No buff-providing classes present to delegate.", "RAID")
        return
    end

    RT.Send("=== Buff Assignments ===", "RAID_WARNING")
    -- Stagger the per-class lines so we don't trip the chat throttle.
    for idx, l in ipairs(lines) do
        local text = RT.ClassLabel(l.class) .. ": " .. l.text
        if AIP.Utils and AIP.Utils.DelayedCall then
            AIP.Utils.DelayedCall(idx * 0.4, function() RT.Send(text, "RAID") end)
        else
            RT.Send(text, "RAID")
        end
    end
    AIP.Print("Buff assignments announced to raid.")
end

-- ============================================================================
-- SELF DEBUFF / CURSE ANNOUNCER
-- Calls out important raid debuffs on YOU (with stack count, re-announced as the
-- stack climbs) plus a short note on what to do. Action hints are sourced from
-- standard WotLK encounter strategy (ICC/ToC/Ulduar). Keep them short.
-- ============================================================================

-- Comprehensive WotLK encounter debuffs (exact aura names) with a short action
-- hint. Anything not listed here is still announced generically if it is a curse
-- or stacks (see ScanSelfDebuffs).
RT.KnownDebuffs = {
    -- ===== Icecrown Citadel =====
    ["Impaled"]                  = "DPS free me - bone spike!",   -- Marrowgar
    ["Coldflame"]                = "move out of the flame!",       -- Marrowgar
    ["Death and Decay"]          = "move out!",                    -- Lady Deathwhisper
    ["Curse of Torpor"]          = "decurse me!",                  -- Lady Deathwhisper
    ["Rune of Blood"]            = "tank hit - heal me up!",       -- Saurfang
    ["Mark of the Fallen Champion"] = "keep me topped off!",      -- Saurfang
    ["Boiling Blood"]            = "dot on me - heal!",            -- Saurfang
    ["Gastric Bloat"]            = "stop - swap eaters!",          -- Festergut
    ["Gas Spore"]                = "share spore with group!",      -- Festergut
    ["Mutated Infection"]        = "move away from raid, then dispel me!", -- Rotface
    ["Vile Gas"]                 = "spread - vile gas!",           -- Rotface / Putricide
    ["Volatile Ooze Adhesive"]   = "run! ranged stack on me!",     -- Putricide
    ["Gaseous Bloat"]            = "run - lead the gas cloud away from raid!", -- Putricide
    ["Unbound Plague"]           = "pass it - run to partner!",    -- Putricide
    ["Mutated Plague"]           = "tank - stacking, swap soon!",  -- Putricide
    ["Shock Vortex"]             = "spread out!",                  -- Blood Princes
    ["Empowered Shock Vortex"]   = "SPREAD - big shock!",          -- Blood Princes
    ["Swarming Shadows"]         = "move - trail away from raid!", -- Blood Queen
    ["Pact of the Darkfallen"]   = "stack with linked players!",   -- Blood Queen
    ["Frenzied Bloodthirst"]     = "bite a DPS now!",              -- Blood Queen
    ["Uncontrollable Frenzy"]    = "mind-controlled until death - raid KILL me!", -- Blood Queen
    ["Shadow Prison"]            = "STOP MOVING!",                 -- Blood Queen
    ["Mystic Buffet"]            = "hide behind an Ice Tomb to drop your stacks!", -- Sindragosa
    ["Unchained Magic"]          = "slow casts - watch Instability!", -- Sindragosa
    ["Instability"]              = "STOP casting NOW!",            -- Sindragosa
    ["Frost Beacon"]             = "Ice Tomb - everyone clear!",   -- Sindragosa
    ["Ice Tomb"]                 = "tombed - stack behind me!",    -- Sindragosa
    ["Necrotic Plague"]          = "run to adds + dispel me!",     -- Lich King
    ["Infest"]                   = "heal me above 90%!",           -- Lich King
    ["Defile"]                   = "move OUT - it grows!",         -- Lich King
    ["Soul Reaper"]              = "tank - pop haste/cds!",        -- Lich King
    ["Harvest Soul"]             = "kill spirits in Frostmourne!", -- Lich King

    -- ===== Ruby Sanctum =====
    ["Fiery Combustion"]         = "move out + dispel me!",        -- Halion
    ["Soul Consumption"]         = "spread - then dispel me!",     -- Halion
    ["Mark of Combustion"]       = "move out + dispel me!",        -- Halion

    -- ===== Trial of the Crusader =====
    ["Paralytic Toxin"]          = "get Burning Bile to cleanse!", -- Acidmaw
    ["Burning Bile"]             = "cleanse a poisoned ally!",     -- Dreadscale
    ["Impale"]                   = "tank - stacking!",            -- Gormok
    ["Fire Bomb"]                = "move - drop fire away!",       -- Gormok snobold
    ["Legion Flame"]             = "move away from raid!",         -- Jaraxxus
    ["Incinerate Flesh"]         = "burst heal / absorb me!",      -- Jaraxxus
    ["Pursue"]                   = "boss chasing me - make way!",  -- Anub'arak
    ["Penetrating Cold"]         = "heal me - cold!",              -- Anub'arak

    -- ===== Ulduar =====
    ["Slag Pot"]                 = "in pot - heal me!",            -- Ignis
    ["Flame Jets"]               = "STOP casting!",                -- Ignis
    ["Devouring Flame"]          = "move out!",                    -- Razorscale
    ["Gravity Bomb"]             = "move away from raid!",         -- XT-002
    ["Searing Light"]            = "move away from raid!",         -- XT-002
    ["Static Disruption"]        = "spread out!",                  -- Assembly of Iron
    ["Rune of Death"]            = "move out!",                    -- Assembly of Iron
    ["Overwhelming Power"]       = "tank - run out at expire!",    -- Steelbreaker
    ["Stone Grip"]               = "DPS free me!",                 -- Kologarn
    ["Focused Eyebeam"]          = "move - eyebeam on me!",        -- Kologarn
    ["Flash Freeze"]             = "frozen in ice - allies break me out fast!", -- Hodir
    ["Biting Cold"]              = "keep moving - stacks while you stand still!", -- Hodir
    ["Iron Roots"]               = "DPS free me!",                 -- Freya
    ["Nature's Fury"]            = "move away from raid!",         -- Freya
    ["Rocket Strike"]            = "MOVE - rocket!",               -- Mimiron
    ["Napalm Shell"]             = "spread - ranged!",             -- Mimiron
    ["Mark of the Faceless"]     = "move away from raid!",         -- Vezax
    ["Malady of the Mind"]       = "run out - fear!",              -- Yogg-Saron
    ["Brain Link"]               = "stay near linked player!",     -- Yogg-Saron
    ["Phase Punch"]              = "tank - phasing, swap!",        -- Algalon
    ["Cosmic Smash"]             = "move off the marker!",         -- Algalon

    -- ===== Naxxramas =====
    ["Web Wrap"]                 = "DPS free me!",                 -- Maexxna
    ["Necrotic Poison"]          = "cleanse me!",                  -- Maexxna
    ["Curse of the Plaguebringer"] = "decurse me!",               -- Noth
    ["Decrepit Fever"]           = "cure me - spread out!",        -- Heigan
    ["Mutating Injection"]       = "move out, then dispel me!",    -- Grobbulus
    ["Mark of Korth'azz"]        = "swap sides - stacking!",       -- Four Horsemen
    ["Mark of Blaumeux"]         = "swap sides - stacking!",       -- Four Horsemen
    ["Mark of Rivendare"]        = "swap sides - stacking!",       -- Four Horsemen
    ["Mark of Zeliek"]           = "swap sides - stacking!",       -- Four Horsemen
    ["Frost Blast"]              = "frozen - others spread!",      -- Kel'Thuzad

    -- ===== Vault of Archavon =====
    ["Overcharge"]               = "move away - overcharged!",     -- Emalon

    -- ===== 5-man dungeons (ICC / heroics) =====
    ["Mirrored Soul"]            = "STOP DPS - reflects to me!",   -- Devourer of Souls (FoS)
    ["Overlord's Brand"]         = "branded - mirrors damage!",    -- Tyrannus (PoS)
    ["Pursuit"]                  = "chased - kite the boss!",      -- Krick (PoS)
    ["Insanity"]                 = "kill the phantoms!",           -- Herald Volazj (Old Kingdom)
}

RT.debuffState = {}  -- name -> {stacks, t}
local DEBUFF_MIN_INTERVAL = 2  -- seconds between re-announces of the same debuff

-- Dispel call-out: the action verb plus the classes that can actually remove
-- this debuff type in WotLK (3.3.5a). Friendly-dispel matrix (verified):
--   Magic   -> Priest, Paladin                (Shaman's Purge is offensive-only)
--   Curse   -> Mage, Druid, Shaman
--   Poison  -> Druid, Paladin, Shaman
--   Disease -> Priest, Paladin, Shaman
-- Returns nil for a nil/empty dtype, i.e. a debuff NO class can dispel - the
-- caller MUST NOT then ask another player to remove it.
local function debuffDispelVerb(dtype)
    if dtype == "Curse" then return "DECURSE me! (Mage/Druid/Shaman)"
    elseif dtype == "Poison" then return "CLEANSE poison off me! (Druid/Pala/Shaman)"
    elseif dtype == "Disease" then return "CURE disease on me! (Priest/Pala/Shaman)"
    elseif dtype == "Magic" then return "DISPEL magic off me! (Priest/Pala)"
    else return nil end
end

function RT.SayDebuff(name, stacks, action, channel)
    local txt = name
    if stacks > 1 then txt = txt .. " x" .. stacks end
    RT.Send(txt .. " - " .. action, channel or "SAY")
end

-- Scan the player's debuffs and announce the noteworthy ones. Called from
-- UNIT_AURA (player). Cheap and self-throttling: it only speaks on a new
-- application or when a stack count actually increases.
function RT.ScanSelfDebuffs()
    if not (AIP.db and AIP.db.debuffAnnounce) then return end
    -- Encounter mechanic: never fire out in the world / in a battleground.
    if not RT.InPveInstance() then return end

    local channel = AIP.db.debuffAnnounceChannel or "SAY"
    local now = GetTime()
    local seen = {}

    for i = 1, 40 do
        local name, _, _, count, dtype = UnitDebuff("player", i)
        if not name then break end
        local stacks = (count and count > 0) and count or 1
        local known = RT.KnownDebuffs[name]
        local dispelHint = debuffDispelVerb(dtype)  -- nil = nobody can remove it

        -- Decide the action, and crucially DO NOT ask another player to remove a
        -- debuff that no class can dispel:
        --   * a known encounter debuff uses its hand-tuned call-out;
        --   * an unknown but dispellable debuff asks the correct class;
        --   * an unknown, non-dispellable debuff that merely stacks gets a
        --     neutral self-directed note (no false "dispel me" request);
        --   * anything else is ignored.
        local action
        if known then
            action = known
        elseif dispelHint then
            action = dispelHint
        elseif stacks > 1 then
            action = "stacking on you - react!"
        end

        if action then
            seen[name] = true
            local st = RT.debuffState[name]
            if not st then
                RT.SayDebuff(name, stacks, action, channel)
                RT.debuffState[name] = {stacks = stacks, t = now}
            elseif stacks > st.stacks then
                if (now - st.t) >= DEBUFF_MIN_INTERVAL then
                    RT.SayDebuff(name, stacks, action, channel)
                    st.t = now
                end
                st.stacks = stacks
            end
        end
    end

    -- Forget debuffs that have fallen off so re-applies announce again.
    for name in pairs(RT.debuffState) do
        if not seen[name] then RT.debuffState[name] = nil end
    end
end

-- ============================================================================
-- AUTO MECHANIC ANNOUNCER  (opt-in "mini-DBM")
-- Trackable in the 3.3.5a client (confirmed against DBM-WotLK): boss spell casts
-- via the combat log, boss yells/emotes, and target/focus health (there is no
-- boss1 token or ENCOUNTER_START in this client). Default output is a personal
-- center-screen heads-up so it doesn't spam raid chat when several people run it.
-- ============================================================================

-- Boss ability (exact combat-log spell name) -> short call-out. Fires on the
-- boss's SPELL_CAST_START / SPELL_AURA_APPLIED.
RT.MechanicSpells = {
    -- ===== Icecrown Citadel =====
    ["Bone Storm"]            = "Bone Storm - run away from Marrowgar!",
    ["Coldflame"]            = "Coldflame - step off the fire lines!",
    ["Bone Spike Graveyard"] = "Bone Spike - DPS the impaled players free!",
    ["Death and Decay"]      = "move out of Death and Decay (the ground pool)!",
    ["Dominate Mind"]        = "Mind Control - crowd-control the charmed player!",
    ["Blood Beasts"]         = "Blood Beasts up - AoE them down fast!",
    ["Pungent Blight"]       = "Pungent Blight - spore stacks reset (Festergut)!",
    ["Malleable Goo"]        = "Malleable Goo thrown - dodge the green blob!",
    ["Choking Gas Bomb"]     = "Gas Bombs dropped - move out of the gas!",
    ["Unstable Experiment"]  = "Ooze/Gas spawned - kite it to its matching side!",
    ["Ooze Flood"]           = "Ooze Flood - move away from the flooding side!",
    ["Unstable Ooze Explosion"] = "Ooze Explosion - spread out, it chains between players!",
    ["Empowered Shock Vortex"] = "Empowered Shock Vortex - SPREAD OUT NOW!",
    ["Bloodbolt Whirl"]      = "Bloodbolt Whirl - spread out (hits nearby players)!",
    ["Frost Breath"]         = "Frost Breath on the tank - do NOT stand in front of Sindragosa!",
    ["Blistering Cold"]      = "Blistering Cold - run 25yd AWAY from Sindragosa NOW!",
    ["Defile"]               = "Defile - move OUT of the black circle (it grows if stood in)!",
    ["Soul Reaper"]          = "Soul Reaper on the tank - healers big cooldown!",
    ["Remorseless Winter"]   = "Transition - spread, dodge Ice Spheres, kill Raging Spirits!",
    ["Vile Spirits"]         = "Vile Spirits up - ranged shoot them before they reach the raid!",
    ["Harvest Soul"]         = "Harvest Soul - target pulled in, kill the spirit in Frostmourne!",
    -- ===== Ruby Sanctum =====
    ["Twilight Cutter"]      = "Twilight beam - move out from between the orbs!",
    ["Meteor Strike"]        = "Meteor marked - clear that spot, stack behind the flame wall!",
    -- ===== Ulduar =====
    ["Tympanic Tantrum"]     = "Tympanic Tantrum - raid-wide damage, heal through it!",
    ["Gravity Bomb"]         = "Gravity Bomb - marked player moves away from the raid!",
    ["Searing Light"]        = "Searing Light - marked player moves away from the raid!",
    ["Rocket Strike"]        = "Rockets incoming - move off the target lines!",
    ["Plasma Blast"]         = "Plasma Blast - tank pop a big cooldown!",
    ["Shock Blast"]          = "Shock Blast - get OUT of melee range of Leviathan Mk II!",
    ["Frost Bomb"]           = "Frost Bomb - destroy it before it detonates!",
    ["Saronite Vapors"]      = "Saronite Vapors up - careful, they heal mana but hurt (Vezax)!",
    ["Shadow Crash"]         = "Shadow Crash - move out of the shadow void zone!",
    ["Death Ray"]            = "Death Ray - move out of its path!",
    ["Flash Freeze"]         = "Flash Freeze - spread and get to a Snowpack/marker (Hodir)!",
    ["Nature Bomb"]          = "Nature Bombs up - destroy them before they explode (Freya)!",
    -- ===== Trial of the (Grand) Crusader =====
    ["Fire Bomb"]            = "Fire Bombs dropping - move out of the fire!",
    ["Massive Crash"]        = "Massive Crash - run away from Icehowl (charge incoming)!",
    ["Nether Power"]         = "Nether Power - dispel the magic buff OFF Jaraxxus!",
    ["Legion Flame"]         = "Legion Flame - marked player runs it away (leaves a fire trail)!",
    ["Incinerate Flesh"]     = "Incinerate Flesh - burst-heal the target before it blows!",
    -- ===== Naxxramas =====
    ["Mutating Injection"]   = "Mutating Injection - move out, THEN get dispelled (spawns cloud+slime)!",
    ["Frost Blast"]          = "Frost Blast - a player is encased, break them out fast!",
    ["Polarity Shift"]       = "Polarity Shift - group with players of your SAME charge (+/-)!",
    ["Shadow Fissure"]       = "Shadow Fissure - move out of the purple void zone!",
    -- ===== Obsidian Sanctum / Eye of Eternity / Onyxia / VoA =====
    ["Flame Tsunami"]        = "Flame Tsunami - jump/move over the lava wave!",
    ["Surge of Power"]       = "Surge of Power - spread out / get to max range!",
    ["Vortex"]               = "Vortex - raid pulled in and takes damage, heal up!",
    ["Deep Breath"]          = "Deep Breath - Onyxia is about to breathe, clear the middle NOW!",
    ["Bellowing Roar"]       = "Bellowing Roar = FEAR - use Tremor Totem / Fear Ward / Berserker Rage!",
    ["Overcharge"]           = "Overcharge - move away from the overcharged player!",
}

-- Boss emote substrings (lowercased) -> short call-out. Only matched against the
-- CHAT_MSG_RAID_BOSS_EMOTE channel (scripted boss emotes), NOT monster
-- emotes/yells - those carry trash-mob and world-mob text, so generic words like
-- "frenzy" / "channel" / "submerge" there caused false call-outs. Keep every
-- phrase here specific enough that essentially only the intended boss emits it.
RT.BossEmotes = {
    ["inhales deeply"] = "Festergut inhales - Gas Spore soon, get into a group!",    -- Festergut
    ["frost beacon"]   = "Frost Beacon on a player - Ice Tomb incoming, clear away!", -- Sindragosa
    ["deep breath"]    = "Deep Breath - Onyxia is about to breathe, clear the middle!", -- Onyxia
    ["fixate"]         = "boss is fixating on a player - kite it, don't face-tank it!", -- Blood Queen / adds
}

-- ============================================================================
-- CLASS-TARGETED MECHANIC DUTIES
-- When a mechanic fires, tell the SPECIFIC classes present in the group what to
-- do with a class ability (Spellsteal the boss, Tranq a frenzy, Tremor the fear,
-- CC the mind-controlled player, etc.). Keyed by the same combat-log spell name
-- as RT.MechanicSpells; each duty is {class = "<CLASSFILE>", action = "<verb>"}.
-- Only classes with a REAL, commonly-used WotLK 3.3.5a ability for that mechanic
-- are listed. Delivery is handled by RT.EmitClassDuties (personal heads-up for
-- your own class on SELF; leader-gated per-class raid lines on a chat channel).
-- Entries are verified against encounter/class guides; expanded from research.
-- ============================================================================
-- CC set reused for mind-control mechanics (charmed player is a Humanoid).
-- Ordered by how commonly the class is assigned; Cyclone is best (damage-immune).
local MC_CC = {
    {class = "DRUID",   action = "Cyclone the mind-controlled player (best)!"},
    {class = "MAGE",    action = "Polymorph the mind-controlled player!"},
    {class = "WARLOCK", action = "Fear the mind-controlled player!"},
    {class = "SHAMAN",  action = "Hex the mind-controlled player!"},
    {class = "PALADIN", action = "Repentance the mind-controlled player!"},
    {class = "HUNTER",  action = "Freezing Trap the mind-controlled player!"},
    {class = "ROGUE",   action = "Blind the mind-controlled player!"},
}

RT.MechanicClassDuties = {
    -- ===== Icecrown Citadel =====
    -- Lady Deathwhisper: Dominate Mind is UNDISPELLABLE - CC only (not "dispel").
    ["Dominate Mind"] = MC_CC,
    ["Curse of Torpor"] = {  -- Curse -> Mage/Druid/Shaman only
        {class = "MAGE",   action = "Remove Curse it off the player fast!"},
        {class = "DRUID",  action = "Remove Curse it off the player fast!"},
        {class = "SHAMAN", action = "Cleanse Spirit it off the player fast!"},
    },
    -- Deathbringer Saurfang: Blood Beasts have Resistant Skin -> single-target
    -- SLOW/CC them off the healers, do NOT try to AoE them down.
    ["Blood Beasts"] = {
        {class = "MAGE",        action = "Frost Nova / slow the Blood Beasts off healers!"},
        {class = "DEATHKNIGHT", action = "Chains of Ice / Death Grip the Blood Beasts!"},
        {class = "HUNTER",      action = "Frost Trap / Concussive the Blood Beasts!"},
        {class = "SHAMAN",      action = "Earthbind / Frost Shock the Blood Beasts!"},
    },
    -- The Lich King: Vile Spirits = raid-wide Shadow burst -> magic mitigation CDs.
    ["Vile Spirits"] = {
        {class = "DEATHKNIGHT", action = "Anti-Magic Zone for the Vile Spirit burst!"},
        {class = "PALADIN",     action = "Divine Sacrifice / Aura Mastery for the burst!"},
        {class = "WARLOCK",     action = "Shadow Ward (self) for the burst!"},
    },

    -- ===== Ruby Sanctum — Halion (Fiery Combustion / Soul Consumption = Magic) =====
    ["Fiery Combustion"] = {
        {class = "PRIEST",  action = "Dispel Magic the marked player at the room edge!"},
        {class = "PALADIN", action = "Cleanse the marked player at the room edge!"},
    },
    ["Soul Consumption"] = {
        {class = "PRIEST",  action = "Dispel Magic the marked player (Twilight realm)!"},
        {class = "PALADIN", action = "Cleanse the marked player (Twilight realm)!"},
    },

    -- ===== Trial of the (Grand) Crusader =====
    -- Jaraxxus Nether Power: boss Magic buff -> OFFENSIVE dispel (Warriors can't).
    ["Nether Power"] = {
        {class = "MAGE",    action = "Spellsteal it off Jaraxxus!"},
        {class = "SHAMAN",  action = "Purge it off Jaraxxus!"},
        {class = "PRIEST",  action = "offensive Dispel Magic off Jaraxxus!"},
        {class = "HUNTER",  action = "Tranquilizing Shot the boss!"},
        {class = "WARLOCK", action = "Felhunter Devour Magic the boss!"},
    },
    ["Impale"] = {  -- Gormok tank bleed (Physical) -> HoP wipes it (or tank-swap)
        {class = "PALADIN", action = "Hand of Protection wipes the bleed (or tank-swap)!"},
    },
    ["Pursue"] = {  -- Anub'arak spike fixate -> HoP nullifies the spike hit
        {class = "PALADIN", action = "Hand of Protection the pursued player (blocks the spike)!"},
    },

    -- ===== Ulduar — Assembly of Iron (Fusion Punch leaves a MAGIC DoT on tank) =====
    ["Fusion Punch"] = {
        {class = "PRIEST",  action = "Dispel the Fusion Punch DoT off the tank!"},
        {class = "PALADIN", action = "Cleanse the Fusion Punch DoT off the tank!"},
        {class = "WARLOCK", action = "Devour Magic the Fusion Punch DoT off the tank!"},
    },

    -- ===== Naxxramas =====
    ["Chains of Kel'Thuzad"] = MC_CC,  -- P2 mind control -> CC the charmed player
    ["Mutating Injection"] = {  -- Grobbulus: MAGIC, dispel ONLY after they run out
        {class = "PRIEST",  action = "Dispel it AFTER they run 20yd out!"},
        {class = "PALADIN", action = "Cleanse it AFTER they run 20yd out!"},
    },
    ["Necrotic Poison"] = {  -- Maexxna: Poison -> Druid/Paladin/Shaman
        {class = "DRUID",   action = "Abolish Poison off the tank!"},
        {class = "PALADIN", action = "Cleanse the poison off the tank!"},
        {class = "SHAMAN",  action = "Poison Cleansing Totem by the tank!"},
    },
    ["Curse of the Plaguebringer"] = {  -- Noth: Curse, explodes if not removed
        {class = "MAGE",   action = "Remove Curse fast (raid-wide blast if not)!"},
        {class = "DRUID",  action = "Remove Curse fast (raid-wide blast if not)!"},
        {class = "SHAMAN", action = "Cleanse Spirit fast (raid-wide blast if not)!"},
    },
    ["Decrepit Fever"] = {  -- Heigan: Disease -> Priest/Paladin/Shaman
        {class = "PRIEST",  action = "Abolish Disease it!"},
        {class = "PALADIN", action = "Cleanse the disease!"},
        {class = "SHAMAN",  action = "Disease Cleansing Totem!"},
    },

    -- ===== Onyxia — Bellowing Roar (Physical fear: prevent/break, can't dispel) =====
    ["Bellowing Roar"] = {
        {class = "SHAMAN",  action = "drop Tremor Totem for the fear!"},
        {class = "PRIEST",  action = "Fear Ward the tank (Priest-only)!"},
        {class = "WARRIOR", action = "Berserker Rage to break/prevent the fear!"},
    },
    -- ===== Blood-Queen Lana'thel — Incite Terror (Magic fear) =====
    ["Incite Terror"] = {
        {class = "PRIEST", action = "Fear Ward the tank / Mass Dispel the fear!"},
        {class = "SHAMAN", action = "drop Tremor Totem for the fear!"},
    },
}

-- Bloodlust family -> show a duration + lockout countdown when applied.
RT.LustSpells = {
    ["Bloodlust"] = true, ["Heroism"] = true,
    ["Time Warp"] = true, ["Ancient Hysteria"] = true,
}

-- Recast interval (seconds) for signature boss abilities. When the boss casts
-- one, a countdown to the *next* expected cast is shown with a pre-warning.
-- All values are the steady-state recast cooldowns verified against DBM-WotLK
-- (NewNextTimer / NewCDTimer); they are accurate once the ability is seen once.
RT.AbilityTimers = {
    -- ===== Icecrown Citadel =====
    ["Bone Storm"]             = 90,    -- Marrowgar (69076)
    ["Dominate Mind"]          = 40,    -- Lady Deathwhisper (71289)
    ["Rune of Blood"]          = 20,    -- Saurfang (72410)
    ["Boiling Blood"]          = 16,    -- Saurfang (72385)
    ["Blood Nova"]             = 20,    -- Saurfang (72378)
    ["Gas Spore"]              = 40,    -- Festergut (69279)
    ["Vile Gas"]               = 30,    -- Rotface (72272)
    ["Slime Spray"]            = 21,    -- Rotface (69508)
    ["Unstable Experiment"]    = 38,    -- Putricide (70351)
    ["Choking Gas Bomb"]       = 35,    -- Putricide (71255)
    ["Malleable Goo"]          = 25,    -- Putricide (72295)
    ["Shock Vortex"]           = 17,    -- Blood Prince Council (72037)
    ["Empowered Shock Vortex"] = 17,    -- Blood Prince Council
    ["Pact of the Darkfallen"] = 30,    -- Lana'thel (71340)
    ["Swarming Shadows"]       = 30,    -- Lana'thel (71266)
    ["Frost Breath"]           = 22,    -- Sindragosa (69649)
    ["Unchained Magic"]        = 30,    -- Sindragosa (69762)
    ["Blistering Cold"]        = 67,    -- Sindragosa (70123)
    ["Defile"]                 = 33,    -- Lich King (72762)
    ["Soul Reaper"]            = 30,    -- Lich King (69409)
    ["Infest"]                 = 22,    -- Lich King (70541)
    ["Necrotic Plague"]        = 30,    -- Lich King (70337)
    ["Vile Spirits"]           = 30,    -- Lich King (70498)
    ["Harvest Soul"]           = 75,    -- Lich King heroic (68980)

    -- ===== Ulduar =====
    ["Flame Jets"]             = 24,    -- Ignis (63472)
    ["Devouring Flame"]        = 21,    -- Razorscale (64021)
    ["Tympanic Tantrum"]       = 61,    -- XT-002 (62776)
    ["Overload"]               = 70,    -- Assembly of Iron (63481)
    ["Rune of Death"]          = 47,    -- Assembly of Iron (63490)
    ["Focused Eyebeam"]        = 18,    -- Kologarn (63346)
    ["Stone Grip"]             = 20,    -- Kologarn (64292)
    ["Flash Freeze"]           = 50,    -- Hodir (61968)
    ["Iron Roots"]             = 14,    -- Freya (62438)
    ["Rocket Strike"]          = 20,    -- Mimiron (64402)
    ["Shock Blast"]            = 35,    -- Mimiron (63631)
    ["Plasma Blast"]           = 30,    -- Mimiron (64529)
    ["Shadow Crash"]           = 10,    -- General Vezax (62660)
    ["Mark of the Faceless"]   = 20,    -- General Vezax (63276)
    -- Yogg-Saron's Malady of the Mind (63830) and Brain Link (63802) are
    -- brain-phase-gated with no steady cadence - DBM keeps their CD timers
    -- commented out for exactly this reason, so a fixed countdown here would be
    -- misleading. They still fire a debuff call-out via RT.KnownDebuffs.
    ["Cosmic Smash"]           = 25,    -- Algalon (64596)
    ["Phase Punch"]            = 16,    -- Algalon (64412)
    ["Big Bang"]               = 90,    -- Algalon (64584)

    -- ===== Trial of the (Grand) Crusader =====
    ["Massive Crash"]          = 55,    -- Icehowl (66683)
    ["Legion Flame"]           = 30,    -- Jaraxxus (66197)
    ["Nether Power"]           = 42,    -- Jaraxxus (67009)
    ["Incinerate Flesh"]       = 23,    -- Jaraxxus (66237)

    -- ===== Ruby Sanctum =====
    ["Fiery Combustion"]       = 30,    -- Halion (74562)
    ["Meteor Strike"]          = 40,    -- Halion (74648)
    ["Twilight Cutter"]        = 15,    -- Halion (74769)
    ["Soul Consumption"]       = 25,    -- Halion (74792)

    -- ===== Vault of Archavon =====
    ["Overcharge"]             = 45,    -- Emalon (64218)
    ["Whiteout"]               = 38,    -- Toravon (72034)

    -- ===== Eye of Eternity =====
    ["Vortex"]                 = 60,    -- Malygos (56105)
    ["Arcane Breath"]          = 59,    -- Malygos (56505)

    -- Onyxia's Deep Breath has a VARIABLE cooldown, so a fixed "next cast"
    -- countdown would be misleading - it is announced off its cast/emote via
    -- MechanicSpells/BossEmotes instead of shown as a recast bar.

    -- ===== Naxxramas =====
    ["Polarity Shift"]         = 30,    -- Thaddius (28089)
    ["Frost Blast"]            = 35,    -- Kel'Thuzad (27808)
    ["Mutating Injection"]     = 15,    -- Grobbulus (28240 cloud cadence)

    -- 5-man dungeons: WotLK has no authoritative recast-timer source and the
    -- fights are short, so dungeon mechanics rely on the mechanic/debuff
    -- announcers (Mirrored Soul, Overlord's Brand, etc.) rather than timers.
}

RT.mechLast = {}        -- spell/emote key -> last GetTime()
RT.bossHpSeen = {}      -- guid -> {threshold = true}
RT.lastRaidHealthWarn = 0

-- Emit a mechanic call-out through the configured channel.
function RT.EmitMechanic(text)
    if not text or text == "" then return end
    local channel = (AIP.db and AIP.db.mechanicAnnounceChannel) or "SELF"
    if channel == "SELF" then
        if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
            RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo["RAID_WARNING"])
        end
        if AIP.Print then AIP.Print("|cFFFF6600[Mechanic]|r " .. text) end
    else
        RT.Send(text, channel)
    end
end

local function mechThrottled(key, interval)
    local now = GetTime()
    if RT.mechLast[key] and (now - RT.mechLast[key]) < (interval or 3) then return true end
    RT.mechLast[key] = now
    return false
end

-- May the local player BROADCAST duty call-outs to the group without causing
-- multi-user spam (when several people run the addon)? Only the raid
-- leader/assistant, or the party leader in a 5-man, does. Solo returns true so
-- previews work.
function RT.CanBroadcast()
    if (GetNumRaidMembers() or 0) > 0 then
        return IsRaidLeader() or IsRaidOfficer()
    elseif (GetNumPartyMembers() or 0) > 0 then
        return IsPartyLeader() == 1 or IsPartyLeader() == true
    end
    return true
end

-- Class-targeted duty call-outs for a mechanic. Delivery follows
-- mechanicAnnounceChannel, mirroring EmitMechanic:
--   * SELF (default), or a chat channel while you are NOT leader: a personal
--     center-screen heads-up for the LOCAL PLAYER'S OWN class only -> no spam.
--   * a chat channel while you ARE raid leader/assistant (or party leader): one
--     staggered line per PRESENT class, naming its member(s), so even players
--     without the addon get told what to do.
-- A duty line is emitted only for a class that is actually in the group.
function RT.EmitClassDuties(key)
    if not (AIP.db and AIP.db.classDutyAnnounce) then return end
    local duties = key and RT.MechanicClassDuties[key]
    if not duties then return end

    local byClass = RT.GetRaidByClass()
    local channel = (AIP.db and AIP.db.mechanicAnnounceChannel) or "SELF"

    if channel ~= "SELF" and RT.CanBroadcast() then
        -- Stagger so several duties for one mechanic don't trip the chat throttle.
        local delay = 0
        for _, d in ipairs(duties) do
            local members = byClass[d.class]
            if members and #members > 0 then
                local line = RT.ClassLabel(d.class) .. ": " .. d.action
                    .. " (" .. table.concat(members, ", ") .. ")"
                if AIP.Utils and AIP.Utils.DelayedCall then
                    AIP.Utils.DelayedCall(delay, function() RT.Send(line, channel) end)
                    delay = delay + 0.3
                else
                    RT.Send(line, channel)
                end
            end
        end
    else
        -- Personal: only the local player's own class duty, as a heads-up (never
        -- a chat send - so a non-leader on a raid channel doesn't spam).
        local _, myClass = UnitClass("player")
        for _, d in ipairs(duties) do
            if d.class == myClass then
                local text = "Your duty: " .. d.action
                if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
                    RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo["RAID_WARNING"])
                end
                if AIP.Print then AIP.Print("|cFF33FF99[Your duty]|r " .. d.action) end
            end
        end
    end
end

-- Combat-log driven boss ability detection + signature-ability countdowns.
function RT.OnMechanicCombatLog(...)
    if not (AIP.db and AIP.db.mechanicAnnounce) then return end
    if not RT.InPveInstance() then return end
    local sub = select(2, ...)

    -- Bloodlust/Heroism (a friendly buff) -> duration + lockout timers.
    if sub == "SPELL_AURA_APPLIED" then
        local sName = select(10, ...)
        if sName and RT.LustSpells[sName] then
            RT.StartTimer("lust", sName, 40, 0.2, 0.9, 0.3, nil, "Interface\\Icons\\Spell_Nature_BloodLust")
            RT.StartTimer("sated", "Sated (lockout)", 600, 1, 0.3, 0.3, nil, "Interface\\Icons\\Spell_Nature_BloodLust")
            return
        end
    end

    if sub ~= "SPELL_CAST_START" and sub ~= "SPELL_AURA_APPLIED" and sub ~= "SPELL_CAST_SUCCESS" then
        return
    end
    local srcFlags = select(5, ...)
    local spellName = select(10, ...)
    if not spellName then return end
    local msg = RT.MechanicSpells[spellName]
    local interval = RT.AbilityTimers[spellName]
    local duties = RT.MechanicClassDuties[spellName]
    if not msg and not (interval and interval > 0) and not duties then return end
    -- Only react to a hostile caster (the boss), never the player/allies.
    if srcFlags and bit and bit.band and bit.band(srcFlags, 0x00000040) == 0 then return end

    if msg and not mechThrottled("s:" .. spellName, 3) then
        RT.EmitMechanic(msg)
    end
    if duties and not mechThrottled("c:" .. spellName, 3) then
        RT.EmitClassDuties(spellName)
    end
    if interval and interval > 0 and not mechThrottled("t:" .. spellName, math.max(5, interval * 0.5)) then
        RT.StartTimer("t:" .. spellName, spellName, interval, 1, 0.6, 0.1, "~" .. spellName .. " soon!")
    end
end

-- Boss yell/emote detection.
function RT.OnMechanicEmote(text)
    if not (AIP.db and AIP.db.mechanicAnnounce) then return end
    if not RT.InPveInstance() then return end
    if not text then return end
    local lower = text:lower()
    for pattern, msg in pairs(RT.BossEmotes) do
        if lower:find(pattern, 1, true) then
            if not mechThrottled("e:" .. pattern, 4) then
                RT.EmitMechanic(msg)
            end
            return
        end
    end
end

-- Target/focus boss health milestones (phase/execute awareness).
function RT.OnMechanicHealth(uId)
    if not (AIP.db and AIP.db.mechanicAnnounce) then return end
    if not RT.InPveInstance() then return end
    if uId ~= "target" and uId ~= "focus" then return end
    if not UnitExists(uId) or UnitIsDead(uId) or not UnitCanAttack("player", uId) then return end
    -- Boss-level only: skull level (-1) or worldboss/rareelite classification.
    -- 5-man dungeon bosses are plain "elite" at a numeric level, so also accept an
    -- at/above-level elite while inside a PvE instance (throttled per-GUID below).
    local lvl = UnitLevel(uId)
    local cls = UnitClassification(uId)
    local isBoss = (lvl == -1) or cls == "worldboss" or cls == "rareelite"
    if not isBoss and cls == "elite" and RT.InPveInstance() and (lvl or 0) >= (UnitLevel("player") or 80) then
        isBoss = true
    end
    if not isBoss then return end
    local maxHP = UnitHealthMax(uId)
    if not maxHP or maxHP == 0 then return end
    local pct = UnitHealth(uId) / maxHP * 100
    local guid = UnitGUID(uId)
    if not guid then return end
    RT.bossHpSeen[guid] = RT.bossHpSeen[guid] or {}
    local seen = RT.bossHpSeen[guid]
    local name = UnitName(uId) or "Boss"
    for _, th in ipairs({35, 20, 10}) do
        if pct <= th and not seen[th] then
            seen[th] = true
            RT.EmitMechanic(name .. " at " .. th .. "%!")
        end
    end
end

-- Raid health monitor (called on a throttle from the events OnUpdate).
function RT.CheckRaidHealth()
    if not (AIP.db and AIP.db.mechanicAnnounce) then return end
    if not RT.InPveInstance() then return end
    local n = GetNumRaidMembers() or 0
    if n < 5 then return end
    if not UnitAffectingCombat("player") then return end
    local low, alive = 0, 0
    for i = 1, n do
        local u = "raid" .. i
        if UnitExists(u) and not UnitIsDeadOrGhost(u) and UnitIsConnected(u) then
            alive = alive + 1
            local m = UnitHealthMax(u)
            if m and m > 0 and (UnitHealth(u) / m) <= 0.35 then low = low + 1 end
        end
    end
    if alive > 0 and low >= math.ceil(alive * 0.4) then
        local now = GetTime()
        if (now - (RT.lastRaidHealthWarn or 0)) > 15 then
            RT.lastRaidHealthWarn = now
            RT.EmitMechanic("Raid low - heal up / use cooldowns!")
        end
    end
end

-- Called on leaving combat (PLAYER_REGEN_ENABLED). The boss-ability recast timers
-- keep counting toward a "next cast" that will never happen once the boss is dead,
-- firing their ~5s pre-warnings after the fight - this stops that. Bloodlust/Sated
-- bars (not prefixed "t:") are left alone.
function RT.ClearMechanicState()
    if RT.timers then
        for key in pairs(RT.timers) do
            if tostring(key):find("^t:") then RT.timers[key] = nil end
        end
    end
    RT.mechLast = {}
    RT.bossHpSeen = {}
    RT.lastRaidHealthWarn = 0
end

-- ============================================================================
-- COUNTDOWN TIMER BARS  (Bloodlust + signature boss abilities)
-- A small, movable stack of shrinking bars. RT.StartTimer(key, label, seconds,
-- r,g,b[, prewarn]) starts/restarts a bar; a pre-warning is emitted ~5s out.
-- ============================================================================

local TIMER_BAR_W, TIMER_BAR_H, TIMER_MAX, TIMER_GAP = 230, 22, 7, 3
local TIMER_ICON_FALLBACK = "Interface\\Icons\\INV_Misc_PocketWatch_01"
RT.timers = {}  -- key -> {label, expire, duration, r, g, b, prewarn, warned, icon}

-- Compact, glanceable time text: "10:00" for >=1 min, whole seconds 10-59,
-- one decimal under 10s (so the final countdown reads clearly).
local function fmtTimer(s)
    if s >= 60 then
        return string.format("%d:%02d", math.floor(s / 60), math.floor(s % 60))
    elseif s >= 10 then
        return string.format("%d", math.floor(s + 0.5))
    end
    return string.format("%.1f", s)
end

function RT.CreateTimerAnchor()
    if RT.TimerAnchor then return RT.TimerAnchor end

    local f = CreateFrame("Frame", "AIPTimerAnchor", UIParent)
    f:SetSize(TIMER_BAR_W + TIMER_BAR_H, TIMER_BAR_H)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        if AIP.db then AIP.db.timerBarPos = {point = p, relPoint = rp, x = x, y = y} end
    end)

    local pos = AIP.db and AIP.db.timerBarPos
    f:ClearAllPoints()
    if pos then f:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or -320, pos.y or 120)
    else f:SetPoint("CENTER", UIParent, "CENTER", -320, 120) end

    local handle = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    handle:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 2, 3)
    handle:SetText("|cFF888888AIP Timers (drag)|r")
    f.handle = handle

    f.bars = {}

    -- Drive all active bars from one OnUpdate; hides itself when empty so it
    -- costs nothing while idle (StartTimer re-shows it).
    f:SetScript("OnUpdate", function(self, e)
        self.acc = (self.acc or 0) + e
        if self.acc < 0.04 then return end
        self.acc = 0
        local now = GetTime()

        local list = {}
        for key, t in pairs(RT.timers) do
            local rem = t.expire - now
            if rem <= 0 then
                RT.timers[key] = nil
            else
                list[#list + 1] = {key = key, t = t, rem = rem}
            end
        end
        table.sort(list, function(a, b) return a.rem < b.rem end)

        for i = 1, TIMER_MAX do
            local item = list[i]
            local bar = self.bars[i]
            if item then
                bar = RT.AcquireTimerBar(i)
                local t, rem = item.t, item.rem
                local frac = (t.duration > 0) and (rem / t.duration) or 0
                bar:SetMinMaxValues(0, t.duration)
                bar:SetValue(rem)
                bar:SetStatusBarColor(t.r, t.g, t.b)
                bar.icon:SetTexture(t.icon or TIMER_ICON_FALLBACK)
                bar.label:SetText(t.label)
                bar.time:SetText(fmtTimer(rem))

                -- Urgency: time text whitens -> yellow -> red as it runs out.
                if rem <= 5 then bar.time:SetTextColor(1, 0.2, 0.2)
                elseif rem <= 10 then bar.time:SetTextColor(1, 0.9, 0.2)
                else bar.time:SetTextColor(1, 1, 1) end

                -- Spark rides the leading edge of the fill.
                bar.spark:ClearAllPoints()
                bar.spark:SetPoint("CENTER", bar, "LEFT", frac * TIMER_BAR_W, 0)
                if frac > 0.02 and frac < 0.99 then bar.spark:Show() else bar.spark:Hide() end

                if t.prewarn and not t.warned and rem <= 5 then
                    t.warned = true
                    RT.EmitMechanic(t.prewarn)
                end
                bar:Show()
            elseif bar then
                bar:Hide()
            end
        end

        if #list == 0 then self:Hide() end
    end)

    RT.TimerAnchor = f
    return f
end

function RT.AcquireTimerBar(i)
    local f = RT.CreateTimerAnchor()
    local bar = f.bars[i]
    if not bar then
        bar = CreateFrame("StatusBar", nil, f)
        bar:SetSize(TIMER_BAR_W, TIMER_BAR_H)
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        -- Leave room for the icon on the left so bars line up under the handle.
        bar:SetPoint("TOPLEFT", f, "TOPLEFT", TIMER_BAR_H + 1, -(i - 1) * (TIMER_BAR_H + TIMER_GAP))

        local bg = bar:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetTexture(0, 0, 0, 0.65)
        bar:SetBackdrop({edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
        bar:SetBackdropBorderColor(0, 0, 0, 0.9)

        -- Square spell icon flush to the bar's left, just outside it.
        local icon = bar:CreateTexture(nil, "OVERLAY")
        icon:SetSize(TIMER_BAR_H, TIMER_BAR_H)
        icon:SetPoint("RIGHT", bar, "LEFT", -1, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)  -- trim the default icon border
        bar.icon = icon

        -- Spark glow on the leading edge.
        local spark = bar:CreateTexture(nil, "OVERLAY")
        spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
        spark:SetBlendMode("ADD")
        spark:SetSize(14, TIMER_BAR_H * 2.1)
        bar.spark = spark

        bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bar.label:SetPoint("LEFT", 5, 0)
        bar.label:SetPoint("RIGHT", bar, "RIGHT", -38, 0)
        bar.label:SetJustifyH("LEFT")
        bar.label:SetShadowOffset(1, -1); bar.label:SetShadowColor(0, 0, 0, 1)

        bar.time = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        bar.time:SetPoint("RIGHT", -4, 0)
        bar.time:SetShadowOffset(1, -1); bar.time:SetShadowColor(0, 0, 0, 1)

        f.bars[i] = bar
    end
    return bar
end

-- Remove every active timer bar and hide the anchor (used by /aip timertest
-- toggle and /aip cleartest; ClearMechanicState only drops the "t:" recast bars).
function RT.ClearAllTimers()
    RT.timers = {}
    if RT.TimerAnchor then RT.TimerAnchor:Hide() end
end

-- Start (or restart) a countdown bar. Gated by the mechanic-announcer toggle.
-- `icon` is optional; otherwise we try the spell's own icon, then a clock.
function RT.StartTimer(key, label, duration, r, g, b, prewarn, icon)
    -- NOT gated on mechanicAnnounce: the mechanic callers gate themselves before
    -- calling, while pull/break bars (DBM bridge) and /aip timertest must render
    -- regardless of the mechanic-announcer toggle.
    if not duration or duration <= 0 then return end
    if not icon then
        icon = select(3, GetSpellInfo(label))  -- nil for non-player spells; that's fine
    end
    RT.timers[key] = {
        label = label, expire = GetTime() + duration, duration = duration,
        r = r or 0.2, g = g or 0.6, b = b or 1, prewarn = prewarn, warned = false,
        icon = icon,
    }
    RT.CreateTimerAnchor():Show()
end

-- ============================================================================
-- /RW LOOT ANNOUNCE (reserved items)
-- ============================================================================

function RT.AnnounceReserved()
    local reserved = (AIP.db and AIP.db.reservedItems) or ""
    if reserved == "" then
        RT.Send("No reserved items set.", "RAID")
        return
    end
    RT.Send("=== Reserved Items (Soft Reserve) ===", "RAID_WARNING")
    for rawLine in reserved:gmatch("[^\r\n]+") do
        local itemLine = rawLine:gsub("^%s+", ""):gsub("%s+$", "")
        if itemLine ~= "" then
            RT.Send(itemLine, "RAID_WARNING")
        end
    end
end

-- ============================================================================
-- LOOT ITEMS (from the current raid session) + EXPIRATION
-- ============================================================================

-- Format remaining seconds as "1h 45m" / "12m" / "expired"
function RT.FormatRemaining(secs)
    if not secs or secs <= 0 then return "expired" end
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h > 0 then return h .. "h " .. m .. "m" end
    return m .. "m"
end

function RT.GetRollItems()
    local items = {}
    local now = time()
    local expire = RT.LOOT_EXPIRE_SECONDS
    local warn = RT.LOOT_WARN_SECONDS

    local session = AIP.RaidSession and AIP.RaidSession.GetCurrentSession and AIP.RaidSession.GetCurrentSession()
    if session and session.loot then
        for i = #session.loot, 1, -1 do
            local e = session.loot[i]
            local ts = e.timestamp or now
            local remaining = (ts + expire) - now
            if remaining > 0 then
                items[#items + 1] = {
                    key = "s" .. i,
                    name = e.itemName or "Unknown",
                    link = e.itemLink,
                    quality = e.itemQuality or 1,
                    timestamp = ts,
                    winner = e.winner,
                    remaining = remaining,
                    expiring = remaining <= warn,
                }
            end
        end
    end

    for i, m in ipairs(RT.manualItems) do
        local ts = m.timestamp or now
        local remaining = (ts + expire) - now
        items[#items + 1] = {
            key = "m" .. i,
            name = m.name or "Unknown",
            link = m.link,
            quality = m.quality or 1,
            timestamp = ts,
            winner = nil,
            remaining = remaining,
            expiring = remaining <= warn,
        }
    end

    return items
end

function RT.AddManualItem(text)
    if not text or text == "" then return end
    local link = text:match("|c%x+|Hitem:.-|h.-|h|r")
    local name, quality
    if link then
        name = link:match("%[(.-)%]") or link
        local _, _, q = GetItemInfo(link)
        quality = q
    else
        name = text:gsub("^%s+", ""):gsub("%s+$", "")
    end
    if name and name ~= "" then
        table.insert(RT.manualItems, { name = name, link = link, quality = quality or 1, timestamp = time() })
        if RT.RefreshRollWindow then RT.RefreshRollWindow() end
    end
end

-- Warn once per item when it crosses the expiry threshold
function RT.CheckExpirations()
    local items = RT.GetRollItems()
    for _, it in ipairs(items) do
        if it.expiring and not it.winner and not RT.warnedItems[it.key] then
            RT.warnedItems[it.key] = true
            AIP.Print("|cFFFF6060Loot warning:|r " .. (it.link or it.name) ..
                " expires in " .. RT.FormatRemaining(it.remaining) .. " (trade window).")
        end
    end
end
