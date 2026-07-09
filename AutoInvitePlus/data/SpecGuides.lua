-- AutoInvite Plus - Per-spec stat caps + rotation guides (WotLK 3.3.5a)
-- Verified against Icy-Veins WotLK Classic (stat-priority + rotation pages),
-- cross-checked vs Wowhead/Warcraft Tavern. Feeds the Rotation "how to play"
-- guide and the Readiness cap-status readout. Rating constants @80:
--   spell hit 26.23/1% (17%=446, 14%=368, 11%=289 with 3% talent+debuff)
--   melee/ranged hit 32.79/1% (8% special cap = 263)
--   expertise 8.20/1 (26 = ~214 rating), ArP 13.99/1% (1400 hard cap)
--   defense 4.92/1 (540 skill for crit immunity)

local AIP = AutoInvitePlus
if not AIP then return end
AIP.SpecGuides = AIP.SpecGuides or {}
local SG = AIP.SpecGuides

-- caps: hit(rating), hitType(spell|melee|ranged|none), expertise(rating), arp(yes|soft|no), defense(540|nil)
SG.Caps = {
    DK_Blood_DPS   = { hit = 263, hitType = "melee", expertise = 214, arp = "yes", defense = nil, notes = "8% melee first; ArP to 1400 late; Str core." },
    DK_Frost_DPS   = { hit = 263, hitType = "melee", expertise = 214, arp = "yes", defense = nil, notes = "DW but specials only need 8%; hit+exp stressed." },
    DK_Unholy_DPS  = { hit = 263, hitType = "melee", expertise = 214, arp = "yes", defense = nil, notes = "2H; Hit>Str>Haste>ArP; haste scales Ghoul/Gargoyle." },
    DK_Tank        = { hit = 0,   hitType = "spell", expertise = 214, arp = "no",  defense = 540, notes = "540 def = crit-immune first; then Stamina." },
    War_Arms_DPS   = { hit = 263, hitType = "melee", expertise = 214, arp = "yes", defense = nil, notes = "8% first; ArP soft-cap 1400 with proc then beats Str." },
    War_Fury_DPS   = { hit = 263, hitType = "melee", expertise = 214, arp = "yes", defense = nil, notes = "8% covers yellow; white DW cap not chased." },
    War_Prot_Tank  = { hit = 0,   hitType = "melee", expertise = 214, arp = "no",  defense = 540, notes = "540 def then Stam; Hit/Exp threat-only." },
    Druid_Balance  = { hit = 368, hitType = "spell", expertise = 0,   arp = "no",  defense = nil, notes = "~289 (11%) with Misery/IFF debuff, 368 without." },
    Druid_FeralCat = { hit = 263, hitType = "melee", expertise = 214, arp = "yes", defense = nil, notes = "8%; Primal Precision eases exp; ArP best late." },
    Druid_FeralBear= { hit = 263, hitType = "melee", expertise = 214, arp = "no",  defense = 540, notes = "540 def uncrittable; Hit/Exp threat only." },
    Druid_Resto    = { hit = 0,   hitType = "none",  expertise = 0,   arp = "no",  defense = nil, notes = "Haste breakpoints 65/735 (Celestial Focus) or 165/856." },
    Pala_Holy      = { hit = 0,   hitType = "none",  expertise = 0,   arp = "no",  defense = nil, notes = "No hit; Int is king > SP > Crit > Haste > Mp5." },
    Pala_Prot_Tank = { hit = 263, hitType = "melee", expertise = 214, arp = "no",  defense = 540, notes = "540 def then Stam; Hit/Exp threat soft-targets." },
    Pala_Ret_DPS   = { hit = 263, hitType = "melee", expertise = 132, arp = "soft",defense = nil, notes = "8% covers Judgement; Glyph of SoV = +10 exp (need ~132)." },
    Hunter_BM      = { hit = 263, hitType = "ranged",expertise = 0,   arp = "no",  defense = nil, notes = "Usually full 8%/263; keep pet alive." },
    Hunter_MM      = { hit = 164, hitType = "ranged",expertise = 0,   arp = "yes", defense = nil, notes = "Focused Aim 3% -> ~164 from gear; hard-stacks ArP." },
    Hunter_SV      = { hit = 164, hitType = "ranged",expertise = 0,   arp = "no",  defense = nil, notes = "Focused Aim 3% -> ~164; Agi>Crit>AP; no ArP." },
    Rogue_Assass   = { hit = 263, hitType = "melee", expertise = 214, arp = "no",  defense = nil, notes = "8% yellow; aim toward 446 so poisons never miss." },
    Rogue_Combat   = { hit = 263, hitType = "melee", expertise = 214, arp = "yes", defense = nil, notes = "8% yellow; hard-stacks ArP to 1400 (best in ICC)." },
    Rogue_Subtlety = { hit = 263, hitType = "melee", expertise = 214, arp = "soft",defense = nil, notes = "8% yellow; leans on Honor Among Thieves." },
    Sham_Elemental = { hit = 368, hitType = "spell", expertise = 0,   arp = "no",  defense = nil, notes = "Elemental Precision 3% -> 14%/368; Fire Ele snapshots SP." },
    Sham_Enhance   = { hit = 263, hitType = "melee", expertise = 214, arp = "no",  defense = nil, notes = "Dual: melee 8%=263 AND ~368 spell hit for Maelstrom." },
    Sham_Resto     = { hit = 0,   hitType = "none",  expertise = 0,   arp = "no",  defense = nil, notes = "No hard haste breakpoint; stack haste, keep Water Shield." },
    Mage_Arcane    = { hit = 368, hitType = "spell", expertise = 0,   arp = "no",  defense = nil, notes = "14%/368 (no hit talent); ~289 with 3/3 Arcane Focus + debuff." },
    Mage_Fire      = { hit = 368, hitType = "spell", expertise = 0,   arp = "no",  defense = nil, notes = "14%/368 (no hit talent); stack haste after hit." },
    Mage_Frost     = { hit = 289, hitType = "spell", expertise = 0,   arp = "no",  defense = nil, notes = "11%/289 = Precision 3% + debuff." },
    Priest_Disc    = { hit = 0,   hitType = "none",  expertise = 0,   arp = "no",  defense = nil, notes = "Healer; Spirit/regen + SP + Haste to GCD." },
    Priest_Holy    = { hit = 0,   hitType = "none",  expertise = 0,   arp = "no",  defense = nil, notes = "Healer; Spirit/regen + SP + Crit (Holy Concentration)." },
    Priest_Shadow  = { hit = 289, hitType = "spell", expertise = 0,   arp = "no",  defense = nil, notes = "11%/289 = Shadow Focus 3% + self Misery 3%." },
    Warlock_Affli  = { hit = 289, hitType = "spell", expertise = 0,   arp = "no",  defense = nil, notes = "11%/289 = Suppression 3% + debuff; 368 without." },
    Warlock_Demo   = { hit = 368, hitType = "spell", expertise = 0,   arp = "no",  defense = nil, notes = "14%/368 default (no Suppression in deep Demo)." },
    Warlock_Destro = { hit = 368, hitType = "spell", expertise = 0,   arp = "no",  defense = nil, notes = "14%/368 default (no Suppression in deep Destro)." },
}

SG.Rotations = {
    DK_Blood_DPS = { "Open: Army pre-pull, IT>PS>Death Strike>Heart Strike; stack Dancing Rune Weapon+ERW early.", "Keep Frost Fever + Blood Plague up via Pestilence; don't re-cast IT/PS needlessly.", "Death Rune Mastery = ~4 Heart Strikes in a row; Blood Tap for extra.", "Dump excess Runic Power with Death Coil so you never RP-cap.", "Mistake: letting diseases fall off or sitting on cooldowns." },
    DK_Frost_DPS = { "Open (Blood Presence): IT>PS>Obliterate, Pestilence, ERW, Obliterate x3.", "Frost+Unholy runes -> Obliterate; Blood runes -> Pestilence; dump RP with Frost Strike.", "Killing Machine -> instant Frost Strike (guaranteed crit); Rime -> free Howling Blast.", "Never Howling Blast without Rime on single target.", "Always spend runes before Runic Power." },
    DK_Unholy_DPS = { "Open (Unholy Presence): diseases, Blood Strikes, D&D, Ghoul Frenzy, Gargoyle, ERW, Army.", "Keep diseases up, Ghoul attacking; Scourge Strike main, Blood Strike to keep Desolation.", "Fire Gargoyle while haste buffs/procs are active (it scales 100% with haste).", "Don't cast D&D on pure single-target (wastes strike runes).", "Mistake: losing Desolation or Ghoul uptime." },
    DK_Tank = { "Pull: Death Grip>IT>PS>Death Strike; Frost Presence (Icy Touch = huge threat).", "Maximize Icy Touch, keep diseases via Pestilence, press Rune Strike whenever available.", "AoE: D&D>IT>Pestilence>Blood Boil.", "Death Strike to self-heal spikes; Vampiric Blood/Icebound/AMS/Rune Tap reactively.", "Mistake: tunneling damage over defensives." },
    War_Arms_DPS = { "Always keep Rend up (feeds Taste for Blood -> Overpower).", "Priority: Overpower proc > Bladestorm on CD > Mortal Strike > Slam filler.", "Execute below 20% or on Sudden Death procs.", "Heroic Strike only above ~40 rage.", "Mistake: letting Rend expire or wasting Overpower procs." },
    War_Fury_DPS = { "Keep Sunder up, then Bloodthirst > Whirlwind > Slam (only on Bloodsurge) > Execute.", "Heroic Strike off-GCD above ~40 rage to avoid rage-capping.", "Bloodsurge proc -> instant Slam immediately.", "Stack Recklessness + Death Wish + Berserker Rage for burst.", "Mistake: Slam without a Bloodsurge proc, and rage-capping." },
    War_Prot_Tank = { "Loop: Shield Slam > Revenge > Devastate filler (S&B resets Shield Slam) > Shockwave.", "Heroic Strike above ~60 rage (Cleave for multi-target).", "AoE: Thunder Clap > Shockwave > Revenge > Cleave.", "Shield Block proactively into physical spikes; Shield Wall/Last Stand emergencies.", "Mistake: missing Shield Slam in Shield Block windows and rage-capping." },
    Druid_Balance = { "Open: Faerie Fire + Insect Swarm + Moonfire, Starfall + Force of Nature, cast toward first Eclipse.", "Lunar -> spam Starfire; Solar -> spam Wrath; between procs cast toward next Eclipse.", "Keep IS + Moonfire up but never clip them or break an Eclipse to refresh.", "Moonfire is your instant filler only while moving.", "Line up trinkets/Lust/pot with an active Eclipse." },
    Druid_FeralCat = { "Open: Mangle, build with Shred, Rake, 5-CP Rip, Savage Roar.", "Keep Savage Roar/Rip/Rake/Mangle up; refresh AFTER expiry, never clip a bleed.", "Pool energy (~90 before Berserk); keep enough to refresh a falling Rip/Rake.", "Tiger's Fury below ~40 energy; Berserk when TF has 15s+ left.", "Swap Rip->Ferocious Bite only if target dies before Rip pays out." },
    Druid_FeralBear = { "Open: Faerie Fire on pull, Mangle, stack Lacerate.", "Priority: Mangle on CD > Faerie Fire on CD > Lacerate to 5 & refresh > Maul/Swipe with spare rage.", "Do NOT use Enrage mid-fight (lowers armor); pre-pull only.", "Barkskin near-100% uptime; Survival Instincts/Frenzied Regen for spikes.", "Pre-empt spikes with cooldowns, don't react late." },
    Druid_Resto = { "Keep Lifebloom on tank and Rejuvenation rolling on damaged targets (favor melee for Revitalize).", "Wild Growth on CD when 3+ hurt; fit 4-5 Rejuvs between casts.", "Fill with Nourish (scales with your HoTs), not spammed Regrowth.", "Emergency: Nature's Swiftness + Healing Touch; Swiftmend when NS is on CD.", "Don't overwrite a fresh Lifebloom stack." },
    Pala_Holy = { "Beacon of Light on tank + Sacred Shield refreshed; spam max-rank Holy Light on a 2nd target.", "Judge Seal of Wisdom every ~60s to keep Judgements of the Pure haste.", "Flash of Light only for spot heals; Holy Shock instant on the move.", "CDs: Divine Illumination heavy phases, Divine Favor clutch crit, Lay on Hands to save a life.", "Mistake: main-healing with Flash or letting Beacon/Sacred Shield/Judgement drop." },
    Pala_Prot_Tank = { "969: alternate a 9s ability (ShoR/Holy Shield) with a 6s (HotR/Judgement/Consecration/Avenger's Shield).", "Open: Judgement or Avenger's Shield, drop Consecration + Holy Shield before the boss lands.", "Single: ShoR > HotR > Judgement > Consecration > Holy Shield ~100% uptime.", "AoE: Seal of Command, lead Avenger's Shield + Consecration + HotR.", "Avenging Wrath threat, Divine Protection for spikes." },
    Pala_Ret_DPS = { "Seal of Vengeance single-target (Glyph of SoV mandatory); Seal of Command on 2+.", "FCFS: Crusader Strike > Judgement > Divine Storm > Exorcism (Art of War) > Consecration > Holy Wrath.", "Art of War -> instant free Exorcism, but never clip a higher-priority ability.", "Avenging Wrath in burn phases (locks bubble ~1 min).", "Divine Plea for mana; never let the GCD idle." },
    Hunter_BM = { "Open: Hunter's Mark + Dragonhawk, Serpent Sting, Bestial Wrath + Rapid Fire + Kill Command.", "Priority: Kill Shot > Kill Command on CD (macro off-GCD) > Serpent Sting > Steady Shot filler.", "Bestial Wrath every ~2 min.", "Keep pet alive/on-target, 5 Frenzy stacks, Mend Pet up.", "Don't over-Arcane-Shot into mana starvation." },
    Hunter_MM = { "Open: Mark + Dragonhawk, Serpent Sting, all CDs, Kill Command > Chimera > Aimed, Readiness for double burst.", "Priority: Kill Shot > Kill Command > Serpent Sting up > Chimera > Aimed > Steady filler.", "Chimera auto-refreshes Serpent Sting - never reapply manually.", "Careful Aim: Int -> ranged AP; Rapid Fire on CD.", "Don't clip Steady Shot casts." },
    Hunter_SV = { "Open: Mark + Dragonhawk, Serpent Sting, Black Arrow, Explosive Shot + Rapid Fire.", "Priority: Kill Shot > Explosive on CD > Black Arrow (feeds Lock and Load) > Serpent Sting > Kill Command > Steady.", "Lock and Load: fire the free Explosive Shots immediately.", "Never let Explosive Shot or Black Arrow sit off CD.", "(True 3.3.5a keeps Black Arrow.)" },
    Rogue_Assass = { "Open: Mutilate > Slice and Dice > Rupture > Hunger for Blood > build > Envenom.", "Mutilate to build, Envenom at 4-5 CP.", "Keep SnD, Rupture and Hunger for Blood up 100% (HfB needs a bleed).", "Cold Blood + Envenom = guaranteed crit; Tricks on the tank.", "Don't let HfB drop or clip Envenom." },
    Rogue_Combat = { "Open: Slice and Dice ASAP, keep Rupture up, fill with Sinister Strike.", "Priority: SnD > Rupture > Eviscerate at 5 CP; Sinister Strike builds.", "Stagger Blade Flurry > Killing Spree > Adrenaline Rush to avoid energy overcap.", "Don't fire Killing Spree + Adrenaline Rush together; keep Glyph of Killing Spree.", "Fan of Knives only at 3+ targets." },
    Rogue_Subtlety = { "Open: Hemorrhage to 4-5 CP > Slice and Dice > Rupture.", "Priority: Expose Armor (no Warr) > SnD > Rupture; Hemorrhage filler + raid debuff.", "Most CP from Honor Among Thieves (group crits).", "Shadowstep before Rupture; during Shadow Dance prioritize Ambush.", "Don't let SnD/Rupture drop." },
    Sham_Elemental = { "Open: totems (Totem of Wrath, Wrath of Air, Flametongue), Elemental Mastery, Flame Shock, Lava Burst.", "Priority: Flame Shock up > Lava Burst only while FS active (guaranteed crit) > Lightning Bolt > Chain Lightning 2+.", "Spend Clearcasting on free Lightning Bolts.", "Never Lava Burst without Flame Shock up.", "Swap to max-SP before Fire Elemental Totem (it snapshots)." },
    Sham_Enhance = { "Open: totems, Feral Spirit + Fire Elemental.", "Priority: 5-stack Maelstrom -> instant Lightning Bolt > Stormstrike > Flame Shock up > Lava Lash > Earth Shock > Fire Nova.", "Weave Maelstrom LB between white swings; keep Lightning Shield up.", "Don't let totems/Flame Shock drop or Earth Shock single-target with Maelstrom.", "Shamanistic Rage on CD for mana." },
    Sham_Resto = { "Keep Earth Shield on tank and Water Shield on self (mana engine).", "Priority: Riptide on CD (procs Tidal Waves) > Chain Heal groups > Healing Wave heavy tank > LHW spot.", "Always spend Tidal Waves right after Riptide.", "Emergency: Nature's Swiftness + Healing Wave; Mana Tide when low.", "Don't downrank (no mana benefit)." },
    Mage_Arcane = { "Open: pre-pot + Mirror Image, start stacking Arcane Blast.", "Core: 4x Arcane Blast then Arcane Missiles, repeat; Missile Barrage -> Missiles immediately.", "Burst: Presence of Mind + Arcane Power + Icy Veins/trinket/pot; Mana Gem on CD.", "Evocation when low; keep a mana buffer for burn.", "Don't clip the Missiles channel." },
    Mage_Fire = { "Open: pre-pot, Living Bomb > Fireball filler; keep Improved Scorch up if you're the debuff source.", "Living Bomb 100% uptime takes priority even over a Hot Streak Pyroblast.", "Hot Streak (2 crits) -> instant Pyroblast immediately.", "Combustion macro'd with Fireball + trinkets/pot, on CD.", "Don't clip Living Bomb before its final tick." },
    Mage_Frost = { "Keep Water Elemental summoned; Frostbolt is your main filler.", "Fingers of Frost: after 2 Frostbolts use Deep Freeze (Shatter crit); spend FoF on Ice Lance while moving.", "Brain Freeze -> instant Frostfire Bolt.", "Icy Veins on pull then Cold Snap reset." },
    Priest_Disc = { "Power Word: Shield is priority - pre-shield anyone about to take damage (Rapture mana + Borrowed Time).", "Penance on CD (builds Grace); keep Prayer of Mending rolling.", "Flash Heal filler; Greater Heal for big hits; Prayer of Healing only under Borrowed Time.", "CDs: Pain Suppression tank spikes, Power Infusion throughput, Divine Hymn emergency.", "Don't hard-cast slow heals when a shield/instant suffices." },
    Priest_Holy = { "Prayer of Mending on CD and Renew rolling; Circle of Healing on CD for group AoE.", "Build Serendipity with Flash/Binding Heal to speed Greater Heal / Prayer of Healing.", "Flash filler, Greater Heal big hits, Binding Heal when also hurt, Prayer of Healing on stacked raid.", "Guardian Spirit tank; Divine Hymn emergency; Hymn of Hope mana.", "Don't spam slow Greater Heals into overheal." },
    Priest_Shadow = { "Open: build 5 Shadow Weaving, then VT > Devouring Plague > SW:Pain > Mind Blast > Mind Flay.", "Priority: VT 100% (feeds Replenishment) > Devouring Plague on CD > Mind Blast on CD > Mind Flay filler.", "SW:Pain is refreshed free by Mind Flay - never re-hardcast it.", "SW:Death only while moving; keep DoTs from ever dropping." },
    Warlock_Affli = { "Open: pre-pot, Haunt > Unstable Affliction > Corruption > Curse of Agony (Doom long fights) > Shadow Bolt.", "Keep Haunt, UA, Corruption and Curse up 100% without clipping.", "Below 25% swap filler to Drain Soul (huge execute) while keeping DoTs rolling.", "Don't clip UA early or let Haunt drop; AoE = Seed of Corruption (watch threat)." },
    Warlock_Demo = { "Open: pre-pot, Life Tap, Metamorphosis, Immolate, Corruption, Curse, Shadow Bolt filler.", "Keep Immolate + Corruption up 100% for Molten Core; spend each Molten Core on Incinerate.", "Below 35% switch filler to Soul Fire (also consumes Molten Core).", "Pop Metamorphosis with trinket/pot; keep the 5% crit debuff up for the raid." },
    Warlock_Destro = { "Open: pre-cast Soul Fire to land on the pull, pre-pot, Curse of Doom + Immolate.", "Keep Immolate 100%; Conflagrate on CD for Backdraft; Chaos Bolt on CD; Incinerate filler.", "Corruption is a DPS loss full-time - cast only while moving.", "Don't let Conflagrate/Chaos Bolt sit off-CD; dump Backdraft into Incinerate/Chaos Bolt." },
}

-- DoTs / maintained buffs the overlay tracks on the target (or player) and warns
-- when they drop. { name, baseDuration, unit } - unit "player" for self-buffs,
-- default "target". Names must match the in-game aura name exactly (UnitAura).
-- Only real player-applied effects; conditional raid-debuffs (Sunder, Expose,
-- Faerie Fire, Curse of the Elements) are omitted to avoid false warnings.
SG.DoTs = {
    DK_Blood_DPS   = { { "Frost Fever", 21 }, { "Blood Plague", 21 } },
    DK_Frost_DPS   = { { "Frost Fever", 21 }, { "Blood Plague", 21 } },  -- 21s w/ Epidemic (DW build); 15s on a 2H build w/o Epidemic
    DK_Unholy_DPS  = { { "Frost Fever", 21 }, { "Blood Plague", 21 } },
    War_Arms_DPS   = { { "Rend", 15 } },
    Rogue_Assass   = { { "Slice and Dice", 21, "player" }, { "Hunger for Blood", 60, "player" }, { "Rupture", 16 } },
    Rogue_Combat   = { { "Slice and Dice", 21, "player" }, { "Rupture", 16 } },
    Rogue_Subtlety = { { "Slice and Dice", 21, "player" }, { "Rupture", 16 }, { "Hemorrhage", 15 } },
    Druid_Balance  = { { "Moonfire", 12 }, { "Insect Swarm", 12 } },
    Druid_FeralCat = { { "Rip", 16 }, { "Rake", 9 }, { "Savage Roar", 34, "player" } },  -- Rip 16s at 5 CP (20s glyphed)
    Hunter_BM      = { { "Serpent Sting", 15 } },
    Hunter_MM      = { { "Serpent Sting", 15 } },
    Hunter_SV      = { { "Serpent Sting", 15 }, { "Black Arrow", 15 } },
    Sham_Elemental = { { "Flame Shock", 18 } },
    Sham_Enhance   = { { "Flame Shock", 18 } },
    Mage_Fire      = { { "Living Bomb", 12 } },
    Priest_Shadow  = { { "Vampiric Touch", 15 }, { "Devouring Plague", 24 }, { "Shadow Word: Pain", 18 } },
    Warlock_Affli  = { { "Haunt", 12 }, { "Unstable Affliction", 15 }, { "Corruption", 18 }, { "Curse of Agony", 24 } },
    Warlock_Demo   = { { "Immolate", 15 }, { "Corruption", 18 } },
    Warlock_Destro = { { "Immolate", 15 } },
}

-- Free-instant / empowered-cast procs to surface (buff name -> what it enables).
SG.Procs = {
    DK_Frost_DPS   = { { "Freezing Fog", "free Howling Blast" }, { "Killing Machine", "guaranteed-crit Frost Strike/Obliterate" } },
    DK_Unholy_DPS  = { { "Sudden Doom", "free Death Coil" } },
    War_Arms_DPS   = { { "Taste for Blood", "Overpower now" }, { "Sudden Death", "Execute now" } },
    War_Fury_DPS   = { { "Bloodsurge", "instant Slam now" } },
    Druid_Balance  = { { "Eclipse (Lunar)", "empowered Starfire" }, { "Eclipse (Solar)", "empowered Wrath" } },
    Druid_FeralCat = { { "Clearcasting", "free Shred" } },
    Pala_Ret_DPS   = { { "The Art of War", "instant Exorcism" } },
    Hunter_SV      = { { "Lock and Load", "free Explosive Shots" } },
    Sham_Enhance   = { { "Maelstrom Weapon", "instant Lightning Bolt (5 stacks)" } },
    Mage_Arcane    = { { "Missile Barrage", "free Arcane Missiles" } },
    Mage_Fire      = { { "Hot Streak", "instant Pyroblast" } },
    Mage_Frost     = { { "Brain Freeze", "instant Frostfire Bolt" }, { "Fingers of Frost", "Ice Lance / Deep Freeze" } },
    Warlock_Affli  = { { "Shadow Trance", "instant Shadow Bolt" } },
    Warlock_Demo   = { { "Molten Core", "empowered Incinerate" }, { "Decimation", "fast Soul Fire (<35%)" } },
    Warlock_Destro = { { "Backdraft", "faster Incinerate/Chaos Bolt" } },
}

-- AoE / multi-target priority (2-3+ targets).
SG.AoE = {
    DK_Blood_DPS   = { "Icy Touch + Plague Strike", "Pestilence (spread)", "Death and Decay", "Blood Boil", "Heart Strike" },
    DK_Frost_DPS   = { "Howling Blast (spreads Frost Fever)", "Pestilence", "Blood Boil", "Death and Decay", "Frost Strike" },
    DK_Unholy_DPS  = { "Icy Touch + Plague Strike", "Pestilence (spread)", "Death and Decay", "Blood Boil", "Scourge Strike" },
    War_Arms_DPS   = { "Sweeping Strikes", "Bladestorm", "Thunder Clap", "Overpower", "Cleave" },
    War_Fury_DPS   = { "Whirlwind", "Bloodthirst", "Thunder Clap", "Cleave (rage dump)" },
    Rogue_Assass   = { "Fan of Knives (6+ targets)", "keep Slice and Dice up", "else single-target" },
    Rogue_Combat   = { "Fan of Knives (3+ targets)", "keep Slice and Dice up", "Blade Flurry" },
    Rogue_Subtlety = { "Fan of Knives (6+ targets)", "keep Slice and Dice up" },
    Druid_Balance  = { "Starfall", "Hurricane", "Typhoon (glyph)", "multi-dot Moonfire/Insect Swarm" },
    Druid_FeralCat = { "Tiger's Fury / Berserk", "Savage Roar", "Swipe (Cat)" },
    Pala_Ret_DPS   = { "Seal of Command", "Divine Storm", "Consecration", "Holy Wrath (undead/demon)", "Judgement + Crusader Strike" },
    Hunter_BM      = { "Explosive Trap", "Volley", "Multi-Shot", "Serpent Sting", "Kill Command" },
    Hunter_MM      = { "Volley", "Multi-Shot", "Explosive Trap", "Chimera on primary" },
    Hunter_SV      = { "Explosive Trap", "Volley", "Multi-Shot", "Black Arrow", "Explosive Shot (free on L&L)" },
    Sham_Elemental = { "Magma Totem", "Fire Nova", "Chain Lightning", "Thunderstorm (glyph)" },
    Sham_Enhance   = { "Magma Totem", "Fire Nova", "Chain Lightning (5 Maelstrom)", "Stormstrike", "Lava Lash" },
    Mage_Arcane    = { "Blizzard (stationary, weave Flamestrike)", "Arcane Explosion (mobile)" },
    Mage_Fire      = { "Living Bomb (if targets live ~12s)", "Dragon's Breath", "instant Flamestrike (Firestarter)", "Blast Wave", "Blizzard" },
    Mage_Frost     = { "Blizzard (weave Flamestrike; FoF procs off ticks)", "Arcane Explosion (mobile)" },
    Priest_Shadow  = { "Mind Sear (channel)", "keep VT/DP/SW:P on main if pack lives" },
    Warlock_Affli  = { "Seed of Corruption (spam)", "Curse of Agony on long-lived target", "Soulshatter for threat" },
    Warlock_Demo   = { "Seed of Corruption", "keep Immolate/Corruption on main", "Rain of Fire" },
    Warlock_Destro = { "Seed of Corruption", "Rain of Fire (layer on detonations)", "Immolate/Conflagrate on priority" },
}

-- Talent build variations - { name, whenToUse }. Empty = single cookie-cutter.
SG.Variants = {
    DK_Frost_DPS   = { { "Blood/Frost 2H (17/54/0)", "strong in lower gear; 15s diseases" }, { "Unholy/Frost DW (0/54/17)", "scales with strong 1H; 21s diseases" } },
    DK_Unholy_DPS  = { { "Unholy DW", "standard most phases" }, { "Scourge Strike 2H", "late-phase with Shadowmourne + Sigil of Virulence" } },
    Rogue_Combat   = { { "Combat Swords", "Sword Specialization" }, { "Combat Daggers / CQC", "Close Quarters Combat - match your best weapons" } },
    Druid_Balance  = { { "Standard Eclipse (deep Balance ~57)", "max single-target throughput" }, { "Typhoon / Starfall utility", "Gale Winds for heavy AoE / movement" } },
    Druid_FeralCat = { { "Standard bleed w/ Berserk (0/55/16)", "max DPS on patchwerk fights" }, { "No-Berserk mobility", "survivability on high-movement fights" } },
    Pala_Ret_DPS   = { { "Standard 0/18/53", "Prot dip for Divine Sacrifice / Improved Judgements - best utility" }, { "Deeper Ret 0/15/56", "pure personal DPS, less utility" } },
    Hunter_MM      = { { "MM 7/57/7", "standard" }, { "Focused Aim <-> Imp. Steady Shot", "swap by your hit rating" } },
    Mage_Fire      = { { "Standard Fireball / TTW", "highest ceiling" }, { "Frostfire Bolt (FFB) build", "more forgiving on some gear" } },
}

-- class + primary tree -> guide key (tank overrides via archetype).
local KEY = {
    DEATHKNIGHT = { "DK_Blood_DPS", "DK_Frost_DPS", "DK_Unholy_DPS" },
    WARRIOR     = { "War_Arms_DPS", "War_Fury_DPS", "War_Prot_Tank" },
    DRUID       = { "Druid_Balance", "Druid_FeralCat", "Druid_Resto" },
    PALADIN     = { "Pala_Holy", "Pala_Prot_Tank", "Pala_Ret_DPS" },
    HUNTER      = { "Hunter_BM", "Hunter_MM", "Hunter_SV" },
    ROGUE       = { "Rogue_Assass", "Rogue_Combat", "Rogue_Subtlety" },
    SHAMAN      = { "Sham_Elemental", "Sham_Enhance", "Sham_Resto" },
    MAGE        = { "Mage_Arcane", "Mage_Fire", "Mage_Frost" },
    PRIEST      = { "Priest_Disc", "Priest_Holy", "Priest_Shadow" },
    WARLOCK     = { "Warlock_Affli", "Warlock_Demo", "Warlock_Destro" },
}

function SG.KeyFor()
    local _, class = UnitClass("player")
    local tree = (AIP.ItemScore and AIP.ItemScore.PrimaryTree and AIP.ItemScore.PrimaryTree()) or 1
    local key = KEY[class] and KEY[class][tree]
    local arch = AIP.ItemScore and AIP.ItemScore.PlayerArchetype and AIP.ItemScore.PlayerArchetype()
    if arch == "tank" then
        if class == "DEATHKNIGHT" then key = "DK_Tank"
        elseif class == "DRUID" then key = "Druid_FeralBear" end
    end
    return key
end
