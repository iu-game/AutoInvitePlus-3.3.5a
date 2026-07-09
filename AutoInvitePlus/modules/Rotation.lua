-- AutoInvite Plus - Rotation Advisor + Live DPS (the "become the best DPS" engine)
-- A Hekili-style next-ability suggester: per spec it evaluates a priority list
-- (APL) against live cooldowns / resources / procs / DoT timers and shows the
-- single best button to press, on a movable on-screen icon, with a LIVE DPS
-- readout underneath (computed from your own combat-log damage). Advisory only -
-- it never casts (that's protected on 3.3.5a and disallowed).
--
-- APLs are the 3.3.5a raiding-consensus priorities. Not sim-perfect, but they
-- encode the "don't drop your DoT / use your proc / spend at 5 CP / execute
-- under 20%" decisions that separate good play from bad. Easy to extend.

local AIP = AutoInvitePlus
if not AIP then return end
AIP.Rotation = AIP.Rotation or {}
local R = AIP.Rotation

local GT = GetTime

-- ============================================================================
-- Live game-state helpers (all read-only, 3.3.5a-safe)
-- ============================================================================
local function ready(spell)              -- off cooldown (GCD-agnostic ~ready)
    local s, d = GetSpellCooldown(spell)
    if s == nil then return false end
    if s == 0 then return true end
    return (s + d - GT()) <= 0.3
end
local function usable(spell)             -- known + affordable
    local u = IsUsableSpell(spell)
    return u and true or false
end
local function pbuff(name)               -- player buff: remaining secs, stacks
    for i = 1, 40 do
        local n, _, _, cnt, _, _, exp = UnitBuff("player", i)
        if not n then break end
        if n == name then return ((exp or 0) - GT()), (cnt or 0) end
    end
    return nil
end
local function myDebuff(name)            -- MY debuff on target: remaining secs, stacks
    if not UnitExists("target") then return nil end
    for i = 1, 40 do
        local n, _, _, cnt, _, _, exp, caster = UnitDebuff("target", i)
        if not n then break end
        if n == name and caster == "player" then return ((exp or 0) - GT()), (cnt or 0) end
    end
    return nil
end
local function power(t) return UnitPower and UnitPower("player", t) or 0 end
local function energy() return power(3) end
local function rage() return power(1) end
local function runic() return power(6) end
local function combo() return GetComboPoints("player", "target") end
local function targetHP()
    if not UnitExists("target") then return 100 end
    local m = UnitHealthMax("target"); if not m or m == 0 then return 100 end
    return UnitHealth("target") / m * 100
end

-- A rule shorthand: return the first spell whose predicate is true AND is ready.
-- Each APL's pick() just returns a spell name (or nil).

-- ============================================================================
-- APLs  (APLS[class][primaryTree] = { label, priority = {lines}, pick = fn })
-- ============================================================================
local APLS = {
    ROGUE = {
        [2] = { label = "Combat Rogue",
            priority = { "Slice and Dice (keep up, 1+ CP)", "Rupture at 5 CP", "Killing Spree", "Sinister Strike (build)" },
            pick = function()
                if (pbuff("Slice and Dice") or 0) < 2 and combo() >= 1 and ready("Slice and Dice") then return "Slice and Dice" end
                if combo() >= 5 and (myDebuff("Rupture") or 0) < 2 and ready("Rupture") then return "Rupture" end
                if ready("Killing Spree") then return "Killing Spree" end
                if energy() >= 45 and ready("Sinister Strike") then return "Sinister Strike" end
            end },
        [1] = { label = "Assassination Rogue",
            priority = { "Hunger for Blood (keep up)", "Slice and Dice (1+ CP)", "Rupture at 4+ CP", "Envenom at 4+ CP", "Mutilate (build)" },
            pick = function()
                if (pbuff("Hunger for Blood") or 0) < 3 and ready("Hunger for Blood") then return "Hunger for Blood" end
                if (pbuff("Slice and Dice") or 0) < 2 and combo() >= 1 then return "Slice and Dice" end
                if combo() >= 4 and (myDebuff("Rupture") or 0) < 2 then return "Rupture" end
                if combo() >= 4 and energy() >= 35 then return "Envenom" end
                if energy() >= 60 then return "Mutilate" end
            end },
    },
    HUNTER = {
        [3] = { label = "Survival Hunter",
            priority = { "Kill Shot (<20%)", "Explosive Shot", "Black Arrow", "Serpent Sting (keep up)", "Steady Shot (filler)" },
            pick = function()
                if targetHP() <= 20 and ready("Kill Shot") then return "Kill Shot" end
                if ready("Explosive Shot") then return "Explosive Shot" end
                if ready("Black Arrow") then return "Black Arrow" end
                if not myDebuff("Serpent Sting") and ready("Serpent Sting") then return "Serpent Sting" end
                return "Steady Shot"
            end },
        [2] = { label = "Marksmanship Hunter",
            priority = { "Kill Shot (<20%)", "Chimera Shot", "Serpent Sting (keep up)", "Aimed Shot", "Steady Shot (filler)" },
            pick = function()
                if targetHP() <= 20 and ready("Kill Shot") then return "Kill Shot" end
                if ready("Chimera Shot") then return "Chimera Shot" end
                if not myDebuff("Serpent Sting") and ready("Serpent Sting") then return "Serpent Sting" end
                if ready("Aimed Shot") then return "Aimed Shot" end
                return "Steady Shot"
            end },
        [1] = { label = "Beast Mastery Hunter",
            priority = { "Kill Shot (<20%)", "Serpent Sting (keep up)", "Arcane Shot", "Steady Shot (filler)" },
            pick = function()
                if targetHP() <= 20 and ready("Kill Shot") then return "Kill Shot" end
                if not myDebuff("Serpent Sting") and ready("Serpent Sting") then return "Serpent Sting" end
                if ready("Arcane Shot") then return "Arcane Shot" end
                return "Steady Shot"
            end },
    },
    DRUID = {
        [2] = { label = "Feral (Cat)",
            priority = { "Faerie Fire (armor)", "Mangle (keep bleed buff)", "Rake (keep up)", "Savage Roar (1+ CP)", "Rip at 5 CP", "Shred (build)" },
            pick = function()
                if not myDebuff("Faerie Fire (Feral)") and ready("Faerie Fire (Feral)") then return "Faerie Fire (Feral)" end
                if (myDebuff("Mangle (Cat)") or 0) < 1 and ready("Mangle (Cat)") then return "Mangle (Cat)" end
                if (myDebuff("Rake") or 0) < 1 and energy() >= 35 then return "Rake" end
                if combo() >= 1 and (pbuff("Savage Roar") or 0) < 2 then return "Savage Roar" end
                if combo() >= 5 and (myDebuff("Rip") or 0) < 2 then return "Rip" end
                if energy() >= 60 then return "Shred" end
            end },
    },
    SHAMAN = {
        [2] = { label = "Enhancement Shaman",
            priority = { "Lightning Bolt (5 Maelstrom)", "Stormstrike", "Lava Lash", "Flame Shock (keep up)", "Earth Shock", "Fire Nova" },
            pick = function()
                local _, ms = pbuff("Maelstrom Weapon")
                if (ms or 0) >= 5 then return "Lightning Bolt" end
                if ready("Stormstrike") then return "Stormstrike" end
                if ready("Lava Lash") then return "Lava Lash" end
                if (myDebuff("Flame Shock") or 0) < 2 and ready("Flame Shock") then return "Flame Shock" end
                if ready("Earth Shock") then return "Earth Shock" end
            end },
    },
    PALADIN = {
        [3] = { label = "Retribution Paladin",
            priority = { "Judgement", "Crusader Strike", "Divine Storm", "Exorcism (Art of War)", "Consecration", "Holy Wrath" },
            pick = function()
                if ready("Judgement of Wisdom") then return "Judgement of Wisdom" end
                if ready("Crusader Strike") then return "Crusader Strike" end
                if ready("Divine Storm") then return "Divine Storm" end
                if pbuff("The Art of War") and ready("Exorcism") then return "Exorcism" end
                if ready("Consecration") then return "Consecration" end
                if ready("Holy Wrath") then return "Holy Wrath" end
            end },
    },
    WARRIOR = {
        [2] = { label = "Fury Warrior",
            priority = { "Bloodthirst", "Whirlwind", "Slam! (proc)", "Heroic Strike (rage dump >50)" },
            pick = function()
                if ready("Bloodthirst") then return "Bloodthirst" end
                if ready("Whirlwind") then return "Whirlwind" end
                if pbuff("Bloodsurge") then return "Slam" end
                if rage() > 50 then return "Heroic Strike" end
            end },
        [1] = { label = "Arms Warrior",
            priority = { "Rend (keep up)", "Mortal Strike", "Overpower (proc)", "Execute (<20%)", "Slam" },
            pick = function()
                if targetHP() <= 20 and ready("Execute") then return "Execute" end
                if (myDebuff("Rend") or 0) < 2 and ready("Rend") then return "Rend" end
                if ready("Mortal Strike") then return "Mortal Strike" end
                if pbuff("Taste for Blood") and ready("Overpower") then return "Overpower" end
                if rage() >= 30 then return "Slam" end
            end },
    },
    DEATHKNIGHT = {
        [3] = { label = "Unholy DK (2H)",
            priority = { "Icy Touch (Frost Fever)", "Plague Strike (Blood Plague)", "Scourge Strike", "Death and Decay", "Death Coil (RP dump)" },
            pick = function()
                if (myDebuff("Frost Fever") or 0) < 1 and ready("Icy Touch") then return "Icy Touch" end
                if (myDebuff("Blood Plague") or 0) < 1 and ready("Plague Strike") then return "Plague Strike" end
                if ready("Scourge Strike") then return "Scourge Strike" end
                if ready("Death and Decay") then return "Death and Decay" end
                if runic() >= 40 then return "Death Coil" end
            end },
    },
    MAGE = {
        [2] = { label = "Fire Mage",
            priority = { "Pyroblast (Hot Streak!)", "Living Bomb (keep up)", "Fireball (filler)" },
            pick = function()
                if pbuff("Hot Streak") then return "Pyroblast" end
                if (myDebuff("Living Bomb") or 0) < 2 and ready("Living Bomb") then return "Living Bomb" end
                return "Fireball"
            end },
    },
    WARLOCK = {
        [1] = { label = "Affliction Warlock",
            priority = { "Haunt", "Corruption (keep up)", "Unstable Affliction (keep up)", "Curse of Agony (keep up)", "Shadow Bolt (filler)" },
            pick = function()
                if ready("Haunt") then return "Haunt" end
                if (myDebuff("Corruption") or 0) < 2 then return "Corruption" end
                if (myDebuff("Unstable Affliction") or 0) < 2 then return "Unstable Affliction" end
                if (myDebuff("Curse of Agony") or 0) < 2 then return "Curse of Agony" end
                if targetHP() <= 25 then return "Drain Soul" end
                return "Shadow Bolt"
            end },
    },
    PRIEST = {
        [3] = { label = "Shadow Priest",
            priority = { "Vampiric Touch (keep up)", "Devouring Plague (keep up)", "Shadow Word: Pain (keep up)", "Mind Blast", "Mind Flay (filler)" },
            pick = function()
                if (myDebuff("Vampiric Touch") or 0) < 2 and ready("Vampiric Touch") then return "Vampiric Touch" end
                if (myDebuff("Devouring Plague") or 0) < 2 and ready("Devouring Plague") then return "Devouring Plague" end
                if (myDebuff("Shadow Word: Pain") or 0) < 2 then return "Shadow Word: Pain" end
                if ready("Mind Blast") then return "Mind Blast" end
                return "Mind Flay"
            end },
    },
}

-- Remaining specs so EVERY class + tree is covered (healers/tanks get a
-- priority/triage list rather than a strict DPS rotation).
APLS.ROGUE[3] = { label = "Subtlety Rogue",
    priority = { "Slice and Dice (keep up)", "Rupture at 5 CP", "Hemorrhage (keep debuff)", "Backstab (build, behind)" },
    pick = function()
        if (pbuff("Slice and Dice") or 0) < 2 and combo() >= 1 then return "Slice and Dice" end
        if combo() >= 5 and (myDebuff("Rupture") or 0) < 2 then return "Rupture" end
        if (myDebuff("Hemorrhage") or 0) < 2 and ready("Hemorrhage") then return "Hemorrhage" end
        if energy() >= 60 then return "Backstab" end
    end }
APLS.DRUID[1] = { label = "Balance Druid",
    priority = { "Insect Swarm + Moonfire (keep up)", "Starfall (on CD)", "Wrath/Starfire per Eclipse" },
    pick = function()
        if (myDebuff("Insect Swarm") or 0) < 2 and ready("Insect Swarm") then return "Insect Swarm" end
        if (myDebuff("Moonfire") or 0) < 2 and ready("Moonfire") then return "Moonfire" end
        if ready("Starfall") then return "Starfall" end
        if pbuff("Eclipse (Solar)") then return "Wrath" end
        return "Starfire"
    end }
APLS.DRUID[3] = { label = "Restoration Druid (heal)",
    priority = { "Rejuvenation on tank/spread", "Wild Growth (on CD, groups)", "Swiftmend emergencies", "Nourish the low target" },
    pick = function()
        if ready("Wild Growth") then return "Wild Growth" end
        if ready("Swiftmend") then return "Swiftmend" end
        return "Nourish"
    end }
APLS.SHAMAN[1] = { label = "Elemental Shaman",
    priority = { "Flame Shock (keep up)", "Lava Burst (on CD)", "Lightning Bolt (filler)" },
    pick = function()
        if (myDebuff("Flame Shock") or 0) < 2 and ready("Flame Shock") then return "Flame Shock" end
        if ready("Lava Burst") then return "Lava Burst" end
        return "Lightning Bolt"
    end }
APLS.SHAMAN[3] = { label = "Restoration Shaman (heal)",
    priority = { "Riptide (on CD)", "Earth Shield on tank", "Chain Heal (grouped)", "Healing Wave (tank)" },
    pick = function()
        if ready("Riptide") then return "Riptide" end
        return "Chain Heal"
    end }
APLS.PALADIN[1] = { label = "Holy Paladin (heal)",
    priority = { "Beacon of Light on the tank", "Holy Shock (on CD)", "Holy Light (main heal)", "Flash of Light (fast)" },
    pick = function()
        if (pbuff("Beacon of Light") or 0) < 3 and ready("Beacon of Light") then return "Beacon of Light" end
        if ready("Holy Shock") then return "Holy Shock" end
        return "Holy Light"
    end }
APLS.PALADIN[2] = { label = "Protection Paladin (tank)",
    priority = { "Holy Shield (keep up)", "Shield of Righteousness", "Judgement", "Hammer of the Righteous", "Consecration" },
    pick = function()
        if (pbuff("Holy Shield") or 0) < 1 and ready("Holy Shield") then return "Holy Shield" end
        if ready("Shield of Righteousness") then return "Shield of Righteousness" end
        if ready("Judgement of Wisdom") then return "Judgement of Wisdom" end
        if ready("Hammer of the Righteous") then return "Hammer of the Righteous" end
        if ready("Consecration") then return "Consecration" end
    end }
APLS.WARRIOR[3] = { label = "Protection Warrior (tank)",
    priority = { "Shield Slam", "Revenge", "Devastate (keep Sunder x5)", "Shield Block up" },
    pick = function()
        if ready("Shield Slam") then return "Shield Slam" end
        if ready("Revenge") then return "Revenge" end
        return "Devastate"
    end }
APLS.DEATHKNIGHT[1] = { label = "Blood DK",
    priority = { "Diseases up (Icy Touch/Plague Strike)", "Heart Strike", "Death Strike", "Death Coil (RP dump)" },
    pick = function()
        if (myDebuff("Frost Fever") or 0) < 1 and ready("Icy Touch") then return "Icy Touch" end
        if (myDebuff("Blood Plague") or 0) < 1 and ready("Plague Strike") then return "Plague Strike" end
        if ready("Heart Strike") then return "Heart Strike" end
        if ready("Death Strike") then return "Death Strike" end
        if runic() >= 40 then return "Death Coil" end
    end }
APLS.DEATHKNIGHT[2] = { label = "Frost DK",
    priority = { "Diseases up (Icy Touch/Plague Strike)", "Obliterate", "Frost Strike (RP dump)", "Blood Strike (build)" },
    pick = function()
        if (myDebuff("Frost Fever") or 0) < 1 and ready("Icy Touch") then return "Icy Touch" end
        if (myDebuff("Blood Plague") or 0) < 1 and ready("Plague Strike") then return "Plague Strike" end
        if ready("Obliterate") then return "Obliterate" end
        if runic() >= 40 then return "Frost Strike" end
        if ready("Blood Strike") then return "Blood Strike" end
    end }
APLS.MAGE[1] = { label = "Arcane Mage",
    priority = { "Arcane Blast (stack) then Missiles", "Arcane Missiles on Missile Barrage", "Evocation for mana" },
    pick = function()
        if pbuff("Missile Barrage") then return "Arcane Missiles" end
        return "Arcane Blast"
    end }
APLS.MAGE[3] = { label = "Frost Mage",
    priority = { "Ice Lance on Fingers of Frost", "Deep Freeze (on CD)", "Frostbolt (filler)" },
    pick = function()
        if pbuff("Fingers of Frost") then return "Ice Lance" end
        if ready("Deep Freeze") then return "Deep Freeze" end
        return "Frostbolt"
    end }
APLS.WARLOCK[2] = { label = "Demonology Warlock",
    priority = { "Immolate (keep up)", "Corruption (keep up)", "Soul Fire on Molten Core", "Shadow Bolt (filler)" },
    pick = function()
        if (myDebuff("Immolate") or 0) < 2 then return "Immolate" end
        if (myDebuff("Corruption") or 0) < 2 then return "Corruption" end
        if pbuff("Molten Core") then return "Soul Fire" end
        return "Shadow Bolt"
    end }
APLS.WARLOCK[3] = { label = "Destruction Warlock",
    priority = { "Immolate (keep up)", "Conflagrate (on CD)", "Chaos Bolt (on CD)", "Incinerate (filler)" },
    pick = function()
        if (myDebuff("Immolate") or 0) < 2 then return "Immolate" end
        if ready("Conflagrate") then return "Conflagrate" end
        if ready("Chaos Bolt") then return "Chaos Bolt" end
        return "Incinerate"
    end }
APLS.PRIEST[1] = { label = "Discipline Priest (heal)",
    priority = { "Power Word: Shield (Rapture)", "Penance (on CD)", "Prayer of Mending up", "Flash Heal (fast)" },
    pick = function()
        if ready("Penance") then return "Penance" end
        if ready("Power Word: Shield") then return "Power Word: Shield" end
        return "Flash Heal"
    end }
APLS.PRIEST[2] = { label = "Holy Priest (heal)",
    priority = { "Renew/CoH on the raid", "Circle of Healing (on CD)", "Prayer of Healing (grouped)", "Flash/Greater Heal (single)" },
    pick = function()
        if ready("Circle of Healing") then return "Circle of Healing" end
        return "Flash Heal"
    end }

-- Current spec's APL (by class + primary talent tree).
function R.CurrentAPL()
    local _, class = UnitClass("player")
    local best, bp = 1, -1
    if GetNumTalentTabs then
        for t = 1, (GetNumTalentTabs() or 3) do
            local p = select(3, GetTalentTabInfo(t)) or 0
            if p > bp then bp, best = p, t end
        end
    end
    local byClass = APLS[class]
    return byClass and byClass[best], class, best
end

-- ============================================================================
-- Live DPS (own damage from the combat log)
-- ============================================================================
R.dmg = 0
R.combatStart = 0
R.lastDPS = 0

local function resetDPS() R.dmg = 0; R.combatStart = GT() end
function R.DPS()
    if R.combatStart == 0 then return R.lastDPS end
    local dur = GT() - R.combatStart
    if dur < 1 then return 0 end
    return R.dmg / dur
end

local function onCLEU(...)
    local sub = select(2, ...)
    local srcGUID = select(3, ...)
    if srcGUID ~= UnitGUID("player") then return end
    local amt
    if sub == "SWING_DAMAGE" then amt = select(9, ...)
    elseif sub == "SPELL_DAMAGE" or sub == "SPELL_PERIODIC_DAMAGE" or sub == "RANGE_DAMAGE" then amt = select(12, ...)
    elseif sub == "DAMAGE_SHIELD" or sub == "SPELL_BUILDING_DAMAGE" then amt = select(12, ...) end
    if amt then R.dmg = R.dmg + amt end
end

-- ============================================================================
-- Instant-cast / free-cast PROC buffs per spec: buff -> the ability it unlocks.
-- When active, the overlay pulses a proc icon and the proc jumps the queue.
-- Optional 3rd field = minimum stacks required (e.g. Maelstrom Weapon 5).
-- ============================================================================
local PROCS = {
    MAGE = {
        [1] = { { "Missile Barrage", "Arcane Missiles" } },
        [2] = { { "Hot Streak", "Pyroblast" } },
        [3] = { { "Fingers of Frost", "Ice Lance" }, { "Brain Freeze", "Frostfire Bolt" } },
    },
    SHAMAN = { [2] = { { "Maelstrom Weapon", "Lightning Bolt", 5 } } },
    WARLOCK = {
        [1] = { { "Nightfall", "Shadow Bolt" }, { "Shadow Trance", "Shadow Bolt" } },
        [2] = { { "Molten Core", "Soul Fire" }, { "Decimation", "Soul Fire" } },
        [3] = { { "Backdraft", "Incinerate" }, { "Backlash", "Incinerate" } },
    },
    PALADIN = { [3] = { { "The Art of War", "Exorcism" } } },
    WARRIOR = { [2] = { { "Bloodsurge", "Slam" } }, [1] = { { "Sudden Death", "Execute" } } },
    DEATHKNIGHT = { [1] = { { "Sudden Doom", "Death Coil" } }, [3] = { { "Sudden Doom", "Death Coil" } } },
    HUNTER = { [3] = { { "Lock and Load", "Explosive Shot" } } },
    DRUID = { [1] = { { "Eclipse (Lunar)", "Starfire" }, { "Eclipse (Solar)", "Wrath" } } },
    PRIEST = { [2] = { { "Surge of Light", "Flash Heal" } } },
}

-- Active proc for the current spec: returns buffName, castSpell, iconTexture.
function R.ActiveProc()
    local _, class = UnitClass("player")
    local best, bp = 1, -1
    if GetNumTalentTabs then
        for t = 1, (GetNumTalentTabs() or 3) do
            local p = select(3, GetTalentTabInfo(t)) or 0
            if p > bp then bp, best = p, t end
        end
    end
    local list = PROCS[class] and PROCS[class][best]
    if not list then return nil end
    for _, pr in ipairs(list) do
        local rem, stacks = pbuff(pr[1])
        if rem and (stacks or 1) >= (pr[3] or 1) then
            local cast = pr[2]
            local _, _, tex = GetSpellInfo(cast)
            return pr[1], cast, tex
        end
    end
    return nil
end

-- ============================================================================
-- Major DPS cooldowns to POP, per spec. Shown bright+glow when READY in the
-- overlay's cooldown bar, dimmed with a countdown when on CD. "Should be used"
-- is approximated as "off cooldown"; the player's DPS racial is appended.
-- ============================================================================
local CDS = {
    ROGUE = { [1] = { "Cold Blood" }, [2] = { "Adrenaline Rush", "Killing Spree", "Blade Flurry" }, [3] = { "Shadow Dance", "Preparation" } },
    HUNTER = { [1] = { "Bestial Wrath", "Rapid Fire", "Readiness" }, [2] = { "Rapid Fire", "Readiness" }, [3] = { "Rapid Fire", "Readiness" } },
    DRUID = { [1] = { "Force of Nature", "Starfall" }, [2] = { "Berserk" } },
    SHAMAN = { [1] = { "Elemental Mastery", "Fire Elemental Totem" }, [2] = { "Feral Spirit", "Fire Elemental Totem" } },
    PALADIN = { [1] = { "Avenging Wrath" }, [2] = { "Avenging Wrath" }, [3] = { "Avenging Wrath" } },
    WARRIOR = { [1] = { "Recklessness", "Bladestorm", "Sweeping Strikes" }, [2] = { "Recklessness", "Death Wish" }, [3] = { "Recklessness" } },
    DEATHKNIGHT = { [1] = { "Dancing Rune Weapon", "Empower Rune Weapon" }, [2] = { "Empower Rune Weapon", "Unbreakable Armor" }, [3] = { "Summon Gargoyle", "Unholy Frenzy", "Empower Rune Weapon" } },
    MAGE = { [1] = { "Arcane Power", "Presence of Mind", "Mirror Image" }, [2] = { "Combustion", "Mirror Image" }, [3] = { "Icy Veins", "Cold Snap", "Mirror Image" } },
    WARLOCK = { [2] = { "Metamorphosis", "Demonic Empowerment" } },  -- Aff/Destro have no intrinsic burst CD
    PRIEST = { [3] = { "Shadowfiend" } },
}
local RACIAL = { Troll = "Berserking", Orc = "Blood Fury" }

local function treeIdx()
    local best, bp = 1, -1
    if GetNumTalentTabs then
        for t = 1, (GetNumTalentTabs() or 3) do
            local p = select(3, GetTalentTabInfo(t)) or 0
            if p > bp then bp, best = p, t end
        end
    end
    return best
end

-- All active instant-cast procs (for the INSTANT bar).
function R.ActiveProcs()
    local _, class = UnitClass("player")
    local out = {}
    local sp = PROCS[class] and PROCS[class][treeIdx()]
    if sp then
        for _, pr in ipairs(sp) do
            local rem, stacks = pbuff(pr[1])
            if rem and (stacks or 1) >= (pr[3] or 1) then
                local _, _, tex = GetSpellInfo(pr[2])
                out[#out + 1] = { buff = pr[1], cast = pr[2], tex = tex }
            end
        end
    end
    return out
end

-- The spec's major DPS cooldowns (+ racial) with ready/remaining state.
function R.SpecCDs()
    local _, class = UnitClass("player")
    local names = {}
    for _, n in ipairs((CDS[class] and CDS[class][treeIdx()]) or {}) do names[#names + 1] = n end
    local _, race = UnitRace("player")
    if race and RACIAL[race] then names[#names + 1] = RACIAL[race] end
    local out = {}
    for _, n in ipairs(names) do
        local s, d = GetSpellCooldown(n)
        local _, _, tex = GetSpellInfo(n)
        if s ~= nil and tex then
            local ready = (d or 0) <= 1.5
            out[#out + 1] = { name = n, tex = tex, ready = ready, remain = ready and 0 or (s + d - GT()) }
        end
    end
    return out
end

-- The DoTs/maintained buffs the current spec must keep up, with live remaining
-- time on the target (or self). Only counts an aura the PLAYER applied. Returns
-- { name, tex, remain, active, dur } so the overlay can warn when one drops.
function R.SpecDoTs()
    local SG = AIP.SpecGuides
    local key = SG and SG.KeyFor and SG.KeyFor()
    local list = key and SG.DoTs and SG.DoTs[key]
    if not list then return {} end
    local out = {}
    for _, d in ipairs(list) do
        local name, dur, unit = d[1], d[2], d[3] or "target"
        local tex, remain = nil, 0
        if UnitExists(unit) then
            for i = 1, 40 do
                local aName, _, aTex, _, _, _, expires, caster
                if unit == "player" then aName, _, aTex, _, _, _, expires, caster = UnitBuff(unit, i)
                else aName, _, aTex, _, _, _, expires, caster = UnitDebuff(unit, i) end
                if not aName then break end
                if aName == name and (unit == "player" or caster == "player") then
                    tex = aTex
                    remain = expires and math.max(0, expires - GetTime()) or 0
                    break
                end
            end
        end
        if not tex then local _, _, t = GetSpellInfo(name); tex = t end
        out[#out + 1] = { name = name, tex = tex, remain = remain, active = remain > 0, dur = dur, unit = unit }
    end
    return out
end

-- ============================================================================
-- On-screen overlay: recommended icon + DOTS bar + INSTANT bar + COOLDOWNS + DPS
-- ============================================================================
local function fmtDPS(n)
    if n >= 1000 then return string.format("%.1fk dps", n / 1000) end
    return string.format("%.0f dps", n)
end

-- A pooled 24px icon in a horizontal bar (with a glow ring + a text overlay).
local function barIcon(bar, pool, i)
    local ic = pool[i]
    if not ic then
        ic = CreateFrame("Frame", nil, bar)
        ic:SetSize(24, 24); ic:SetPoint("LEFT", (i - 1) * 28, 0)
        ic.glow = ic:CreateTexture(nil, "BACKGROUND")
        ic.glow:SetPoint("CENTER"); ic.glow:SetSize(40, 40)
        ic.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border"); ic.glow:SetBlendMode("ADD")
        ic.tex = ic:CreateTexture(nil, "ARTWORK")
        ic.tex:SetAllPoints(); ic.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        ic.txt = ic:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall"); ic.txt:SetPoint("CENTER")
        pool[i] = ic
    end
    return ic
end

function R.CreateOverlay()
    if R.frame then return R.frame end
    local f = CreateFrame("Frame", "AIPRotationOverlay", UIParent)
    f:SetSize(210, 172)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        if AIP.db then AIP.db.rotationPos = { point = p, relPoint = rp, x = x, y = y } end
    end)
    local pos = AIP.db and AIP.db.rotationPos
    f:ClearAllPoints()
    if pos then f:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or -150)
    else f:SetPoint("CENTER", UIParent, "CENTER", 0, -150) end

    f:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.02, 0.02, 0.05, 0.86); f:SetBackdropBorderColor(0.35, 0.35, 0.42, 0.95)

    -- Title / drag strip: spec name (left) + live DPS (right).
    local title = f:CreateTexture(nil, "ARTWORK")
    title:SetPoint("TOPLEFT", 5, -5); title:SetPoint("TOPRIGHT", -5, -5); title:SetHeight(18)
    title:SetTexture(0.16, 0.16, 0.24, 0.95)
    local specName = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    specName:SetPoint("LEFT", title, "LEFT", 6, 0); specName:SetText("|cffffd100Rotation|r"); f.specName = specName
    local dps = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dps:SetPoint("RIGHT", title, "RIGHT", -6, 0); dps:SetTextColor(0.4, 1, 0.4); f.dps = dps

    -- NEXT block: the hero element - large icon + the ability to press.
    local main = CreateFrame("Frame", nil, f)
    main:SetSize(48, 48); main:SetPoint("TOPLEFT", 10, -28)
    main:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    main:SetBackdropBorderColor(0.85, 0.72, 0.2, 1)
    local glow = main:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("CENTER"); glow:SetSize(78, 78)
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border"); glow:SetBlendMode("ADD"); glow:SetVertexColor(1, 0.85, 0.2)
    f.glow = glow
    local icon = main:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2); icon:SetPoint("BOTTOMRIGHT", -2, 2); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.icon = icon
    local nextLbl = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    nextLbl:SetPoint("TOPLEFT", main, "TOPRIGHT", 8, -1); nextLbl:SetText("|cff888888NEXT|r")
    local name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("TOPLEFT", main, "TOPRIGHT", 8, -15); name:SetPoint("RIGHT", -6, 0)
    name:SetJustifyH("LEFT"); name:SetHeight(32); f.name = name

    -- Inline label + icon-strip rows (label left, icons right), tinted per type.
    local function makeRow(y, labelText, r, g, b)
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT", 6, y + 2); bg:SetPoint("TOPRIGHT", -6, y + 2); bg:SetHeight(26)
        bg:SetTexture(r, g, b, 0.22)
        local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        lbl:SetPoint("TOPLEFT", 10, y - 6); lbl:SetText(labelText)
        local bar = CreateFrame("Frame", nil, f); bar:SetPoint("TOPLEFT", 54, y); bar:SetSize(150, 24)
        return bar
    end
    f.dotBar, f.dotIcons = makeRow(-84, "|cff66bbffDoTs|r", 0.12, 0.20, 0.44), {}
    f.procBar, f.procIcons = makeRow(-112, "|cff55ff55Free|r", 0.12, 0.35, 0.14), {}
    f.cdBar, f.cdIcons = makeRow(-140, "|cffffcc55CDs|r", 0.35, 0.28, 0.10), {}

    f.acc = 0
    f:SetScript("OnUpdate", function(self, e)
        local a = 0.5 + 0.4 * math.sin(GetTime() * 7)
        for _, pi in ipairs(self.procIcons) do if pi:IsShown() then pi.glow:SetAlpha(a) end end
        for _, di in ipairs(self.dotIcons) do if di:IsShown() and di.glow:IsShown() then di.glow:SetAlpha(a) end end
        self.acc = self.acc + e
        if self.acc < 0.1 then return end
        self.acc = 0
        R.Tick()
    end)
    R.frame = f
    return f
end

-- Evaluate the APL (proc-aware) + refresh both icon bars.
function R.Tick()
    if not (AIP.db and AIP.db.rotationHelper) then if R.frame then R.frame:Hide() end return end
    local f = R.CreateOverlay()
    f.dps:SetText(fmtDPS(R.DPS()))
    if f.specName then local a = R.CurrentAPL(); f.specName:SetText("|cffffd100" .. (a and a.label or "Rotation") .. "|r") end

    -- DOTS bar: seconds left on each maintained DoT; desaturated + red-pulsing "!"
    -- the moment one drops, so you never let uptime lapse.
    local dots = R.SpecDoTs()
    local haveTgt = UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target")
    for _, ic in ipairs(f.dotIcons) do ic:Hide() end
    for i, d in ipairs(dots) do
        local ic = barIcon(f.dotBar, f.dotIcons, i)
        ic.tex:SetTexture(d.tex or "Interface\\Icons\\INV_Misc_QuestionMark")
        local down = (not d.active) and (d.unit == "player" or haveTgt)
        if down then
            if ic.tex.SetDesaturated then ic.tex:SetDesaturated(true) end
            ic.glow:SetVertexColor(1, 0.2, 0.2); ic.glow:SetAlpha(0.9); ic.glow:Show()
            ic.txt:SetText("!"); ic.txt:SetTextColor(1, 0.35, 0.35)
        else
            if ic.tex.SetDesaturated then ic.tex:SetDesaturated(false) end
            ic.glow:Hide()
            ic.txt:SetText(d.active and tostring(math.floor(d.remain)) or "")
            if d.remain <= 4 then ic.txt:SetTextColor(1, 0.6, 0.2) else ic.txt:SetTextColor(0.6, 1, 0.6) end
        end
        ic:Show()
    end

    -- INSTANT bar: one pulsing green icon per active instant-cast proc
    local procs = R.ActiveProcs()
    for _, ic in ipairs(f.procIcons) do ic:Hide() end
    for i, p in ipairs(procs) do
        local ic = barIcon(f.procBar, f.procIcons, i)
        ic.tex:SetTexture(p.tex or "Interface\\Icons\\INV_Misc_QuestionMark")
        if ic.tex.SetDesaturated then ic.tex:SetDesaturated(false) end
        ic.glow:SetVertexColor(0.2, 1, 0.4); ic.glow:Show(); ic.txt:SetText("")
        ic:Show()
    end

    -- COOLDOWNS bar: bright+glow when ready, dimmed with a countdown when on CD
    local cds = R.SpecCDs()
    for _, ic in ipairs(f.cdIcons) do ic:Hide() end
    for i, c in ipairs(cds) do
        local ic = barIcon(f.cdBar, f.cdIcons, i)
        ic.tex:SetTexture(c.tex)
        if c.ready then
            if ic.tex.SetDesaturated then ic.tex:SetDesaturated(false) end
            ic.glow:SetVertexColor(1, 0.85, 0.2); ic.glow:SetAlpha(0.9); ic.glow:Show(); ic.txt:SetText("")
        else
            if ic.tex.SetDesaturated then ic.tex:SetDesaturated(true) end
            ic.glow:Hide()
            ic.txt:SetText(c.remain >= 60 and (math.floor(c.remain / 60) .. "m") or tostring(math.floor(c.remain)))
        end
        ic:Show()
    end

    -- main recommended ability (a live instant-cast proc jumps the queue)
    local procBuff, procCast = R.ActiveProc()
    local inCombat = UnitAffectingCombat("player")
    local hasTarget = UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target")
    if not (inCombat and hasTarget) then
        f.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        f.name:SetText("|cff888888(waiting)|r"); f.glow:Hide(); f:Show()
        return
    end
    local apl = R.CurrentAPL()
    if not apl then
        f.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        f.name:SetText("|cffaaaaaano APL for spec|r"); f.glow:Hide(); f:Show()
        return
    end
    local isProc = procBuff and procCast
    local spell = isProc or apl.pick()
    if spell then
        local _, _, tex = GetSpellInfo(spell)
        f.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
        if isProc then f.name:SetText("|cff40ff40" .. spell .. "  !|r"); f.glow:SetVertexColor(0.2, 1, 0.4)
        else f.name:SetText(spell); f.glow:SetVertexColor(1, 0.85, 0.2) end
        f.glow:Show()
    else
        f.icon:SetTexture("Interface\\Icons\\Spell_Nature_TimeStop")
        f.name:SetText("|cff888888wait / pool|r"); f.glow:Hide()
    end
    f:Show()
end

-- ============================================================================
-- Events
-- ============================================================================
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        resetDPS()
    elseif event == "PLAYER_REGEN_ENABLED" then
        R.lastDPS = R.DPS(); R.combatStart = 0
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if AIP.db and AIP.db.rotationHelper then onCLEU(...) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- If the advisor was left on, spin up the overlay (its OnUpdate ticks it).
        if AIP.db and AIP.db.rotationHelper then R.CreateOverlay() end
    end
end)

function R.Toggle()
    if not AIP.db then return end
    AIP.db.rotationHelper = not AIP.db.rotationHelper
    if AIP.db.rotationHelper then R.CreateOverlay():Show(); R.Tick()
    elseif R.frame then R.frame:Hide() end
    if AIP.Print then AIP.Print("Rotation advisor " .. (AIP.db.rotationHelper and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r") .. ".") end
end
