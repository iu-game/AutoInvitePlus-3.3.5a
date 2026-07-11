-- AutoInvite Plus - PvP recommendations (WotLK 3.3.5a, Wrathful arena season).
-- Per spec-key (SG.KeyFor): resilience target, stat priority, PvP gemming approach,
-- PvP major glyphs (linked via GlyphData), the arena set name, key PvP items, and a
-- verified PvP talent build string (previewable in the Spec tree).
--
-- DATA HONESTY: guidance text + resilience targets are curated WotLK PvP facts;
-- glyphs render via GlyphData (name-guarded); talentBuild is a web-verified Wowhead
-- digit string (sums to ~71) or nil. Set/items are referenced by NAME (no fabricated
-- item IDs). Populated by the PvP research pass.
--
-- Row: PvP.List[specKey] = { resilTarget, statPriority, gemNote, glyphs={..}, setName, keyItems, talentBuild }

local AIP = AutoInvitePlus
if not AIP then return end
AIP.PvPData = AIP.PvPData or {}
local PvP = AIP.PvPData

PvP.List = {
    DK_Blood_DPS = {
        resilTarget = 1000,
        statPriority = "Resilience > Strength > Stamina > Hit",
        gemNote = "Chaotic Skyflare meta; Strength/Resilience hybrid gems; Rune of the Fallen Crusader on weapon",
        setName = "Wrathful Gladiator's Dreadplate Armor",
        keyItems = "PvP Medallion; 2H Wrathful Gladiator's weapon; resilience off-pieces. Blood is a niche arena DPS spec; no verified standard talent build",
    },
    DK_Frost_DPS = {
        resilTarget = 1000,
        statPriority = "~135 Spell Penetration > Hit (~5% PvP melee) > Strength (Resilience ~1000+ from gear)",
        gemNote = "Chaotic Skyflare Diamond meta; Bold Cardinal Ruby (Str), Stormy Majestic Zircon (spell pen), Str/Resil hybrids; Rune of the Fallen Crusader",
        glyphs = { "Frost Strike", "Hungering Cold", "Obliterate" },
        setName = "Wrathful Gladiator's Dreadplate Armor",
        keyItems = "PvP Medallion; deep-Frost burst, DW or 2H; 3 Unholy pts = Virulence (anti-dispel); Wrathful weapon(s), resilience off-pieces",
    },
    DK_Unholy_DPS = {
        resilTarget = 1000,
        statPriority = "Resilience > Strength > Stamina (Hit to cap and some Spell Penetration)",
        gemNote = "Chaotic Skyflare Diamond meta; +Str/+Resil hybrid gems and Bold Cardinal Ruby; spell penetration where needed; Rune of the Fallen Crusader",
        glyphs = { "Dark Death", "The Ghoul", "Anti-Magic Shell" },
        setName = "Wrathful Gladiator's Dreadplate Armor",
        keyItems = "PvP Medallion; on-use burst trinket (Death's Verdict/Choice); 2H Wrathful Gladiator's weapon; 51+ Unholy for Summon Gargoyle. Most-played DK arena spec",
    },
    Druid_Balance = {
        resilTarget = 1400,
        statPriority = "Resilience (~1400) > Spell Power > Crit > Haste; 4% Spell Hit cap, ~75 Spell Pen",
        gemNote = "Chaotic Skyflare Diamond meta; Runed Cardinal Ruby (SP) in red; SP/resil hybrids in yellow; spell-pen gems (Stormy Majestic Zircon) in blue",
        glyphs = { "Starfall", "Insect Swarm", "Monsoon" },
        setName = "Wrathful Gladiator's Wyrmhide (leather caster set)",
        keyItems = "PvP Medallion; Wrathful Gladiator's Battle Staff (2H) or Mageblade + Grimoire; resilience off-pieces; on-use burst trinkets",
    },
    Druid_FeralCat = {
        resilTarget = 850,
        statPriority = "Agility > Attack Power > Crit > Armor Pen; some Hit/Expertise; lower Resilience (~850) for burst",
        gemNote = "Relentless Earthsiege Diamond meta; Delicate Cardinal Ruby (Agi) in red; Mystic King's Amber in yellow; Vivid Eye of Zul in blue",
        glyphs = { "Shred", "Rip", "Savage Roar" },
        setName = "Wrathful Gladiator's Dragonhide (leather feral set)",
        keyItems = "PvP Medallion; Wrathful Gladiator's Greatstaff (2H); resilience-heavy off-pieces; burst trinkets",
        talentBuild = "-530202132320212052122033310511-00550301",
    },
    Druid_Resto = {
        resilTarget = 1500,
        statPriority = "Resilience (~1500) > Spell Power > Intellect/Spirit > Haste; 4% Spell Hit, ~75 Spell Pen",
        gemNote = "Trenchant Earthsiege Diamond meta (Insightful for mana); Runed Cardinal Ruby (SP) in red; SP/int hybrids in yellow; spell-pen gems in blue",
        glyphs = { "Swiftmend", "Barkskin", "Rejuvenation" },
        setName = "Wrathful Gladiator's Kodohide (leather healer set)",
        keyItems = "PvP Medallion; Wrathful Gladiator's Salvation (1H) + Grimoire off-hand (spell pen) or Energy Staff; resilience off-pieces; Bauble of True Blood",
    },
    Hunter_BM = {
        statPriority = "Hit ~5% cap > Agility >= Resilience/Stamina > ArP > Crit",
        gemNote = "Agility reds (Delicate Cardinal Ruby); yellow = hit (Rigid King's Amber); meta Relentless Earthsiege Diamond",
        setName = "Wrathful Gladiator's Pursuit",
        keyItems = "PvP trinket Medallion (CC break); exotic pet via 51-pt Beast Mastery (Chimaera); Wrathful ranged weapon; Deathbringer's Will",
    },
    Hunter_MM = {
        statPriority = "Hit 5% cap > Resilience >= Agility > ArP > Crit > AP",
        gemNote = "Delicate Cardinal Ruby (Agi); Rigid King's Amber (hit); one Agi/Resil hybrid for meta; Relentless Earthsiege Diamond",
        glyphs = { "Aimed Shot", "Chimera Shot", "Serpent Sting" },
        setName = "Wrathful Gladiator's Pursuit",
        keyItems = "Medallion (CC break); Wrathful Gladiator ranged weapon; Deathbringer's Will; Disengage/Survival Tactics kiting",
    },
    Hunter_SV = {
        statPriority = "Hit 5% cap > Agility ~ Crit > Resilience/Stamina > ArP",
        gemNote = "Delicate Cardinal Ruby (Agi); Rigid King's Amber (hit); meta Relentless Earthsiege Diamond",
        glyphs = { "Explosive Shot", "Deterrence", "Kill Shot" },
        setName = "Wrathful Gladiator's Pursuit",
        keyItems = "Medallion (CC break); Wrathful ranged weapon; Deathbringer's Will; 51-pt Explosive Shot capstone",
    },
    Mage_Arcane = {
        resilTarget = 1400,
        statPriority = "Resilience > Hit (~4% cap) > Spell Penetration (~130) > Spell Power > Crit/Haste",
        gemNote = "Runed Cardinal Ruby (SP) in most sockets; Chaotic Skyflare Diamond meta; add Resilience gems only to stay comfortable; JC Mystic Dragon's Eyes for resilience",
        glyphs = { "Arcane Missiles", "Evocation", "Arcane Blast" },
        setName = "Wrathful Gladiator's Silk Regalia",
        keyItems = "Medallion PvP trinket (breaks stun/fear); Wrathful Gladiator's Spellblade + Endgame (or War Staff) and Touch of Defeat wand; +spell-pen off-pieces",
        talentBuild = "205024130122032103323102405321-03-203023001",
    },
    Mage_Fire = {
        resilTarget = 1400,
        statPriority = "Resilience > Hit (~4% cap) > Spell Penetration (~130) > Spell Power > Crit > Haste",
        gemNote = "Runed Cardinal Ruby (SP) in most sockets; Chaotic Skyflare Diamond meta; minimal Resilience gems as needed; JC Mystic Dragon's Eyes",
        glyphs = { "Living Bomb", "Evocation", "Polymorph" },
        setName = "Wrathful Gladiator's Silk Regalia",
        keyItems = "Medallion (breaks stun/fear); Wrathful Gladiator's Spellblade + Endgame; +spell-pen off-pieces",
    },
    Mage_Frost = {
        resilTarget = 1400,
        statPriority = "Resilience > Hit (~4% cap) > Spell Penetration (~130) > Spell Power > Crit/Haste",
        gemNote = "Runed Cardinal Ruby (SP) primary; Chaotic Skyflare Diamond meta; a few Resilience gems for survivability; JC Mystic Dragon's Eyes",
        glyphs = { "Ice Barrier", "Evocation", "Polymorph" },
        setName = "Wrathful Gladiator's Silk Regalia",
        keyItems = "Medallion CC-break trinket; Wrathful Gladiator's Spellblade + Endgame (or War Staff) + Touch of Defeat wand; +spell-pen off-pieces",
        talentBuild = "23032022010203--3533203111203100232102231151",
    },
    Pala_Holy = {
        resilTarget = 1200,
        statPriority = "Resilience (~1200) > Spell Power > Crit > Intellect > Mp5 > Haste",
        gemNote = "Meta Insightful Earthsiege Diamond; gem Spell Power + Resilience (do NOT gem raw Intellect - Holy Guidance converts only ~20%); socket bonuses only if cheap",
        glyphs = { "Holy Shock", "Seal of Light", "Turn Evil" },
        setName = "Wrathful Gladiator's Ornamented Battlegear",
        keyItems = "PvP Medallion (breaks stun/fear/root); Wrathful Gladiator's 1H spellpower weapon + shield; resilience honor off-pieces",
    },
    Pala_Ret_DPS = {
        statPriority = "Resilience > Strength > Crit (~30% sweet spot) > Haste; Stamina for survivability",
        gemNote = "Meta Relentless Earthsiege Diamond; gem Strength (Bold), add Resilience/Stamina gems where survivability is needed",
        glyphs = { "Judgement", "Turn Evil", "Salvation" },
        setName = "Wrathful Gladiator's Scaled Battlegear",
        keyItems = "PvP Medallion to break CC and set up kills; 2H Wrathful Gladiator weapon; optional 1H spellpower + shield swap; resilience off-pieces",
    },
    Priest_Disc = {
        resilTarget = 1414,
        statPriority = "Resilience (to ~1414) > Hit (~4% for offense) > Spell Penetration (75-130) > Spell Power > Spirit/MP5",
        gemNote = "Mix Spell Power/Intellect with Resilience; JC Mystic Dragon's Eyes for big resilience; Chaotic Skyflare Diamond meta; healer leans Intellect over raw SP",
        glyphs = { "Penance", "Pain Suppression", "Power Word: Shield" },
        setName = "Wrathful Gladiator's Mooncloth Regalia",
        keyItems = "Medallion (breaks stun/fear); caster main-hand + off-hand (Wrathful Gladiator's Spellblade/Endgame) or War Staff; on-use resilience/mana trinket",
    },
    Priest_Holy = {
        resilTarget = 1400,
        statPriority = "Resilience > Spell Power/Intellect > Spirit/MP5 > Spell Penetration",
        gemNote = "Balance Spell Power/Intellect with Resilience; JC Mystic Dragon's Eyes for resilience; Chaotic Skyflare Diamond meta",
        setName = "Wrathful Gladiator's Mooncloth Regalia",
        keyItems = "Medallion CC-break trinket; caster weapon + off-hand; on-use resilience/mana trinket (Holy is off-meta; Discipline is the standard priest arena build)",
    },
    Priest_Shadow = {
        resilTarget = 1400,
        statPriority = "Resilience > Hit (to cap) > Spell Penetration (~130) > Spell Power > Haste/Crit",
        gemNote = "Runed Cardinal Ruby (SP) with some Resilience gems; Chaotic Skyflare Diamond meta; JC Mystic Dragon's Eyes for resilience",
        glyphs = { "Dispersion", "Power Word: Shield", "Fade" },
        setName = "Wrathful Gladiator's Satin Regalia",
        keyItems = "Medallion (breaks stun/fear); Wrathful Gladiator's Spellblade + Endgame + Touch of Defeat wand; +spell-pen off-pieces",
    },
    Rogue_Assass = {
        resilTarget = 1000,
        statPriority = "Hit cap > AP > Crit ~ Haste; ~1000 Resilience",
        gemNote = "AP reds (Empowered/Bright Ametrine); Nightmare Tear meta activator; Relentless Earthsiege Diamond",
        setName = "Wrathful Gladiator's Vestments",
        keyItems = "Medallion (CC break); slow MH (Wound Poison) + fast OH (Deadly Poison) daggers; Deathbringer's Will",
    },
    Rogue_Combat = {
        statPriority = "Hit cap > AP > Haste ~ Crit; stack Resilience",
        gemNote = "AP reds (Empowered Ametrine); Relentless Earthsiege Diamond meta",
        glyphs = { "Killing Spree", "Adrenaline Rush", "Sinister Strike" },
        setName = "Wrathful Gladiator's Vestments",
        keyItems = "Medallion (CC break); Wrathful Gladiator swords/maces; 51-pt Killing Spree capstone",
    },
    Rogue_Subtlety = {
        resilTarget = 900,
        statPriority = "Hit 5% cap > Resilience (~900) > AP > Agility > Crit",
        gemNote = "Empowered Ametrine (AP) red; Rigid King's Amber (hit); Nightmare Tear + Relentless Earthsiege Diamond meta",
        glyphs = { "Vigor", "Preparation", "Shadow Dance" },
        setName = "Wrathful Gladiator's Vestments",
        keyItems = "Medallion (CC break); Wrathful Gladiator daggers; Deathbringer's Will / Sharpened Twilight Scale; Cloak of Shadows vs casters",
    },
    Sham_Elemental = {
        statPriority = "Resilience/Stamina > Intellect/Spell Power/Crit > Haste (~15%) > Spell Pen; 4% spell hit",
        gemNote = "Durable Ametrine red; Rigid/Mystic King's Amber yellow; Stormy Majestic Zircon blue; Insightful Earthsiege Diamond meta",
        glyphs = { "Stoneclaw Totem", "Thunder", "Lava" },
        setName = "Wrathful Gladiator's Thunderfist",
        keyItems = "Medallion (CC break); Wrathful Gladiator's Mageblade + Redoubt shield; Grounding Totem; Dislodged Foreign Object",
    },
    Sham_Enhance = {
        statPriority = "Resilience/Stamina > Intellect/Strength/Crit/Haste; 4% hit",
        gemNote = "Empowered Ametrine red; Kharmaa's Grace/Mystic King's Amber yellow; Stormy Majestic Zircon blue; Relentless Earthsiege Diamond meta",
        glyphs = { "Shocking", "Stoneclaw Totem", "Feral Spirit" },
        setName = "Wrathful Gladiator's Earthshaker",
        keyItems = "Medallion (CC break); dual-wield Wrathful Gladiator weapons; Deathbringer's Will; 51-pt Feral Spirit; Grounding Totem",
    },
    Sham_Resto = {
        statPriority = "Resilience/Stamina > Intellect/Spell Power/Crit; 4% spell hit",
        gemNote = "Durable Ametrine red; Kharmaa's Grace/Mystic King's Amber yellow; Opaque Eye of Zul blue; Insightful Earthsiege Diamond meta",
        glyphs = { "Earth Shield", "Stoneclaw Totem", "Healing Wave" },
        setName = "Wrathful Gladiator's Wartide",
        keyItems = "Medallion (CC break); Wrathful Gladiator's Salvation weapon + shield; Bauble of True Blood; Nature's Guardian",
    },
    War_Arms_DPS = {
        resilTarget = 1000,
        statPriority = "Resilience ~950-1050 > Hit to 5% > Strength > ArP (~60%) > Crit; more Stamina/Resil than PvE",
        gemNote = "Meta Relentless Earthsiege Diamond; stack Strength (or ArP to soft cap in early gear), Resilience in blue sockets / to meet socket bonuses",
        glyphs = { "Mortal Strike", "Rending", "Bladestorm" },
        setName = "Wrathful Gladiator's Battlegear",
        keyItems = "On-use Medallion of the Horde/Alliance (breaks CC) + resilience trinket; Wrathful Gladiator's 2H axe/mace; resilience honor off-pieces (neck, cloak, rings)",
        talentBuild = "0320332023330105202212013231251-32500013-",
    },
    War_Fury_DPS = {
        resilTarget = 1000,
        statPriority = "Resilience ~950-1050 > Hit to DW 5% > Strength/ArP > Crit; niche burst spec, rarely arena",
        gemNote = "Meta Relentless Earthsiege Diamond; Strength-focused with Resilience in blue sockets for survivability",
        glyphs = { "Whirlwind", "Cleaving", "Heroic Strike" },
        setName = "Wrathful Gladiator's Battlegear",
        keyItems = "Medallion CC-break trinket + resilience trinket; Wrathful Gladiator's one-hand weapons; relies on burst-window cooldowns",
    },
    Warlock_Affli = {
        resilTarget = 1414,
        statPriority = "Resilience (to ~1414) > Hit (6%) > Spell Penetration (~130) > Haste > Spell Power",
        gemNote = "Stack Resilience/Stamina with Spell Power fillers; JC Mystic Dragon's Eyes for resilience; Blacksmithing socket bracer/gloves; Chaotic Skyflare Diamond meta",
        glyphs = { "Quick Decay", "Siphon Life", "Shadowflame" },
        setName = "Wrathful Gladiator's Felweave Regalia",
        keyItems = "Medallion (breaks stun/fear); Wrathful Gladiator's Spellblade + Endgame; SL/SL pet survivability; +spell-pen off-pieces",
    },
    Warlock_Demo = {
        statPriority = "Resilience > Hit (6%) > Spell Penetration (~130) > Spell Power > Haste",
        gemNote = "Resilience/Stamina with Spell Power fillers; JC Mystic Dragon's Eyes; Chaotic Skyflare Diamond meta",
        setName = "Wrathful Gladiator's Felweave Regalia",
        keyItems = "Medallion CC-break trinket; caster weapon set (no dedicated Demonology arena guide; Affliction/Destruction are the standard warlock arena specs)",
    },
    Warlock_Destro = {
        resilTarget = 1300,
        statPriority = "Resilience (>=1300) > Hit (6%) > Spell Penetration (~130) > Spell Power > Haste > Crit",
        gemNote = "Resilience/Stamina with Spell Power fillers; JC Mystic Dragon's Eyes for resilience; Chaotic Skyflare Diamond meta",
        glyphs = { "Conflagrate", "Shadowflame", "Succubus" },
        setName = "Wrathful Gladiator's Felweave Regalia",
        keyItems = "Medallion (breaks stun/fear); Wrathful Gladiator's Spellblade + Endgame; Succubus for Seduction CC; +spell-pen off-pieces",
    },
}

-- ============================================================================
-- PvP GEMMING + ENCHANTING plans (Wrathful / Season 8, verified research pass)
-- Keyed by a coarse PvP archetype (strMelee/agiMelee/caster/healer) so every spec
-- gets correct, consistent guidance. Rule: at Wrathful resilience you GEM OFFENSE in
-- the primary colour and take resilience from gear; PvP enchants differ from PvE
-- mainly in the resilience head arcanum, Tuskarr's boots, and cloak (spell-pierce /
-- greater speed). Meta activation reqs: Relentless = 1R/1Y/1B; Chaotic/Austere = 2 Blue;
-- Persistent = 2Y/1B; Enigmatic = 2R/1Y; Insightful = 1R/1Y/1B.
-- ============================================================================
PvP.GemPlan = {
    strMelee = { meta = "Chaotic Skyflare Diamond (crit+critdmg), or Persistent Earthsiege (+42 AP, -10% stun) for PvP",
                 gems = "Bold Cardinal Ruby (Str) primary; Sovereign Dreadstone (Str+Sta) for blue sockets; a touch of hit (~5%); Mystic King's Amber (+20 resil) only for a yellow socket bonus / survival." },
    agiMelee = { meta = "Relentless Earthsiege Diamond (+21 Agi; needs 1 Red + 1 Yellow + 1 Blue)",
                 gems = "Delicate Cardinal Ruby (Agi) primary; Glinting Dreadstone (Agi+hit) toward ~5% hit; Shifting Dreadstone (Agi+Sta) for blue sockets; Mystic King's Amber (+20 resil) only for a yellow socket bonus." },
    caster   = { meta = "Chaotic Skyflare Diamond (max dmg), or Enigmatic Skyflare (-10% snare/root, great for kiting)",
                 gems = "Runed Cardinal Ruby (SP) primary; Stormy Majestic Zircon (+25 spell pen) x3-4 toward ~130 pen; a little hit (~4-5%) via Veiled Ametrine; resilience from gear." },
    healer   = { meta = "Insightful Earthsiege Diamond (mana proc), or Austere Earthsiege (+32 Sta/+2% armor) for survival",
                 gems = "Brilliant Cardinal Ruby (Int) primary; Purified Dreadstone (SP+Spirit) for blue sockets; Mystic King's Amber (+20 resil) to taste for survival." },
}
-- Spec-specific gemming nuances layered on top of the archetype plan.
PvP.GemPlanBySpec = {
    Mage_Frost   = "Enigmatic Skyflare Diamond meta (-10% snare/root duration) is preferred for kiting.",
    War_Arms_DPS = "Add Fractured Cardinal Ruby (+20 Armor Pen) alongside Strength once your ArP gear supports it.",
    Rogue_Combat = "Take a little more hit/expertise (Glinting/Precise) than the other rogue specs.",
    Hunter_SV    = "Slightly higher ranged-hit target than BM/MM; add a Rigid King's Amber if under ~5%.",
}
-- PvP enchant plan by archetype. "[PvP]" marks a slot that differs from the PvE enchant.
PvP.EnchantPlan = {
    strMelee = {
        "Head: Arcanum of Triumph (+50 AP, +20 resilience) [PvP]",
        "Cloak: Major Agility, or Greater Speed for kiting [PvP]",
        "Legs: Icescale Leg Armor   Feet: Tuskarr's Vitality (+8% run speed) [PvP]",
        "Weapon: Berserking (2H) - DKs use Runeforging instead (Fallen Crusader DPS / Spellshattering defensive) [PvP]",
        "Wrist: Greater Assault   Hands: Crusher   Chest: Powerful Stats (Super Health for survival)",
    },
    agiMelee = {
        "Head: Arcanum of Triumph (+50 AP, +20 resilience) [PvP]",
        "Cloak: Major Agility (or Greater Speed) [PvP]   Legs: Icescale Leg Armor",
        "Feet: Tuskarr's Vitality (+8% run speed) [PvP]",
        "Weapon: Mongoose (melee) - Hunters use Heartseeker Scope (+40 crit) on the ranged instead",
        "Wrist: Greater Assault   Hands: Crusher/Major Agility   Chest: Powerful Stats",
    },
    caster = {
        "Head: Arcanum of Dominance (+29 SP, +20 resilience) [PvP]",
        "Cloak: Spell Piercing (+35 spell pen) [PvP], or Springy Arachnoweave (engineers)",
        "Legs: Sapphire Spellthread   Feet: Tuskarr's Vitality (+8% run speed) [PvP]",
        "Weapon: Black Magic (burst) or Mighty Spellpower (+63 SP, consistent)",
        "Wrist: Superior Spellpower   Hands: Exceptional Spellpower   Chest: Powerful Stats",
    },
    healer = {
        "Head: Arcanum of Dominance (+29 SP, +20 resilience) [PvP]",
        "Cloak: Greater Speed (haste) [PvP], or Wisdom",
        "Legs: Brilliant Spellthread   Feet: Tuskarr's Vitality (+8% run speed) [PvP]",
        "Weapon: Mighty Spellpower   Shield: Resilience (+12) [PvP] or Greater Intellect",
        "Wrist: Superior Spellpower   Hands: Exceptional Spellpower   Chest: Powerful Stats",
    },
}

-- Map the player's ItemScore archetype -> coarse PvP plan archetype.
local function pvpPlanArch()
    local IS = AIP.ItemScore
    local a = IS and IS.PlayerArchetype and IS.PlayerArchetype()
    if a == "healerCrit" or a == "casterHot" then return "healer" end
    if a == "casterDPS" then return "caster" end
    if a == "agiDPS" then return "agiMelee" end
    if a == "strDPS" or a == "tank" then return "strMelee" end
    return "caster"
end

-- Returns the archetype gem plan {meta,gems} plus an optional spec-specific nuance string.
function PvP.GemPlanForPlayer()
    local SG = AIP.SpecGuides
    local key = SG and SG.KeyFor and SG.KeyFor()
    return PvP.GemPlan[pvpPlanArch()], key and PvP.GemPlanBySpec[key] or nil
end

-- Returns the archetype enchant plan (array of per-slot lines).
function PvP.EnchantPlanForPlayer()
    return PvP.EnchantPlan[pvpPlanArch()]
end

-- Per-slot PvP item recommendations (Wrathful arena set pieces + honor off-pieces),
-- keyed by spec-key then numeric inventory slot id. Row: { name, itemID|nil, ilvl|nil,
-- source }. Same data-honesty contract as the rest of the addon: an entry ships an
-- itemID only when web-verified for 3.3.5a (name-guarded at render, so a stale id
-- degrades to the item NAME as text); otherwise itemID is nil and the UI shows the
-- name + source text. Populated by the PvP gear research pass (empty = ForSlot falls
-- back to the set-name / key-item guidance text in the slot detail).
PvP.Gear = {
    Mage_Arcane = {
        [1] = { { "Wrathful Gladiator's Silk Cowl", 51465, 270, "arena set" } },
        [2] = { { "Wrathful Gladiator's Pendant of Ascendancy", nil, 264, "caster SP neck (honor)" } },
        [3] = { { "Wrathful Gladiator's Silk Amice", 51467, 270, "arena set" } },
        [15] = { { "Wrathful Gladiator's Cloak of Ascendancy", nil, 264, "caster SP cloak (honor)" } },
        [5] = { { "Wrathful Gladiator's Silk Raiment", 51463, 270, "arena set" } },
        [9] = { { "Wrathful Gladiator's Silk Cuffs", nil, 264, "caster wrist (honor)" } },
        [10] = { { "Wrathful Gladiator's Silk Handguards", 51464, 270, "arena set" } },
        [6] = { { "Wrathful Gladiator's Silk Cord", nil, 264, "caster waist (honor)" } },
        [7] = { { "Wrathful Gladiator's Silk Trousers", 51466, 270, "arena set" } },
        [8] = { { "Wrathful Gladiator's Silk Treads", nil, 264, "caster feet (honor)" } },
        [11] = { { "Wrathful Gladiator's Band of Dominance", nil, 264, "caster SP ring (honor)" } },
        [13] = { { "Medallion of the Alliance", 42123, 200, "PvP trinket (Alliance) - CC break + resil" }, { "Medallion of the Horde", 42122, 200, "PvP trinket (Horde) - CC break + resil" } },
        [16] = { { "Wrathful Gladiator's Spellblade", nil, 264, "1H caster main-hand" }, { "Wrathful Gladiator's War Staff", nil, 264, "2H caster staff (alt)" } },
        [17] = { { "Wrathful Gladiator's Endgame", nil, 264, "caster off-hand" } },
        [18] = { { "Wrathful Gladiator's Touch of Defeat", nil, 264, "wand" } },
    },
    Mage_Fire = {
        [1] = { { "Wrathful Gladiator's Silk Cowl", 51465, 270, "arena set" } },
        [2] = { { "Wrathful Gladiator's Pendant of Ascendancy", nil, 264, "caster SP neck (honor)" } },
        [3] = { { "Wrathful Gladiator's Silk Amice", 51467, 270, "arena set" } },
        [15] = { { "Wrathful Gladiator's Cloak of Ascendancy", nil, 264, "caster SP cloak (honor)" } },
        [5] = { { "Wrathful Gladiator's Silk Raiment", 51463, 270, "arena set" } },
        [9] = { { "Wrathful Gladiator's Silk Cuffs", nil, 264, "caster wrist (honor)" } },
        [10] = { { "Wrathful Gladiator's Silk Handguards", 51464, 270, "arena set" } },
        [6] = { { "Wrathful Gladiator's Silk Cord", nil, 264, "caster waist (honor)" } },
        [7] = { { "Wrathful Gladiator's Silk Trousers", 51466, 270, "arena set" } },
        [8] = { { "Wrathful Gladiator's Silk Treads", nil, 264, "caster feet (honor)" } },
        [11] = { { "Wrathful Gladiator's Band of Dominance", nil, 264, "caster SP ring (honor)" } },
        [13] = { { "Medallion of the Alliance", 42123, 200, "PvP trinket (Alliance) - CC break + resil" }, { "Medallion of the Horde", 42122, 200, "PvP trinket (Horde) - CC break + resil" } },
        [16] = { { "Wrathful Gladiator's Spellblade", nil, 264, "1H caster main-hand" }, { "Wrathful Gladiator's War Staff", nil, 264, "2H caster staff (alt)" } },
        [17] = { { "Wrathful Gladiator's Endgame", nil, 264, "caster off-hand" } },
        [18] = { { "Wrathful Gladiator's Touch of Defeat", nil, 264, "wand" } },
    },
    Mage_Frost = {
        [1] = { { "Wrathful Gladiator's Silk Cowl", 51465, 270, "arena set" } },
        [2] = { { "Wrathful Gladiator's Pendant of Ascendancy", nil, 264, "caster SP neck (honor)" } },
        [3] = { { "Wrathful Gladiator's Silk Amice", 51467, 270, "arena set" } },
        [15] = { { "Wrathful Gladiator's Cloak of Ascendancy", nil, 264, "caster SP cloak (honor)" } },
        [5] = { { "Wrathful Gladiator's Silk Raiment", 51463, 270, "arena set" } },
        [9] = { { "Wrathful Gladiator's Silk Cuffs", nil, 264, "caster wrist (honor)" } },
        [10] = { { "Wrathful Gladiator's Silk Handguards", 51464, 270, "arena set" } },
        [6] = { { "Wrathful Gladiator's Silk Cord", nil, 264, "caster waist (honor)" } },
        [7] = { { "Wrathful Gladiator's Silk Trousers", 51466, 270, "arena set" } },
        [8] = { { "Wrathful Gladiator's Silk Treads", nil, 264, "caster feet (honor)" } },
        [11] = { { "Wrathful Gladiator's Band of Dominance", nil, 264, "caster SP ring (honor)" } },
        [13] = { { "Medallion of the Alliance", 42123, 200, "PvP trinket (Alliance) - CC break + resil" }, { "Medallion of the Horde", 42122, 200, "PvP trinket (Horde) - CC break + resil" } },
        [16] = { { "Wrathful Gladiator's Spellblade", nil, 264, "1H caster main-hand" }, { "Wrathful Gladiator's War Staff", nil, 264, "2H caster staff (alt)" } },
        [17] = { { "Wrathful Gladiator's Endgame", nil, 264, "caster off-hand" } },
        [18] = { { "Wrathful Gladiator's Touch of Defeat", nil, 264, "wand" } },
    },
    Warlock_Affli = {
        [1] = { { "Wrathful Gladiator's Felweave Cowl", 51538, 270, "arena set" } },
        [2] = { { "Wrathful Gladiator's Pendant of Ascendancy", nil, 264, "caster SP neck (honor)" } },
        [3] = { { "Wrathful Gladiator's Felweave Amice", 51540, 270, "arena set" } },
        [15] = { { "Wrathful Gladiator's Cloak of Ascendancy", nil, 264, "caster SP cloak (honor)" } },
        [5] = { { "Wrathful Gladiator's Felweave Raiment", 51536, 270, "arena set" } },
        [9] = { { "Wrathful Gladiator's Felweave Cuffs", nil, 264, "caster wrist (honor)" } },
        [10] = { { "Wrathful Gladiator's Felweave Handguards", 51537, 270, "arena set" } },
        [6] = { { "Wrathful Gladiator's Felweave Cord", nil, 264, "caster waist (honor)" } },
        [7] = { { "Wrathful Gladiator's Felweave Trousers", nil, 270, "arena set" } },
        [8] = { { "Wrathful Gladiator's Treads of Alacrity", nil, 264, "caster feet (honor)" } },
        [11] = { { "Wrathful Gladiator's Band of Dominance", nil, 264, "caster SP ring (honor)" } },
        [13] = { { "Medallion of the Alliance", 42123, 200, "PvP trinket (Alliance) - CC break + resil" }, { "Medallion of the Horde", 42122, 200, "PvP trinket (Horde) - CC break + resil" } },
        [16] = { { "Wrathful Gladiator's Spellblade", nil, 264, "1H caster main-hand" }, { "Wrathful Gladiator's War Staff", nil, 264, "2H caster staff (alt)" } },
        [17] = { { "Wrathful Gladiator's Endgame", nil, 264, "caster off-hand" } },
        [18] = { { "Wrathful Gladiator's Touch of Defeat", nil, 264, "wand" } },
    },
    Warlock_Demo = {
        [1] = { { "Wrathful Gladiator's Felweave Cowl", 51538, 270, "arena set" } },
        [2] = { { "Wrathful Gladiator's Pendant of Ascendancy", nil, 264, "caster SP neck (honor)" } },
        [3] = { { "Wrathful Gladiator's Felweave Amice", 51540, 270, "arena set" } },
        [15] = { { "Wrathful Gladiator's Cloak of Ascendancy", nil, 264, "caster SP cloak (honor)" } },
        [5] = { { "Wrathful Gladiator's Felweave Raiment", 51536, 270, "arena set" } },
        [9] = { { "Wrathful Gladiator's Felweave Cuffs", nil, 264, "caster wrist (honor)" } },
        [10] = { { "Wrathful Gladiator's Felweave Handguards", 51537, 270, "arena set" } },
        [6] = { { "Wrathful Gladiator's Felweave Cord", nil, 264, "caster waist (honor)" } },
        [7] = { { "Wrathful Gladiator's Felweave Trousers", nil, 270, "arena set" } },
        [8] = { { "Wrathful Gladiator's Treads of Alacrity", nil, 264, "caster feet (honor)" } },
        [11] = { { "Wrathful Gladiator's Band of Dominance", nil, 264, "caster SP ring (honor)" } },
        [13] = { { "Medallion of the Alliance", 42123, 200, "PvP trinket (Alliance) - CC break + resil" }, { "Medallion of the Horde", 42122, 200, "PvP trinket (Horde) - CC break + resil" } },
        [16] = { { "Wrathful Gladiator's Spellblade", nil, 264, "1H caster main-hand" }, { "Wrathful Gladiator's War Staff", nil, 264, "2H caster staff (alt)" } },
        [17] = { { "Wrathful Gladiator's Endgame", nil, 264, "caster off-hand" } },
        [18] = { { "Wrathful Gladiator's Touch of Defeat", nil, 264, "wand" } },
    },
    Warlock_Destro = {
        [1] = { { "Wrathful Gladiator's Felweave Cowl", 51538, 270, "arena set" } },
        [2] = { { "Wrathful Gladiator's Pendant of Ascendancy", nil, 264, "caster SP neck (honor)" } },
        [3] = { { "Wrathful Gladiator's Felweave Amice", 51540, 270, "arena set" } },
        [15] = { { "Wrathful Gladiator's Cloak of Ascendancy", nil, 264, "caster SP cloak (honor)" } },
        [5] = { { "Wrathful Gladiator's Felweave Raiment", 51536, 270, "arena set" } },
        [9] = { { "Wrathful Gladiator's Felweave Cuffs", nil, 264, "caster wrist (honor)" } },
        [10] = { { "Wrathful Gladiator's Felweave Handguards", 51537, 270, "arena set" } },
        [6] = { { "Wrathful Gladiator's Felweave Cord", nil, 264, "caster waist (honor)" } },
        [7] = { { "Wrathful Gladiator's Felweave Trousers", nil, 270, "arena set" } },
        [8] = { { "Wrathful Gladiator's Treads of Alacrity", nil, 264, "caster feet (honor)" } },
        [11] = { { "Wrathful Gladiator's Band of Dominance", nil, 264, "caster SP ring (honor)" } },
        [13] = { { "Medallion of the Alliance", 42123, 200, "PvP trinket (Alliance) - CC break + resil" }, { "Medallion of the Horde", 42122, 200, "PvP trinket (Horde) - CC break + resil" } },
        [16] = { { "Wrathful Gladiator's Spellblade", nil, 264, "1H caster main-hand" }, { "Wrathful Gladiator's War Staff", nil, 264, "2H caster staff (alt)" } },
        [17] = { { "Wrathful Gladiator's Endgame", nil, 264, "caster off-hand" } },
        [18] = { { "Wrathful Gladiator's Touch of Defeat", nil, 264, "wand" } },
    },
    Pala_Ret_DPS = {
        [1] = { { "Wrathful Gladiator's Scaled Helm", 51476, 270, "arena set" } },
        [2] = { { "Wrathful Gladiator's Pendant of Triumph", 51355, 264, "honor (AP+crit)" }, { "Wrathful Gladiator's Pendant of Victory", 51357, 264, "honor (AP+hit)" } },
        [3] = { { "Wrathful Gladiator's Scaled Shoulders", 51479, 270, "arena set" } },
        [15] = { { "Wrathful Gladiator's Cloak of Triumph", 51354, 264, "honor (AP+crit)" }, { "Wrathful Gladiator's Cloak of Victory", 51356, 264, "honor (AP+hit)" } },
        [5] = { { "Wrathful Gladiator's Scaled Chestpiece", 51474, 270, "arena set" } },
        [9] = { { "Wrathful Gladiator's Bracers of Triumph", 51364, 264, "honor (str/AP plate)" } },
        [10] = { { "Wrathful Gladiator's Scaled Gauntlets", 51475, 270, "arena set" } },
        [6] = { { "Wrathful Gladiator's Girdle of Triumph", 51362, 264, "honor (str/AP plate)" } },
        [7] = { { "Wrathful Gladiator's Scaled Legguards", 51477, 270, "arena set" } },
        [8] = { { "Wrathful Gladiator's Greaves of Triumph", 51363, 264, "honor (str/AP plate)" } },
        [11] = { { "Wrathful Gladiator's Band of Triumph", 51358, 264, "honor (AP+crit)" } },
        [13] = { { "Medallion of the Alliance", 42123, 200, "PvP trinket (Alliance) - CC break + resil" }, { "Medallion of the Horde", 42122, 200, "PvP trinket (Horde) - CC break + resil" } },
        [16] = { { "Wrathful Gladiator's Greatsword", 51392, 264, "2H sword" }, { "Wrathful Gladiator's Decapitator", 51388, 264, "2H axe" }, { "Wrathful Gladiator's Bonegrinder", 51390, 264, "2H mace" } },
        [18] = { { "Wrathful Gladiator's Libram of Fortitude", 51478, 270, "relic (Ret)" } },
    },
    Druid_FeralCat = {
        [1] = { { "Wrathful Gladiator's Dragonhide Helm", 51427, 270, "arena set" } },
        [2] = { { "Wrathful Gladiator's Pendant of Triumph", 51355, 264, "honor (AP+crit)" }, { "Wrathful Gladiator's Pendant of Victory", 51357, 264, "honor (AP+hit)" } },
        [3] = { { "Wrathful Gladiator's Dragonhide Spaulders", 51430, 270, "arena set" } },
        [15] = { { "Wrathful Gladiator's Cloak of Triumph", 51354, 264, "honor (AP+crit)" }, { "Wrathful Gladiator's Cloak of Victory", 51356, 264, "honor (AP+hit)" } },
        [5] = { { "Wrathful Gladiator's Dragonhide Robes", 51425, 270, "arena set" } },
        [9] = { { "Wrathful Gladiator's Armwraps of Triumph", 51370, 264, "honor (agi leather)" } },
        [10] = { { "Wrathful Gladiator's Dragonhide Gloves", 51426, 270, "arena set" } },
        [6] = { { "Wrathful Gladiator's Belt of Triumph", 51368, 264, "honor (agi leather)" } },
        [7] = { { "Wrathful Gladiator's Dragonhide Legguards", 51428, 270, "arena set" } },
        [8] = { { "Wrathful Gladiator's Boots of Triumph", 51369, 264, "honor (agi leather)" } },
        [11] = { { "Wrathful Gladiator's Band of Triumph", 51358, 264, "honor (AP+crit)" } },
        [13] = { { "Medallion of the Alliance", 42123, 200, "PvP trinket (Alliance) - CC break + resil" }, { "Medallion of the Horde", 42122, 200, "PvP trinket (Horde) - CC break + resil" } },
        [16] = { { "Wrathful Gladiator's Staff", 51431, 264, "2H staff (feral, druid-only)" } },
        [18] = { { "Wrathful Gladiator's Idol of Resolve", 51429, 270, "relic (feral)" } },
    },
    Hunter_BM = {
        [1] = { { "Wrathful Gladiator's Chain Helm", 51460, 270, "arena set" } },
        [2] = { { "Wrathful Gladiator's Pendant of Triumph", 51355, 264, "honor (AP+crit)" }, { "Wrathful Gladiator's Pendant of Victory", 51357, 264, "honor (AP+hit)" } },
        [3] = { { "Wrathful Gladiator's Chain Spaulders", 51462, 270, "arena set" } },
        [15] = { { "Wrathful Gladiator's Cloak of Triumph", 51354, 264, "honor (AP+crit)" }, { "Wrathful Gladiator's Cloak of Victory", 51356, 264, "honor (AP+hit)" } },
        [5] = { { "Wrathful Gladiator's Chain Armor", 51458, 270, "arena set" } },
        [9] = { { "Wrathful Gladiator's Wristguards of Triumph", 51352, 264, "honor (agi mail)" } },
        [10] = { { "Wrathful Gladiator's Chain Gauntlets", 51459, 270, "arena set" } },
        [6] = { { "Wrathful Gladiator's Waistguard of Triumph", 51350, 264, "honor (agi mail)" } },
        [7] = { { "Wrathful Gladiator's Chain Leggings", 51461, 270, "arena set" } },
        [8] = { { "Wrathful Gladiator's Sabatons of Triumph", 51351, 264, "honor (agi mail)" } },
        [11] = { { "Wrathful Gladiator's Band of Triumph", 51358, 264, "honor (AP+crit)" } },
        [13] = { { "Medallion of the Alliance", 42123, 200, "PvP trinket (Alliance) - CC break + resil" }, { "Medallion of the Horde", 42122, 200, "PvP trinket (Horde) - CC break + resil" } },
        [18] = { { "Wrathful Gladiator's Longbow", 51394, 264, "bow" }, { "Wrathful Gladiator's Rifle", 51449, 264, "gun" }, { "Wrathful Gladiator's Heavy Crossbow", 51411, 264, "crossbow" } },
    },
    Hunter_MM = {
        [1] = { { "Wrathful Gladiator's Chain Helm", 51460, 270, "arena set" } },
        [2] = { { "Wrathful Gladiator's Pendant of Triumph", 51355, 264, "honor (AP+crit)" }, { "Wrathful Gladiator's Pendant of Victory", 51357, 264, "honor (AP+hit)" } },
        [3] = { { "Wrathful Gladiator's Chain Spaulders", 51462, 270, "arena set" } },
        [15] = { { "Wrathful Gladiator's Cloak of Triumph", 51354, 264, "honor (AP+crit)" }, { "Wrathful Gladiator's Cloak of Victory", 51356, 264, "honor (AP+hit)" } },
        [5] = { { "Wrathful Gladiator's Chain Armor", 51458, 270, "arena set" } },
        [9] = { { "Wrathful Gladiator's Wristguards of Triumph", 51352, 264, "honor (agi mail)" } },
        [10] = { { "Wrathful Gladiator's Chain Gauntlets", 51459, 270, "arena set" } },
        [6] = { { "Wrathful Gladiator's Waistguard of Triumph", 51350, 264, "honor (agi mail)" } },
        [7] = { { "Wrathful Gladiator's Chain Leggings", 51461, 270, "arena set" } },
        [8] = { { "Wrathful Gladiator's Sabatons of Triumph", 51351, 264, "honor (agi mail)" } },
        [11] = { { "Wrathful Gladiator's Band of Triumph", 51358, 264, "honor (AP+crit)" } },
        [13] = { { "Medallion of the Alliance", 42123, 200, "PvP trinket (Alliance) - CC break + resil" }, { "Medallion of the Horde", 42122, 200, "PvP trinket (Horde) - CC break + resil" } },
        [18] = { { "Wrathful Gladiator's Longbow", 51394, 264, "bow" }, { "Wrathful Gladiator's Rifle", 51449, 264, "gun" }, { "Wrathful Gladiator's Heavy Crossbow", 51411, 264, "crossbow" } },
    },
    Hunter_SV = {
        [1] = { { "Wrathful Gladiator's Chain Helm", 51460, 270, "arena set" } },
        [2] = { { "Wrathful Gladiator's Pendant of Triumph", 51355, 264, "honor (AP+crit)" }, { "Wrathful Gladiator's Pendant of Victory", 51357, 264, "honor (AP+hit)" } },
        [3] = { { "Wrathful Gladiator's Chain Spaulders", 51462, 270, "arena set" } },
        [15] = { { "Wrathful Gladiator's Cloak of Triumph", 51354, 264, "honor (AP+crit)" }, { "Wrathful Gladiator's Cloak of Victory", 51356, 264, "honor (AP+hit)" } },
        [5] = { { "Wrathful Gladiator's Chain Armor", 51458, 270, "arena set" } },
        [9] = { { "Wrathful Gladiator's Wristguards of Triumph", 51352, 264, "honor (agi mail)" } },
        [10] = { { "Wrathful Gladiator's Chain Gauntlets", 51459, 270, "arena set" } },
        [6] = { { "Wrathful Gladiator's Waistguard of Triumph", 51350, 264, "honor (agi mail)" } },
        [7] = { { "Wrathful Gladiator's Chain Leggings", 51461, 270, "arena set" } },
        [8] = { { "Wrathful Gladiator's Sabatons of Triumph", 51351, 264, "honor (agi mail)" } },
        [11] = { { "Wrathful Gladiator's Band of Triumph", 51358, 264, "honor (AP+crit)" } },
        [13] = { { "Medallion of the Alliance", 42123, 200, "PvP trinket (Alliance) - CC break + resil" }, { "Medallion of the Horde", 42122, 200, "PvP trinket (Horde) - CC break + resil" } },
        [18] = { { "Wrathful Gladiator's Longbow", 51394, 264, "bow" }, { "Wrathful Gladiator's Rifle", 51449, 264, "gun" }, { "Wrathful Gladiator's Heavy Crossbow", 51411, 264, "crossbow" } },
    },
    Rogue_Assass = {
        [1] = { { "Wrathful Gladiator's Leather Helm", 51494, 270, "arena set" } },
        [2] = { { "Wrathful Gladiator's Pendant of Triumph", 51355, 264, "honor (AP+crit)" }, { "Wrathful Gladiator's Pendant of Victory", 51357, 264, "honor (AP+hit)" } },
        [3] = { { "Wrathful Gladiator's Leather Spaulders", 51496, 270, "arena set" } },
        [15] = { { "Wrathful Gladiator's Cloak of Triumph", 51354, 264, "honor (AP+crit)" }, { "Wrathful Gladiator's Cloak of Victory", 51356, 264, "honor (AP+hit)" } },
        [5] = { { "Wrathful Gladiator's Leather Tunic", 51492, 270, "arena set" } },
        [9] = { { "Wrathful Gladiator's Armwraps of Triumph", 51370, 264, "honor (agi leather)" } },
        [10] = { { "Wrathful Gladiator's Leather Gloves", 51493, 270, "arena set" } },
        [6] = { { "Wrathful Gladiator's Belt of Triumph", 51368, 264, "honor (agi leather)" } },
        [7] = { { "Wrathful Gladiator's Leather Legguards", 51495, 270, "arena set" } },
        [8] = { { "Wrathful Gladiator's Boots of Triumph", 51369, 264, "honor (agi leather)" } },
        [11] = { { "Wrathful Gladiator's Band of Triumph", 51358, 264, "honor (AP+crit)" } },
        [13] = { { "Medallion of the Alliance", 42123, 200, "PvP trinket (Alliance) - CC break + resil" }, { "Medallion of the Horde", 42122, 200, "PvP trinket (Horde) - CC break + resil" } },
        [16] = { { "Wrathful Gladiator's Shanker", 51517, 264, "1H dagger" }, { "Wrathful Gladiator's Shiv", 51441, 264, "1H dagger" } },
        [17] = { { "Wrathful Gladiator's Shanker", 51517, 264, "1H dagger" }, { "Wrathful Gladiator's Shiv", 51441, 264, "1H dagger" } },
    },
    Rogue_Subtlety = {
        [1] = { { "Wrathful Gladiator's Leather Helm", 51494, 270, "arena set" } },
        [2] = { { "Wrathful Gladiator's Pendant of Triumph", 51355, 264, "honor (AP+crit)" }, { "Wrathful Gladiator's Pendant of Victory", 51357, 264, "honor (AP+hit)" } },
        [3] = { { "Wrathful Gladiator's Leather Spaulders", 51496, 270, "arena set" } },
        [15] = { { "Wrathful Gladiator's Cloak of Triumph", 51354, 264, "honor (AP+crit)" }, { "Wrathful Gladiator's Cloak of Victory", 51356, 264, "honor (AP+hit)" } },
        [5] = { { "Wrathful Gladiator's Leather Tunic", 51492, 270, "arena set" } },
        [9] = { { "Wrathful Gladiator's Armwraps of Triumph", 51370, 264, "honor (agi leather)" } },
        [10] = { { "Wrathful Gladiator's Leather Gloves", 51493, 270, "arena set" } },
        [6] = { { "Wrathful Gladiator's Belt of Triumph", 51368, 264, "honor (agi leather)" } },
        [7] = { { "Wrathful Gladiator's Leather Legguards", 51495, 270, "arena set" } },
        [8] = { { "Wrathful Gladiator's Boots of Triumph", 51369, 264, "honor (agi leather)" } },
        [11] = { { "Wrathful Gladiator's Band of Triumph", 51358, 264, "honor (AP+crit)" } },
        [13] = { { "Medallion of the Alliance", 42123, 200, "PvP trinket (Alliance) - CC break + resil" }, { "Medallion of the Horde", 42122, 200, "PvP trinket (Horde) - CC break + resil" } },
        [16] = { { "Wrathful Gladiator's Shanker", 51517, 264, "1H dagger" }, { "Wrathful Gladiator's Shiv", 51441, 264, "1H dagger" } },
        [17] = { { "Wrathful Gladiator's Shanker", 51517, 264, "1H dagger" }, { "Wrathful Gladiator's Shiv", 51441, 264, "1H dagger" } },
    },
    Rogue_Combat = {
        [1] = { { "Wrathful Gladiator's Leather Helm", 51494, 270, "arena set" } },
        [2] = { { "Wrathful Gladiator's Pendant of Triumph", 51355, 264, "honor (AP+crit)" }, { "Wrathful Gladiator's Pendant of Victory", 51357, 264, "honor (AP+hit)" } },
        [3] = { { "Wrathful Gladiator's Leather Spaulders", 51496, 270, "arena set" } },
        [15] = { { "Wrathful Gladiator's Cloak of Triumph", 51354, 264, "honor (AP+crit)" }, { "Wrathful Gladiator's Cloak of Victory", 51356, 264, "honor (AP+hit)" } },
        [5] = { { "Wrathful Gladiator's Leather Tunic", 51492, 270, "arena set" } },
        [9] = { { "Wrathful Gladiator's Armwraps of Triumph", 51370, 264, "honor (agi leather)" } },
        [10] = { { "Wrathful Gladiator's Leather Gloves", 51493, 270, "arena set" } },
        [6] = { { "Wrathful Gladiator's Belt of Triumph", 51368, 264, "honor (agi leather)" } },
        [7] = { { "Wrathful Gladiator's Leather Legguards", 51495, 270, "arena set" } },
        [8] = { { "Wrathful Gladiator's Boots of Triumph", 51369, 264, "honor (agi leather)" } },
        [11] = { { "Wrathful Gladiator's Band of Triumph", 51358, 264, "honor (AP+crit)" } },
        [13] = { { "Medallion of the Alliance", 42123, 200, "PvP trinket (Alliance) - CC break + resil" }, { "Medallion of the Horde", 42122, 200, "PvP trinket (Horde) - CC break + resil" } },
        [16] = { { "Wrathful Gladiator's Slicer", 51521, 264, "1H sword" }, { "Wrathful Gladiator's Bonecracker", 51445, 264, "1H mace" }, { "Wrathful Gladiator's Right Ripper", 51523, 264, "fist (MH)" } },
        [17] = { { "Wrathful Gladiator's Slicer", 51521, 264, "1H sword" }, { "Wrathful Gladiator's Bonecracker", 51445, 264, "1H mace" }, { "Wrathful Gladiator's Left Ripper", 51443, 264, "fist (OH)" } },
    },
}

-- Warm the item cache for any populated PvP gear ids on login so links resolve.
local warm = CreateFrame("Frame")
warm:RegisterEvent("PLAYER_ENTERING_WORLD")
warm:SetScript("OnEvent", function()
    if not GetItemInfo then return end
    for _, slots in pairs(PvP.Gear) do
        for _, list in pairs(slots) do
            for _, it in ipairs(list) do if it[2] then GetItemInfo(it[2]) end end
        end
    end
end)

-- Recommended PvP items for the local player's spec + a given inventory slot id.
function PvP.ForSlot(slotId)
    local SG = AIP.SpecGuides
    local key = SG and SG.KeyFor and SG.KeyFor()
    local slots = key and PvP.Gear[key]
    return slots and slots[slotId] or nil
end

function PvP.ForPlayer()
    local SG = AIP.SpecGuides
    local key = SG and SG.KeyFor and SG.KeyFor()
    return key and PvP.List[key] or nil
end
