-- AutoInvite Plus - Atlas-style boss-drop database (WotLK 3.3.5a endgame raids).
-- Pass 1 coverage: ICC 10/25, Ruby Sanctum 10/25, Trial of the Crusader 10/25,
-- Vault of Archavon 10/25, Onyxia's Lair 10/25. (Ulduar / Naxxramas / OS / EoE
-- are a planned follow-up pass.)
--
-- DATA HONESTY (BiSData.lua / GearUpgrades.lua rule):
--   * `id` is present ONLY where the 3.3.5a itemID is verified (cross-checked
--     against this addon's web-verified BiSData/GearUpgrades tables where they
--     overlap). Where only the item NAME is reliably known, id = nil and the
--     UI's Link() falls back to plain "[Name]" text - never a wrong item link.
--   * Every id is additionally name-guarded at link time (first word of the
--     resolved item name must match the stored name), so a stale/wrong id
--     degrades to text instead of linking the wrong item.
--   * `rate` is nil unless genuinely known: quest/guaranteed drops are 100,
--     famous mounts carry their commonly-cited figure. No guessed percentages.
--   * `hc = true` marks the heroic-mode version, folded into the same instance
--     entry (ICC 10-player heroic items share names with 10-normal and are not
--     duplicated; the Marks of Sanctification that 10-heroic wing bosses drop
--     are listed as hc entries).
--
-- Item row: { id = itemID|nil, name = "...", slot = "...", hc = true|nil,
--             rate = number|nil, note = "..."|nil }

local AIP = AutoInvitePlus
if not AIP then return end
AIP.LootDB = AIP.LootDB or {}
local LDB = AIP.LootDB

LDB.Instances = {

  ------------------------------------------------------------------
  -- ICECROWN CITADEL (10)  - normal ilvl 251 (10H shares item names)
  ------------------------------------------------------------------
  {
    key = "ICC10", name = "Icecrown Citadel (10)",
    bosses = {
      { name = "Lord Marrowgar", items = {
          { id = 50771, name = "Frost Needle", slot = "One-Hand Sword", hc = nil, rate = nil, note = nil },
          { id = nil,   name = "Marrowgar's Frigid Eye", slot = "Ring", hc = nil, rate = nil, note = nil },
          { id = 50775, name = "Corrupted Silverplate Leggings", slot = "Plate Legs", hc = nil, rate = nil, note = nil },
          { id = nil,   name = "Snowserpent Mail Helm", slot = "Mail Helm", hc = nil, rate = nil, note = nil },
          { id = nil,   name = "Rusted Bonespike Pauldrons", slot = "Shoulders", hc = nil, rate = nil, note = nil },
          { id = nil,   name = "Coldwraith Bracers", slot = "Bracers", hc = nil, rate = nil, note = nil },
          { id = nil,   name = "Shawl of Nerubian Silk", slot = "Cloak", hc = nil, rate = nil, note = nil },
          { id = nil,   name = "Ancient Skeletal Boots", slot = "Boots", hc = nil, rate = nil, note = nil },
      }},
      { name = "Lady Deathwhisper", items = {
          { id = nil, name = "Njorndar Bone Bow", slot = "Bow", hc = nil, rate = nil, note = nil },
          { id = nil, name = "The Lady's Promise", slot = "Ring", hc = nil, rate = nil, note = nil },
          { id = nil, name = "Cultist's Bloodsoaked Spaulders", slot = "Shoulders", hc = nil, rate = nil, note = nil },
      }},
      { name = "Icecrown Gunship Battle", items = {
          { id = nil, name = "Midnight Sun", slot = "One-Hand Sword", hc = nil, rate = nil, note = nil },
          { id = nil, name = "Frost Giant's Cleaver", slot = "One-Hand Axe", hc = nil, rate = nil, note = nil },
          { id = nil, name = "Saronite Plated Legguards", slot = "Plate Legs", hc = nil, rate = nil, note = nil },
          { id = nil, name = "Ice-Reinforced Vrykul Helm", slot = "Helm", hc = nil, rate = nil, note = nil },
      }},
      { name = "Deathbringer Saurfang", items = {
          { id = nil, name = "Ramaladni's Blade of Culling", slot = "One-Hand Weapon", hc = nil, rate = nil, note = nil },
          { id = nil, name = "Mag'hari Chieftain's Staff", slot = "Staff", hc = nil, rate = nil, note = nil },
          { id = nil, name = "Gargoyle Spit Bracers", slot = "Bracers", hc = nil, rate = nil, note = nil },
          { id = 52025, name = "Conqueror's Mark of Sanctification", slot = "Tier Token", hc = true, rate = nil, note = "10H - Paladin/Priest/Warlock" },
          { id = 52026, name = "Protector's Mark of Sanctification", slot = "Tier Token", hc = true, rate = nil, note = "10H - Warrior/Hunter/Shaman" },
          { id = 52027, name = "Vanquisher's Mark of Sanctification", slot = "Tier Token", hc = true, rate = nil, note = "10H - DK/Druid/Mage/Rogue" },
      }},
      { name = "Festergut", items = {
          { id = nil, name = "Gutbuster", slot = "One-Hand Axe", hc = nil, rate = nil, note = nil },
          { id = nil, name = "Abomination Knuckles", slot = "Fist Weapon", hc = nil, rate = nil, note = nil },
      }},
      { name = "Rotface", items = {
          { id = nil, name = "Lockjaw", slot = "Dagger", hc = nil, rate = nil, note = nil },
          { id = nil, name = "Ether-Soaked Bracers", slot = "Bracers", hc = nil, rate = nil, note = nil },
      }},
      { name = "Professor Putricide", items = {
          { id = nil, name = "Unclean Surgical Gloves", slot = "Gloves", hc = nil, rate = nil, note = nil },
          { id = nil, name = "Rippling Flesh Kilt", slot = "Legs", hc = nil, rate = nil, note = nil },
          { id = 52025, name = "Conqueror's Mark of Sanctification", slot = "Tier Token", hc = true, rate = nil, note = "10H - Paladin/Priest/Warlock" },
          { id = 52026, name = "Protector's Mark of Sanctification", slot = "Tier Token", hc = true, rate = nil, note = "10H - Warrior/Hunter/Shaman" },
          { id = 52027, name = "Vanquisher's Mark of Sanctification", slot = "Tier Token", hc = true, rate = nil, note = "10H - DK/Druid/Mage/Rogue" },
      }},
      { name = "Blood Prince Council", items = {
          { id = nil, name = "Taldaram's Plated Fists", slot = "Gloves", hc = nil, rate = nil, note = nil },
      }},
      { name = "Blood-Queen Lana'thel", items = {
          { id = nil, name = "Bloodsipper", slot = "One-Hand Weapon", hc = nil, rate = nil, note = nil },
          { id = 52025, name = "Conqueror's Mark of Sanctification", slot = "Tier Token", hc = true, rate = nil, note = "10H - Paladin/Priest/Warlock" },
          { id = 52026, name = "Protector's Mark of Sanctification", slot = "Tier Token", hc = true, rate = nil, note = "10H - Warrior/Hunter/Shaman" },
          { id = 52027, name = "Vanquisher's Mark of Sanctification", slot = "Tier Token", hc = true, rate = nil, note = "10H - DK/Druid/Mage/Rogue" },
      }},
      { name = "Valithria Dreamwalker", items = {
          { id = nil, name = "Emerald Saint's Spaulders", slot = "Shoulders", hc = nil, rate = nil, note = nil },
          { id = nil, name = "Sister's Handshrouds", slot = "Gloves", hc = nil, rate = nil, note = nil },
      }},
      { name = "Sindragosa", items = {
          { id = nil, name = "Rimetooth Pendant", slot = "Neck", hc = nil, rate = nil, note = nil },
          { id = 52025, name = "Conqueror's Mark of Sanctification", slot = "Tier Token", hc = true, rate = nil, note = "10H - Paladin/Priest/Warlock" },
          { id = 52026, name = "Protector's Mark of Sanctification", slot = "Tier Token", hc = true, rate = nil, note = "10H - Warrior/Hunter/Shaman" },
          { id = 52027, name = "Vanquisher's Mark of Sanctification", slot = "Tier Token", hc = true, rate = nil, note = "10H - DK/Druid/Mage/Rogue" },
      }},
      { name = "The Lich King", items = {
          { id = nil, name = "Troggbane, Axe of the Frostborne King", slot = "Two-Hand Axe", hc = nil, rate = nil, note = nil },
          { id = nil, name = "Tel'thas, Dagger of the Blood King", slot = "Dagger", hc = nil, rate = nil, note = "caster" },
          { id = nil, name = "Valius, Gavel of the Silver Hand", slot = "One-Hand Mace", hc = nil, rate = nil, note = "healer" },
          { id = 52025, name = "Conqueror's Mark of Sanctification", slot = "Tier Token", hc = true, rate = nil, note = "10H - Paladin/Priest/Warlock" },
          { id = 52026, name = "Protector's Mark of Sanctification", slot = "Tier Token", hc = true, rate = nil, note = "10H - Warrior/Hunter/Shaman" },
          { id = 52027, name = "Vanquisher's Mark of Sanctification", slot = "Tier Token", hc = true, rate = nil, note = "10H - DK/Druid/Mage/Rogue" },
      }},
      { name = "Trash", items = {
          { id = nil, name = "Saronite Gargoyle Cloak", slot = "Cloak", hc = nil, rate = nil, note = "BoE trash drop" },
          { id = nil, name = "Bone Drake's Enameled Boots", slot = "Boots", hc = nil, rate = nil, note = "BoE trash drop" },
          { id = nil, name = "Ancient Corroded Leggings", slot = "Legs", hc = nil, rate = nil, note = "BoE trash drop" },
      }},
    },
  },

  ------------------------------------------------------------------
  -- ICECROWN CITADEL (25)  - normal ilvl 264, heroic (hc) ilvl 277
  ------------------------------------------------------------------
  {
    key = "ICC25", name = "Icecrown Citadel (25)",
    bosses = {
      { name = "Lord Marrowgar", items = {
          { id = 50339, name = "Sliver of Pure Ice", slot = "Trinket", hc = nil, rate = nil, note = "caster mana return" },
          { id = 50346, name = "Sliver of Pure Ice", slot = "Trinket", hc = true, rate = nil, note = nil },
          { id = 50352, name = "Corpse Tongue Coin", slot = "Trinket", hc = nil, rate = nil, note = "tank armor proc" },
          { id = 50349, name = "Corpse Tongue Coin", slot = "Trinket", hc = true, rate = nil, note = nil },
          { id = 49976, name = "Bulwark of Smouldering Steel", slot = "Shield", hc = nil, rate = nil, note = nil },
          { id = 50616, name = "Bulwark of Smouldering Steel", slot = "Shield", hc = true, rate = nil, note = nil },
          { id = 49975, name = "Bone Sentinel's Amulet", slot = "Neck", hc = nil, rate = nil, note = nil },
          { id = 49949, name = "Band of the Bone Colossus", slot = "Ring", hc = nil, rate = nil, note = nil },
          { id = 50604, name = "Band of the Bone Colossus", slot = "Ring", hc = true, rate = nil, note = nil },
          { id = 49950, name = "Frostbitten Fur Boots", slot = "Boots", hc = nil, rate = nil, note = nil },
          { id = 50607, name = "Frostbitten Fur Boots", slot = "Boots", hc = true, rate = nil, note = nil },
          { id = 50611, name = "Bracers of Dark Reckoning", slot = "Bracers", hc = true, rate = nil, note = nil },
          { id = 50613, name = "Crushing Coldwraith Belt", slot = "Belt", hc = true, rate = nil, note = nil },
          { id = nil,   name = "Frozen Bonespike", slot = "Dagger", hc = nil, rate = nil, note = nil },
          { id = nil,   name = "Bone Warden's Splitter", slot = "One-Hand Axe", hc = nil, rate = nil, note = nil },
          { id = nil,   name = "Citadel Enforcer's Claymore", slot = "Two-Hand Sword", hc = nil, rate = nil, note = nil },
      }},
      { name = "Lady Deathwhisper", items = {
          { id = 50342, name = "Whispering Fanged Skull", slot = "Trinket", hc = nil, rate = nil, note = "physical-DPS BiS" },
          { id = 50343, name = "Whispering Fanged Skull", slot = "Trinket", hc = true, rate = nil, note = nil },
          { id = 50034, name = "Zod's Repeating Longbow", slot = "Bow", hc = nil, rate = nil, note = nil },
          { id = 50638, name = "Zod's Repeating Longbow", slot = "Bow", hc = true, rate = nil, note = nil },
          { id = 49992, name = "Nibelung", slot = "Staff", hc = nil, rate = nil, note = "summons Val'kyr on proc" },
          { id = 50648, name = "Nibelung", slot = "Staff", hc = true, rate = nil, note = nil },
          { id = 49982, name = "Heartpierce", slot = "Dagger", hc = nil, rate = nil, note = nil },
          { id = 50641, name = "Heartpierce", slot = "Dagger", hc = true, rate = nil, note = nil },
          { id = 49994, name = "The Lady's Brittle Bracers", slot = "Bracers", hc = nil, rate = nil, note = nil },
          { id = 50651, name = "The Lady's Brittle Bracers", slot = "Bracers", hc = true, rate = nil, note = nil },
          { id = 49988, name = "Leggings of Northern Lights", slot = "Mail Legs", hc = nil, rate = nil, note = nil },
          { id = 50645, name = "Leggings of Northern Lights", slot = "Mail Legs", hc = true, rate = nil, note = nil },
          { id = 50647, name = "Ahn'kahar Onyx Neckguard", slot = "Neck", hc = true, rate = nil, note = nil },
          { id = 50643, name = "Shoulders of Mercy Killing", slot = "Shoulders", hc = true, rate = nil, note = nil },
          { id = 50639, name = "Blood-Soaked Saronite Stompers", slot = "Boots", hc = true, rate = nil, note = nil },
          { id = 50640, name = "Broken Ram Skull Helm", slot = "Plate Helm", hc = true, rate = nil, note = nil },
          { id = 50642, name = "Juggernaut Band", slot = "Ring", hc = true, rate = nil, note = nil },
          { id = 50650, name = "Fallen Lord's Handguards", slot = "Gloves", hc = true, rate = nil, note = nil },
          { id = nil,   name = "Necrophotic Greaves", slot = "Boots", hc = nil, rate = nil, note = nil },
      }},
      { name = "Icecrown Gunship Battle", items = {
          { id = 50340, name = "Muradin's Spyglass", slot = "Trinket", hc = nil, rate = nil, note = "caster stacking SP" },
          { id = 50345, name = "Muradin's Spyglass", slot = "Trinket", hc = true, rate = nil, note = nil },
          { id = 50359, name = "Althor's Abacus", slot = "Trinket", hc = nil, rate = nil, note = "healer BiS" },
          { id = 50366, name = "Althor's Abacus", slot = "Trinket", hc = true, rate = nil, note = nil },
          { id = 50001, name = "Ikfirus's Sack of Wonder", slot = "Leather Chest", hc = nil, rate = nil, note = nil },
          { id = 50656, name = "Ikfirus's Sack of Wonder", slot = "Leather Chest", hc = true, rate = nil, note = nil },
          { id = 50008, name = "Ring of Rapid Ascent", slot = "Ring", hc = nil, rate = nil, note = nil },
          { id = 50664, name = "Ring of Rapid Ascent", slot = "Ring", hc = true, rate = nil, note = nil },
          { id = 50011, name = "Gunship Captain's Mittens", slot = "Gloves", hc = nil, rate = nil, note = nil },
          { id = 50663, name = "Gunship Captain's Mittens", slot = "Gloves", hc = true, rate = nil, note = nil },
          { id = 50659, name = "Polar Bear Claw Bracers", slot = "Bracers", hc = true, rate = nil, note = nil },
          { id = 50655, name = "Scourge Hunter's Vambraces", slot = "Mail Bracers", hc = true, rate = nil, note = nil },
          { id = 50653, name = "Shadowvault Slayer's Cloak", slot = "Cloak", hc = true, rate = nil, note = nil },
          { id = 50660, name = "Boneguard Commander's Pauldrons", slot = "Plate Shoulders", hc = true, rate = nil, note = nil },
          { id = 50661, name = "Corp'rethar Ceremonial Crown", slot = "Helm", hc = true, rate = nil, note = nil },
          { id = nil,   name = "Amulet of the Silent Eulogy", slot = "Neck", hc = nil, rate = nil, note = nil },
      }},
      { name = "Deathbringer Saurfang", items = {
          { id = 50362, name = "Deathbringer's Will", slot = "Trinket", hc = nil, rate = nil, note = "famous physical-DPS proc" },
          { id = 50363, name = "Deathbringer's Will", slot = "Trinket", hc = true, rate = nil, note = nil },
          { id = 50014, name = "Greatcloak of the Turned Champion", slot = "Cloak", hc = nil, rate = nil, note = nil },
          { id = 50668, name = "Greatcloak of the Turned Champion", slot = "Cloak", hc = true, rate = nil, note = nil },
          { id = 50333, name = "Toskk's Maximized Wristguards", slot = "Bracers", hc = nil, rate = nil, note = nil },
          { id = 50670, name = "Toskk's Maximized Wristguards", slot = "Bracers", hc = true, rate = nil, note = nil },
          { id = 50672, name = "Bloodvenom Blade", slot = "One-Hand Weapon", hc = true, rate = nil, note = nil },
          { id = nil,   name = "Scourgeborne Waraxe", slot = "One-Hand Axe", hc = nil, rate = nil, note = nil },
          { id = nil,   name = "Pauldrons of the Souleater", slot = "Plate Shoulders", hc = nil, rate = nil, note = nil },
          { id = 52025, name = "Conqueror's Mark of Sanctification", slot = "Tier Token", hc = nil, rate = nil, note = "Paladin/Priest/Warlock" },
          { id = 52026, name = "Protector's Mark of Sanctification", slot = "Tier Token", hc = nil, rate = nil, note = "Warrior/Hunter/Shaman" },
          { id = 52027, name = "Vanquisher's Mark of Sanctification", slot = "Tier Token", hc = nil, rate = nil, note = "DK/Druid/Mage/Rogue" },
          { id = 52028, name = "Conqueror's Mark of Sanctification", slot = "Tier Token", hc = true, rate = nil, note = "Heroic - Paladin/Priest/Warlock" },
          { id = 52029, name = "Protector's Mark of Sanctification", slot = "Tier Token", hc = true, rate = nil, note = "Heroic - Warrior/Hunter/Shaman" },
          { id = 52030, name = "Vanquisher's Mark of Sanctification", slot = "Tier Token", hc = true, rate = nil, note = "Heroic - DK/Druid/Mage/Rogue" },
      }},
      { name = "Festergut", items = {
          { id = 50341, name = "Unidentifiable Organ", slot = "Trinket", hc = nil, rate = nil, note = "tank stamina" },
          { id = 50344, name = "Unidentifiable Organ", slot = "Trinket", hc = true, rate = nil, note = nil },
          { id = 50062, name = "Plague Scientist's Boots", slot = "Leather Boots", hc = nil, rate = nil, note = nil },
          { id = 50699, name = "Plague Scientist's Boots", slot = "Leather Boots", hc = true, rate = nil, note = nil },
          { id = 50413, name = "Nerub'ar Stalker's Cord", slot = "Mail Belt", hc = nil, rate = nil, note = nil },
          { id = 50063, name = "Lingering Illness", slot = "One-Hand Weapon", hc = nil, rate = nil, note = nil },
          { id = 50065, name = "Icecrown Glacial Wall", slot = "Shield", hc = nil, rate = nil, note = nil },
          { id = 50693, name = "Might of Blight", slot = "Ring", hc = true, rate = nil, note = nil },
          { id = 50691, name = "Belt of Broken Bones", slot = "Plate Belt", hc = true, rate = nil, note = nil },
          { id = 50690, name = "Fleshrending Gauntlets", slot = "Gloves", hc = true, rate = nil, note = nil },
          { id = 50694, name = "Plaguebringer's Stained Pants", slot = "Cloth Legs", hc = true, rate = nil, note = nil },
          { id = nil,   name = "Gangrenous Leggings", slot = "Legs", hc = nil, rate = nil, note = nil },
      }},
      { name = "Rotface", items = {
          { id = 50353, name = "Dislodged Foreign Object", slot = "Trinket", hc = nil, rate = nil, note = "caster proc" },
          { id = 50348, name = "Dislodged Foreign Object", slot = "Trinket", hc = true, rate = nil, note = nil },
          { id = 50021, name = "Aldriana's Gloves of Secrecy", slot = "Leather Gloves", hc = nil, rate = nil, note = nil },
          { id = 50675, name = "Aldriana's Gloves of Secrecy", slot = "Leather Gloves", hc = true, rate = nil, note = nil },
          { id = 50023, name = "Bile-Encrusted Medallion", slot = "Neck", hc = nil, rate = nil, note = nil },
          { id = 50682, name = "Bile-Encrusted Medallion", slot = "Neck", hc = true, rate = nil, note = nil },
          { id = 50032, name = "Death Surgeon's Sleeves", slot = "Bracers", hc = nil, rate = nil, note = nil },
          { id = 50677, name = "Winding Sheet", slot = "Cloak", hc = true, rate = nil, note = nil },
          { id = 50680, name = "Rot-Resistant Breastplate", slot = "Chest", hc = true, rate = nil, note = nil },
          { id = 50684, name = "Corpse-Impaling Spike", slot = "Wand", hc = true, rate = nil, note = nil },
          { id = nil,   name = "Trauma", slot = "One-Hand Mace", hc = nil, rate = nil, note = "healer proc mace" },
      }},
      { name = "Professor Putricide", items = {
          { id = 50360, name = "Phylactery of the Nameless Lich", slot = "Trinket", hc = nil, rate = nil, note = "caster-DPS BiS" },
          { id = 50365, name = "Phylactery of the Nameless Lich", slot = "Trinket", hc = true, rate = nil, note = nil },
          { id = 50351, name = "Tiny Abomination in a Jar", slot = "Trinket", hc = nil, rate = nil, note = "melee proc" },
          { id = 50706, name = "Tiny Abomination in a Jar", slot = "Trinket", hc = true, rate = nil, note = nil },
          { id = 50067, name = "Astrylian's Sutured Cinch", slot = "Leather Belt", hc = nil, rate = nil, note = nil },
          { id = 50707, name = "Astrylian's Sutured Cinch", slot = "Leather Belt", hc = true, rate = nil, note = nil },
          { id = 50069, name = "Professor's Bloodied Smock", slot = "Cloak", hc = nil, rate = nil, note = nil },
          { id = 50705, name = "Professor's Bloodied Smock", slot = "Cloak", hc = true, rate = nil, note = nil },
          { id = 51859, name = "Shoulders of Ruinous Senility", slot = "Cloth Shoulders", hc = true, rate = nil, note = nil },
          { id = nil,   name = "Last Word", slot = "One-Hand Mace", hc = nil, rate = nil, note = nil },
          { id = nil,   name = "Abracadaver", slot = "One-Hand Mace", hc = nil, rate = nil, note = nil },
          { id = 52025, name = "Conqueror's Mark of Sanctification", slot = "Tier Token", hc = nil, rate = nil, note = "Paladin/Priest/Warlock" },
          { id = 52026, name = "Protector's Mark of Sanctification", slot = "Tier Token", hc = nil, rate = nil, note = "Warrior/Hunter/Shaman" },
          { id = 52027, name = "Vanquisher's Mark of Sanctification", slot = "Tier Token", hc = nil, rate = nil, note = "DK/Druid/Mage/Rogue" },
          { id = 52028, name = "Conqueror's Mark of Sanctification", slot = "Tier Token", hc = true, rate = nil, note = "Heroic - Paladin/Priest/Warlock" },
          { id = 52029, name = "Protector's Mark of Sanctification", slot = "Tier Token", hc = true, rate = nil, note = "Heroic - Warrior/Hunter/Shaman" },
          { id = 52030, name = "Vanquisher's Mark of Sanctification", slot = "Tier Token", hc = true, rate = nil, note = "Heroic - DK/Druid/Mage/Rogue" },
      }},
      { name = "Blood Prince Council", items = {
          { id = 50172, name = "Sanguine Silk Robes", slot = "Cloth Chest", hc = nil, rate = nil, note = nil },
          { id = 50717, name = "Sanguine Silk Robes", slot = "Cloth Chest", hc = true, rate = nil, note = nil },
          { id = 50173, name = "Shadow Silk Spindle", slot = "Off-hand", hc = nil, rate = nil, note = nil },
          { id = 50719, name = "Shadow Silk Spindle", slot = "Off-hand", hc = true, rate = nil, note = nil },
          { id = 50176, name = "San'layn Ritualist Gloves", slot = "Cloth Gloves", hc = nil, rate = nil, note = nil },
          { id = 50722, name = "San'layn Ritualist Gloves", slot = "Cloth Gloves", hc = true, rate = nil, note = nil },
          { id = 50074, name = "Royal Crimson Cloak", slot = "Cloak", hc = nil, rate = nil, note = nil },
          { id = 50718, name = "Royal Crimson Cloak", slot = "Cloak", hc = true, rate = nil, note = nil },
          { id = nil,   name = "Bloodsoul Raiment", slot = "Chest", hc = nil, rate = nil, note = nil },
          { id = nil,   name = "Keleseth's Seducer", slot = "One-Hand Sword", hc = nil, rate = nil, note = "caster sword" },
      }},
      { name = "Blood-Queen Lana'thel", items = {
          { id = 50354, name = "Bauble of True Blood", slot = "Trinket", hc = nil, rate = nil, note = "healer proc" },
          { id = 50726, name = "Bauble of True Blood", slot = "Trinket", hc = true, rate = nil, note = nil },
          { id = 50182, name = "Blood Queen's Crimson Choker", slot = "Neck", hc = nil, rate = nil, note = nil },
          { id = 50724, name = "Blood Queen's Crimson Choker", slot = "Neck", hc = true, rate = nil, note = nil },
          { id = nil,   name = "Cryptmaker", slot = "Two-Hand Mace", hc = nil, rate = nil, note = nil },
          { id = nil,   name = "Bloodfall", slot = "Dagger", hc = nil, rate = nil, note = "caster" },
          { id = nil,   name = "Cowl of Malefic Repose", slot = "Cloth Helm", hc = nil, rate = nil, note = nil },
          { id = 52025, name = "Conqueror's Mark of Sanctification", slot = "Tier Token", hc = nil, rate = nil, note = "Paladin/Priest/Warlock" },
          { id = 52026, name = "Protector's Mark of Sanctification", slot = "Tier Token", hc = nil, rate = nil, note = "Warrior/Hunter/Shaman" },
          { id = 52027, name = "Vanquisher's Mark of Sanctification", slot = "Tier Token", hc = nil, rate = nil, note = "DK/Druid/Mage/Rogue" },
          { id = 52028, name = "Conqueror's Mark of Sanctification", slot = "Tier Token", hc = true, rate = nil, note = "Heroic - Paladin/Priest/Warlock" },
          { id = 52029, name = "Protector's Mark of Sanctification", slot = "Tier Token", hc = true, rate = nil, note = "Heroic - Warrior/Hunter/Shaman" },
          { id = 52030, name = "Vanquisher's Mark of Sanctification", slot = "Tier Token", hc = true, rate = nil, note = "Heroic - DK/Druid/Mage/Rogue" },
      }},
      { name = "Valithria Dreamwalker", items = {
          { id = 50417, name = "Bracers of Eternal Dreaming", slot = "Cloth Bracers", hc = nil, rate = nil, note = nil },
          { id = 50630, name = "Bracers of Eternal Dreaming", slot = "Cloth Bracers", hc = true, rate = nil, note = nil },
          { id = 50185, name = "Devium's Eternally Cold Ring", slot = "Ring", hc = nil, rate = nil, note = nil },
          { id = 50622, name = "Devium's Eternally Cold Ring", slot = "Ring", hc = true, rate = nil, note = nil },
          { id = 50205, name = "Frostbinder's Shredded Cape", slot = "Cloak", hc = nil, rate = nil, note = nil },
          { id = 50628, name = "Frostbinder's Shredded Cape", slot = "Cloak", hc = true, rate = nil, note = nil },
          { id = 50621, name = "Lungbreaker", slot = "Dagger", hc = true, rate = nil, note = nil },
          { id = 50620, name = "Coldwraith Links", slot = "Mail Belt", hc = true, rate = nil, note = nil },
          { id = 50624, name = "Scourge Reaver's Legplates", slot = "Plate Legs", hc = true, rate = nil, note = nil },
          { id = 50625, name = "Grinning Skull Greatboots", slot = "Plate Boots", hc = true, rate = nil, note = nil },
          { id = 50618, name = "Frostbrood Sapphire Ring", slot = "Ring", hc = true, rate = nil, note = nil },
          { id = 50629, name = "Robe of the Waking Nightmare", slot = "Cloth Chest", hc = true, rate = nil, note = nil },
          { id = nil,   name = "Oxheart", slot = "Fist Weapon", hc = nil, rate = nil, note = nil },
          { id = nil,   name = "Nightmare Ender", slot = "Shield", hc = nil, rate = nil, note = nil },
          { id = nil,   name = "Leggings of the Refracted Mind", slot = "Legs", hc = nil, rate = nil, note = nil },
      }},
      { name = "Sindragosa", items = {
          { id = 50361, name = "Sindragosa's Flawless Fang", slot = "Trinket", hc = nil, rate = nil, note = "stamina + resist" },
          { id = 50364, name = "Sindragosa's Flawless Fang", slot = "Trinket", hc = true, rate = nil, note = nil },
          { id = 50421, name = "Sindragosa's Cruel Claw", slot = "Neck", hc = nil, rate = nil, note = nil },
          { id = 50633, name = "Sindragosa's Cruel Claw", slot = "Neck", hc = true, rate = nil, note = nil },
          { id = 50423, name = "Sundial of Eternal Dusk", slot = "Off-hand", hc = nil, rate = nil, note = nil },
          { id = 50635, name = "Sundial of Eternal Dusk", slot = "Off-hand", hc = true, rate = nil, note = nil },
          { id = 50424, name = "Memory of Malygos", slot = "Ring", hc = nil, rate = nil, note = nil },
          { id = 50636, name = "Memory of Malygos", slot = "Ring", hc = true, rate = nil, note = nil },
          { id = 51817, name = "Legplates of Aetheric Strife", slot = "Plate Legs", hc = true, rate = nil, note = nil },
          { id = nil,   name = "Wyrmwing Treads", slot = "Boots", hc = nil, rate = nil, note = nil },
          { id = nil,   name = "Etched Dragonbone Girdle", slot = "Belt", hc = nil, rate = nil, note = nil },
          { id = 52025, name = "Conqueror's Mark of Sanctification", slot = "Tier Token", hc = nil, rate = nil, note = "Paladin/Priest/Warlock" },
          { id = 52026, name = "Protector's Mark of Sanctification", slot = "Tier Token", hc = nil, rate = nil, note = "Warrior/Hunter/Shaman" },
          { id = 52027, name = "Vanquisher's Mark of Sanctification", slot = "Tier Token", hc = nil, rate = nil, note = "DK/Druid/Mage/Rogue" },
          { id = 52028, name = "Conqueror's Mark of Sanctification", slot = "Tier Token", hc = true, rate = nil, note = "Heroic - Paladin/Priest/Warlock" },
          { id = 52029, name = "Protector's Mark of Sanctification", slot = "Tier Token", hc = true, rate = nil, note = "Heroic - Warrior/Hunter/Shaman" },
          { id = 52030, name = "Vanquisher's Mark of Sanctification", slot = "Tier Token", hc = true, rate = nil, note = "Heroic - DK/Druid/Mage/Rogue" },
      }},
      { name = "The Lich King", items = {
          { id = 50818, name = "Invincible's Reins", slot = "Mount", hc = true, rate = 100, note = "guaranteed from 25H on 3.3.5a (became ~1% only in Cataclysm)" },
          { id = 49623, name = "Shadowmourne", slot = "Two-Hand Axe", hc = nil, rate = nil, note = "legendary - quest reward, not a loot-table drop" },
          { id = 50070, name = "Glorenzelg, High-Blade of the Silver Hand", slot = "Two-Hand Sword", hc = nil, rate = nil, note = nil },
          { id = 50730, name = "Glorenzelg, High-Blade of the Silver Hand", slot = "Two-Hand Sword", hc = true, rate = nil, note = nil },
          { id = 49997, name = "Mithrios, Bronzebeard's Legacy", slot = "One-Hand Mace", hc = nil, rate = nil, note = "tank" },
          { id = 50738, name = "Mithrios, Bronzebeard's Legacy", slot = "One-Hand Mace", hc = true, rate = nil, note = nil },
          { id = 50425, name = "Oathbinder, Charge of the Ranger-General", slot = "Polearm", hc = nil, rate = nil, note = nil },
          { id = 50735, name = "Oathbinder, Charge of the Ranger-General", slot = "Polearm", hc = true, rate = nil, note = nil },
          { id = 50734, name = "Royal Scepter of Terenas II", slot = "One-Hand Mace", hc = true, rate = nil, note = "healer" },
          { id = 50732, name = "Bloodsurge, Kel'Thuzad's Blade of Agony", slot = "One-Hand Sword", hc = true, rate = nil, note = "caster" },
          { id = 50733, name = "Fal'inrush, Defender of Quel'thalas", slot = "Bow", hc = true, rate = nil, note = "hunter BiS ranged" },
          { id = 50737, name = "Havoc's Call, Blade of Lordaeron Kings", slot = "One-Hand Sword", hc = true, rate = nil, note = nil },
          { id = 50736, name = "Heaven's Fall, Kryss of a Thousand Lies", slot = "Dagger", hc = true, rate = nil, note = "off-hand" },
          { id = nil,   name = "Warmace of Menethil", slot = "Two-Hand Mace", hc = nil, rate = nil, note = nil },
          { id = 52025, name = "Conqueror's Mark of Sanctification", slot = "Tier Token", hc = nil, rate = nil, note = "Paladin/Priest/Warlock" },
          { id = 52026, name = "Protector's Mark of Sanctification", slot = "Tier Token", hc = nil, rate = nil, note = "Warrior/Hunter/Shaman" },
          { id = 52027, name = "Vanquisher's Mark of Sanctification", slot = "Tier Token", hc = nil, rate = nil, note = "DK/Druid/Mage/Rogue" },
          { id = 52028, name = "Conqueror's Mark of Sanctification", slot = "Tier Token", hc = true, rate = nil, note = "Heroic - Paladin/Priest/Warlock" },
          { id = 52029, name = "Protector's Mark of Sanctification", slot = "Tier Token", hc = true, rate = nil, note = "Heroic - Warrior/Hunter/Shaman" },
          { id = 52030, name = "Vanquisher's Mark of Sanctification", slot = "Tier Token", hc = true, rate = nil, note = "Heroic - DK/Druid/Mage/Rogue" },
      }},
      { name = "Trash", items = {
          { id = 50415, name = "Bryntroll, the Bone Arbiter", slot = "Two-Hand Axe", hc = nil, rate = nil, note = "famous BoE trash drop" },
          { id = 50709, name = "Bryntroll, the Bone Arbiter", slot = "Two-Hand Axe", hc = true, rate = nil, note = nil },
          { id = 50444, name = "Rowan's Rifle of Silver Bullets", slot = "Gun", hc = nil, rate = nil, note = "BoE trash drop" },
          { id = nil,   name = "Wodin's Lucky Necklace", slot = "Neck", hc = nil, rate = nil, note = "BoE trash drop" },
          { id = nil,   name = "Precious's Ribbon", slot = "Shirt", hc = nil, rate = nil, note = "from Precious (Rotface's pet)" },
      }},
    },
  },

  ------------------------------------------------------------------
  -- RUBY SANCTUM (10) - 258 normal / 271 heroic. The three minibosses
  -- share one Sanctum loot table (items split below for readability).
  ------------------------------------------------------------------
  {
    key = "RS10", name = "Ruby Sanctum (10)",
    bosses = {
      { name = "Baltharus the Warborn", items = {
          { id = nil, name = "Umbrage Armbands", slot = "Bracers", hc = nil, rate = nil, note = "shared miniboss loot table" },
          { id = nil, name = "Phaseshifter's Bracers", slot = "Bracers", hc = nil, rate = nil, note = "shared miniboss loot table" },
          { id = nil, name = "Misbegotten Belt", slot = "Belt", hc = nil, rate = nil, note = "shared miniboss loot table" },
          { id = nil, name = "Gloaming Sark", slot = "Leather Chest", hc = nil, rate = nil, note = "shared miniboss loot table" },
      }},
      { name = "Saviana Ragefire", items = {
          { id = nil, name = "Foreshadow Steps", slot = "Boots", hc = nil, rate = nil, note = "shared miniboss loot table" },
          { id = nil, name = "Treads of Impending Resurrection", slot = "Boots", hc = nil, rate = nil, note = "shared miniboss loot table" },
      }},
      { name = "General Zarithrian", items = {
          { id = nil, name = "Surrogate Belt", slot = "Belt", hc = nil, rate = nil, note = "shared miniboss loot table" },
          { id = nil, name = "Returning Footfalls", slot = "Boots", hc = nil, rate = nil, note = "shared miniboss loot table" },
      }},
      { name = "Halion", items = {
          { id = nil, name = "Changeling Gloves", slot = "Gloves", hc = nil, rate = nil, note = nil },
          { id = nil, name = "Abduction's Cover", slot = "Cloak", hc = nil, rate = nil, note = nil },
          { id = nil, name = "Split Shape Belt", slot = "Belt", hc = nil, rate = nil, note = nil },
          { id = nil, name = "Apocalypse's Advance", slot = "Boots", hc = nil, rate = nil, note = nil },
      }},
    },
  },

  ------------------------------------------------------------------
  -- RUBY SANCTUM (25) - 271 normal / 284 heroic
  ------------------------------------------------------------------
  {
    key = "RS25", name = "Ruby Sanctum (25)",
    bosses = {
      { name = "Baltharus the Warborn", items = {
          { id = nil, name = "Umbrage Armbands", slot = "Bracers", hc = nil, rate = nil, note = "shared miniboss loot table" },
          { id = nil, name = "Phaseshifter's Bracers", slot = "Bracers", hc = nil, rate = nil, note = "shared miniboss loot table" },
          { id = nil, name = "Misbegotten Belt", slot = "Belt", hc = nil, rate = nil, note = "shared miniboss loot table" },
          { id = nil, name = "Gloaming Sark", slot = "Leather Chest", hc = nil, rate = nil, note = "shared miniboss loot table" },
      }},
      { name = "Saviana Ragefire", items = {
          { id = nil, name = "Foreshadow Steps", slot = "Boots", hc = nil, rate = nil, note = "shared miniboss loot table" },
          { id = nil, name = "Treads of Impending Resurrection", slot = "Boots", hc = nil, rate = nil, note = "shared miniboss loot table" },
      }},
      { name = "General Zarithrian", items = {
          { id = nil, name = "Surrogate Belt", slot = "Belt", hc = nil, rate = nil, note = "shared miniboss loot table" },
          { id = nil, name = "Returning Footfalls", slot = "Boots", hc = nil, rate = nil, note = "shared miniboss loot table" },
      }},
      { name = "Halion", items = {
          { id = 54569, name = "Sharpened Twilight Scale", slot = "Trinket", hc = nil, rate = nil, note = "physical DPS (ArP)" },
          { id = 54590, name = "Sharpened Twilight Scale", slot = "Trinket", hc = true, rate = nil, note = nil },
          { id = 54572, name = "Charred Twilight Scale", slot = "Trinket", hc = nil, rate = nil, note = "caster DPS" },
          { id = 54588, name = "Charred Twilight Scale", slot = "Trinket", hc = true, rate = nil, note = nil },
          { id = 54573, name = "Glowing Twilight Scale", slot = "Trinket", hc = nil, rate = nil, note = "healer" },
          { id = 54589, name = "Glowing Twilight Scale", slot = "Trinket", hc = true, rate = nil, note = nil },
          { id = 54571, name = "Petrified Twilight Scale", slot = "Trinket", hc = nil, rate = nil, note = "tank" },
          { id = 54591, name = "Petrified Twilight Scale", slot = "Trinket", hc = true, rate = nil, note = nil },
          { id = 54582, name = "Bracers of Fiery Night", slot = "Cloth Bracers", hc = true, rate = nil, note = nil },
          { id = 54583, name = "Cloak of Burning Dusk", slot = "Cloak", hc = true, rate = nil, note = nil },
          { id = 54585, name = "Ring of Phased Regeneration", slot = "Ring", hc = true, rate = nil, note = nil },
          { id = nil,   name = "Penumbra Pendant", slot = "Neck", hc = nil, rate = nil, note = nil },
      }},
    },
  },

  ------------------------------------------------------------------
  -- TRIAL OF THE CRUSADER (10) - 232 normal; ToGC-10 (hc) 245.
  -- Most ToC armor comes in Alliance/Horde variants with different names.
  ------------------------------------------------------------------
  {
    key = "TOC10", name = "Trial of the Crusader (10)",
    bosses = {
      { name = "Northrend Beasts", items = {
          { id = nil, name = "Banner of Victory", slot = "Trinket", hc = nil, rate = nil, note = "armor penetration" },
          { id = nil, name = "Icehowl Binding", slot = "Belt", hc = nil, rate = nil, note = nil },
      }},
      { name = "Lord Jaraxxus", items = {
          { id = 47041, name = "Solace of the Defeated", slot = "Trinket", hc = nil, rate = nil, note = "healer mp5" },
          { id = 47059, name = "Solace of the Defeated", slot = "Trinket", hc = true, rate = nil, note = "ToGC" },
          { id = nil,   name = "Talisman of Volatile Power", slot = "Trinket", hc = nil, rate = nil, note = "Alliance caster haste" },
          { id = nil,   name = "Fetish of Volatile Power", slot = "Trinket", hc = nil, rate = nil, note = "Horde caster haste" },
      }},
      { name = "Faction Champions", items = {
          { id = nil, name = "Victor's Call", slot = "Trinket", hc = nil, rate = nil, note = "Alliance AP on use" },
          { id = nil, name = "Vengeance of the Forsaken", slot = "Trinket", hc = nil, rate = nil, note = "Horde AP on use" },
      }},
      { name = "Twin Val'kyr", items = {
          { id = nil, name = "Binding Light", slot = "Trinket", hc = nil, rate = nil, note = "Alliance healer" },
          { id = nil, name = "Binding Stone", slot = "Trinket", hc = nil, rate = nil, note = "Horde healer" },
      }},
      { name = "Anub'arak", items = {
          { id = 47316, name = "Reign of the Dead", slot = "Trinket", hc = nil, rate = nil, note = "caster - counterpart of Reign of the Unliving" },
      }},
    },
  },

  ------------------------------------------------------------------
  -- TRIAL OF THE CRUSADER (25) - 245 normal; ToGC-25 (hc) 258.
  -- Every 25-normal boss also drops Trophy of the Crusade (T9 token).
  ------------------------------------------------------------------
  {
    key = "TOC25", name = "Trial of the Crusader (25)",
    bosses = {
      { name = "Northrend Beasts", items = {
          { id = nil,   name = "Legwraps of the Broken Beast", slot = "Legs", hc = nil, rate = nil, note = nil },
          { id = 47242, name = "Trophy of the Crusade", slot = "Tier Token", hc = nil, rate = nil, note = "T9 (245) upgrade token, all classes" },
      }},
      { name = "Lord Jaraxxus", items = {
          { id = 47271, name = "Solace of the Fallen", slot = "Trinket", hc = nil, rate = nil, note = "healer mp5" },
          { id = 47432, name = "Solace of the Fallen", slot = "Trinket", hc = true, rate = nil, note = "ToGC" },
          { id = 47272, name = "Charge of the Eredar", slot = "Neck", hc = nil, rate = nil, note = nil },
          { id = 47242, name = "Trophy of the Crusade", slot = "Tier Token", hc = nil, rate = nil, note = "T9 (245) upgrade token, all classes" },
      }},
      { name = "Faction Champions", items = {
          { id = 47451, name = "Juggernaut's Vitality", slot = "Trinket", hc = nil, rate = nil, note = "Horde tank stamina" },
          { id = 47290, name = "Juggernaut's Vitality", slot = "Trinket", hc = true, rate = nil, note = "ToGC" },
          { id = nil,   name = "Satrina's Impeding Scarab", slot = "Trinket", hc = nil, rate = nil, note = "Alliance tank stamina" },
          { id = 47284, name = "Icewalker Treads", slot = "Boots", hc = nil, rate = nil, note = nil },
          { id = nil,   name = "Ring of Callous Aggression", slot = "Ring", hc = true, rate = nil, note = "ToGC" },
          { id = 47242, name = "Trophy of the Crusade", slot = "Tier Token", hc = nil, rate = nil, note = "T9 (245) upgrade token, all classes" },
      }},
      { name = "Twin Val'kyr", items = {
          { id = 47115, name = "Death's Verdict", slot = "Trinket", hc = nil, rate = nil, note = "Alliance - famous DPS trinket" },
          { id = 47131, name = "Death's Verdict", slot = "Trinket", hc = true, rate = nil, note = "ToGC" },
          { id = 47303, name = "Death's Choice", slot = "Trinket", hc = nil, rate = nil, note = "Horde - famous DPS trinket" },
          { id = 47464, name = "Death's Choice", slot = "Trinket", hc = true, rate = nil, note = "ToGC" },
          { id = nil,   name = "Belt of the Pitiless Killer", slot = "Belt", hc = nil, rate = nil, note = nil },
          { id = 47242, name = "Trophy of the Crusade", slot = "Tier Token", hc = nil, rate = nil, note = "T9 (245) upgrade token, all classes" },
      }},
      { name = "Anub'arak", items = {
          { id = 47182, name = "Reign of the Unliving", slot = "Trinket", hc = nil, rate = nil, note = "caster-DPS proc" },
          { id = 47188, name = "Reign of the Unliving", slot = "Trinket", hc = true, rate = nil, note = "ToGC" },
          { id = 47206, name = "Misery's End", slot = "One-Hand Weapon", hc = true, rate = nil, note = "ToGC" },
          { id = nil,   name = "Armbands of Dark Determination", slot = "Bracers", hc = nil, rate = nil, note = nil },
          { id = 47242, name = "Trophy of the Crusade", slot = "Tier Token", hc = nil, rate = nil, note = "T9 (245) upgrade token, all classes" },
      }},
      { name = "Tribute Chest", items = {
          { id = 47545, name = "Vereesa's Dexterity", slot = "Cloak", hc = true, rate = nil, note = "ToGC tribute (Alliance, agility)" },
          { id = 47546, name = "Sylvanas' Cunning", slot = "Cloak", hc = true, rate = nil, note = "ToGC tribute (Horde, agility)" },
          { id = 47547, name = "Varian's Furor", slot = "Cloak", hc = true, rate = nil, note = "ToGC tribute (Alliance, strength)" },
          { id = 47548, name = "Garrosh's Rage", slot = "Cloak", hc = true, rate = nil, note = "ToGC tribute (Horde, strength)" },
      }},
    },
  },

  ------------------------------------------------------------------
  -- VAULT OF ARCHAVON (10) - class tier + current-season PvP pieces.
  -- Requires your faction to hold Wintergrasp.
  ------------------------------------------------------------------
  {
    key = "VOA10", name = "Vault of Archavon (10)",
    bosses = {
      { name = "Archavon the Stone Watcher", items = {
          { id = nil, name = "Heroes' Tier 7 gauntlets & leggings (random class)", slot = "Gloves / Legs", hc = nil, rate = nil, note = "actual class item drops directly" },
          { id = nil, name = "Deadly Gladiator's gauntlets & legguards (random class)", slot = "Gloves / Legs", hc = nil, rate = nil, note = "Season 5 PvP" },
      }},
      { name = "Emalon the Storm Watcher", items = {
          { id = nil, name = "Valorous Tier 8 gauntlets & leggings (random class)", slot = "Gloves / Legs", hc = nil, rate = nil, note = "actual class item drops directly" },
          { id = nil, name = "Furious Gladiator's gauntlets & legguards (random class)", slot = "Gloves / Legs", hc = nil, rate = nil, note = "Season 6 PvP" },
      }},
      { name = "Koralon the Flame Watcher", items = {
          { id = nil, name = "Tier 9 gloves & leggings, ilvl 232 (random class)", slot = "Gloves / Legs", hc = nil, rate = nil, note = "actual class item drops directly" },
          { id = nil, name = "Relentless Gladiator's gauntlets & legguards (random class)", slot = "Gloves / Legs", hc = nil, rate = nil, note = "Season 7 PvP" },
      }},
      { name = "Toravon the Ice Watcher", items = {
          { id = nil, name = "Tier 10 gauntlets & leggings, ilvl 251 (random class)", slot = "Gloves / Legs", hc = nil, rate = nil, note = "actual class item drops directly" },
          { id = nil, name = "Wrathful Gladiator's gauntlets & legguards (random class)", slot = "Gloves / Legs", hc = nil, rate = nil, note = "Season 8 PvP" },
      }},
    },
  },

  ------------------------------------------------------------------
  -- VAULT OF ARCHAVON (25)
  ------------------------------------------------------------------
  {
    key = "VOA25", name = "Vault of Archavon (25)",
    bosses = {
      { name = "Archavon the Stone Watcher", items = {
          { id = nil, name = "Valorous Tier 7.5 gauntlets & leggings (random class)", slot = "Gloves / Legs", hc = nil, rate = nil, note = "actual class item drops directly" },
          { id = nil, name = "Deadly Gladiator's gauntlets & legguards (random class)", slot = "Gloves / Legs", hc = nil, rate = nil, note = "Season 5 PvP" },
      }},
      { name = "Emalon the Storm Watcher", items = {
          { id = nil, name = "Conqueror's Tier 8.5 gauntlets & leggings (random class)", slot = "Gloves / Legs", hc = nil, rate = nil, note = "actual class item drops directly" },
          { id = nil, name = "Furious Gladiator's gauntlets & legguards (random class)", slot = "Gloves / Legs", hc = nil, rate = nil, note = "Season 6 PvP" },
      }},
      { name = "Koralon the Flame Watcher", items = {
          { id = nil, name = "Tier 9 gloves & leggings, ilvl 245 (random class)", slot = "Gloves / Legs", hc = nil, rate = nil, note = "actual class item drops directly" },
          { id = nil, name = "Relentless Gladiator's gauntlets & legguards (random class)", slot = "Gloves / Legs", hc = nil, rate = nil, note = "Season 7 PvP" },
      }},
      { name = "Toravon the Ice Watcher", items = {
          { id = nil, name = "Sanctified Tier 10 gauntlets & leggings, ilvl 264 (random class)", slot = "Gloves / Legs", hc = nil, rate = nil, note = "actual class item drops directly" },
          { id = nil, name = "Wrathful Gladiator's gauntlets & legguards (random class)", slot = "Gloves / Legs", hc = nil, rate = nil, note = "Season 8 PvP" },
      }},
    },
  },

  ------------------------------------------------------------------
  -- ONYXIA'S LAIR (10) - ilvl 232 (3.2.2 anniversary revamp)
  ------------------------------------------------------------------
  {
    key = "ONYXIA10", name = "Onyxia's Lair (10)",
    bosses = {
      { name = "Onyxia", items = {
          { id = nil,   name = "Head of Onyxia", slot = "Quest Item", hc = nil, rate = 100, note = "guaranteed - starts capital-city turn-in quest" },
          { id = 49636, name = "Reins of the Onyxian Drake", slot = "Mount", hc = nil, rate = 1, note = "very rare (~1%)" },
          { id = nil,   name = "Enlarged Onyxia Hide Backpack", slot = "Bag", hc = nil, rate = nil, note = "22-slot bag" },
          { id = nil,   name = "Vis'kag the Bloodletter", slot = "One-Hand Sword", hc = nil, rate = nil, note = "ilvl 232 remake" },
          { id = nil,   name = "Deathbringer", slot = "One-Hand Axe", hc = nil, rate = nil, note = "ilvl 232 remake" },
          { id = nil,   name = "Tier-2-styled class helms (e.g. Stormrage Cover, Judgement Crown)", slot = "Helm", hc = nil, rate = nil, note = "ilvl 232 remakes of the classic T2 helms" },
      }},
    },
  },

  ------------------------------------------------------------------
  -- ONYXIA'S LAIR (25) - ilvl 245
  ------------------------------------------------------------------
  {
    key = "ONYXIA25", name = "Onyxia's Lair (25)",
    bosses = {
      { name = "Onyxia", items = {
          { id = nil,   name = "Head of Onyxia", slot = "Quest Item", hc = nil, rate = 100, note = "guaranteed - starts capital-city turn-in quest" },
          { id = 49636, name = "Reins of the Onyxian Drake", slot = "Mount", hc = nil, rate = 1, note = "very rare (~1%)" },
          { id = nil,   name = "Enlarged Onyxia Hide Backpack", slot = "Bag", hc = nil, rate = nil, note = "22-slot bag" },
          { id = nil,   name = "Vis'kag the Bloodletter", slot = "One-Hand Sword", hc = nil, rate = nil, note = "ilvl 245 remake" },
          { id = nil,   name = "Deathbringer", slot = "One-Hand Axe", hc = nil, rate = nil, note = "ilvl 245 remake" },
          { id = nil,   name = "Purified Shard of the Scale", slot = "Trinket", hc = nil, rate = nil, note = "healer remake" },
          { id = nil,   name = "Helm of Wrath", slot = "Plate Helm", hc = nil, rate = nil, note = "Warrior T2-styled helm, ilvl 245" },
          { id = nil,   name = "Judgement Crown", slot = "Plate Helm", hc = nil, rate = nil, note = "Paladin T2-styled helm, ilvl 245" },
          { id = nil,   name = "Dragonstalker's Helm", slot = "Mail Helm", hc = nil, rate = nil, note = "Hunter T2-styled helm, ilvl 245" },
          { id = nil,   name = "Helmet of Ten Storms", slot = "Mail Helm", hc = nil, rate = nil, note = "Shaman T2-styled helm, ilvl 245" },
          { id = nil,   name = "Bloodfang Hood", slot = "Leather Helm", hc = nil, rate = nil, note = "Rogue T2-styled helm, ilvl 245" },
          { id = nil,   name = "Stormrage Cover", slot = "Leather Helm", hc = nil, rate = nil, note = "Druid T2-styled helm, ilvl 245" },
          { id = nil,   name = "Netherwind Crown", slot = "Cloth Helm", hc = nil, rate = nil, note = "Mage T2-styled helm, ilvl 245" },
          { id = nil,   name = "Nemesis Skullcap", slot = "Cloth Helm", hc = nil, rate = nil, note = "Warlock T2-styled helm, ilvl 245" },
          { id = nil,   name = "Halo of Transcendence", slot = "Cloth Helm", hc = nil, rate = nil, note = "Priest T2-styled helm, ilvl 245" },
      }},
    },
  },
}

------------------------------------------------------------------
-- Accessors
------------------------------------------------------------------

local keyIndex   -- instance key -> instance entry (lazy)
local itemIndex  -- itemID -> { item, bossName, inst }  (lazy)

local function buildKeyIndex()
    keyIndex = {}
    for _, inst in ipairs(LDB.Instances) do
        keyIndex[inst.key] = inst
    end
end

-- Direct key lookup; if not found, retry with a trailing "HC" stripped
-- ("ICC25HC" -> "ICC25"); otherwise nil.
function LDB.GetInstance(key)
    if not key then return nil end
    if not keyIndex then buildKeyIndex() end
    local inst = keyIndex[key]
    if inst then return inst end
    local base = string.gsub(key, "HC$", "")
    if base ~= key then return keyIndex[base] end
    return nil
end

local function buildItemIndex()
    itemIndex = {}
    for _, inst in ipairs(LDB.Instances) do
        for _, boss in ipairs(inst.bosses) do
            for _, item in ipairs(boss.items) do
                if item.id then
                    itemIndex[item.id] = itemIndex[item.id] or {}
                    table.insert(itemIndex[item.id], { item = item, boss = boss.name, inst = inst })
                end
            end
        end
    end
end

-- Returns item, bossName, instanceEntry for a known itemID (nil otherwise).
-- When an item drops from multiple bosses (tier tokens, some trinkets), this
-- returns only the FIRST one encountered - callers that need to be honest
-- about multi-source items should use LDB.FindItemAll instead.
function LDB.FindItem(itemID)
    local hits = LDB.FindItemAll(itemID)
    if not hits or not hits[1] then return nil end
    local hit = hits[1]
    return hit.item, hit.boss, hit.inst
end

-- Returns the full list of {item, boss, inst} hits for a known itemID (nil
-- otherwise) - some items (tier tokens, some trinkets) drop from several
-- bosses in the same instance/raid size, so a single "the" source is a lie.
function LDB.FindItemAll(itemID)
    if not itemID then return nil end
    if not itemIndex then buildItemIndex() end
    return itemIndex[itemID]
end

-- Clickable link when the id resolves AND the resolved name's first word
-- matches the stored name's first word (guards against a wrong/stale id
-- linking a different item). Otherwise plain "[Name]" text.
function LDB.Link(item)
    if not item then return "[?]" end
    if item.id and GetItemInfo then
        local rname, rlink = GetItemInfo(item.id)
        if rname and rlink then
            local a = string.match(rname, "^%S+")
            local b = string.match(item.name or "", "^%S+")
            if a and b and a == b then return rlink end
        end
    end
    return "[" .. (item.name or "?") .. "]"
end

-- Force-request an item into the local cache. On 3.3.5a GetItemInfo only
-- reads the LOCAL cache; a hidden-tooltip SetHyperlink makes the client ask
-- the server, after which GetItemInfo (and so LDB.Link) resolves to a real
-- clickable link. On-demand only (visible browser rows), never a mass sweep,
-- and once per id per session - every id here is 3.3.5a-verified so the
-- query is safe.
local queryTip
local requested = {}
function LDB.Request(itemID)
    if not itemID or requested[itemID] then return end
    requested[itemID] = true
    if GetItemInfo and GetItemInfo(itemID) then return end  -- already cached
    if not queryTip then
        queryTip = CreateFrame("GameTooltip", "AIPLootDBQueryTip", UIParent, "GameTooltipTemplate")
    end
    queryTip:SetOwner(UIParent, "ANCHOR_NONE")
    queryTip:SetHyperlink("item:" .. itemID)
    queryTip:Hide()
end

------------------------------------------------------------------
-- Warm the item cache so GetItemInfo/Link resolve on first view.
-- 3.3.5a has no C_Timer: an OnUpdate accumulator walks all known ids
-- in batches of ~25 every 0.5s, then shuts itself off.
------------------------------------------------------------------
local warm = CreateFrame("Frame")
warm.ids = nil
warm.pos = 1
warm.elapsed = 0
warm:RegisterEvent("PLAYER_LOGIN")
warm:RegisterEvent("PLAYER_ENTERING_WORLD")  -- also fires on /reload
warm:SetScript("OnEvent", function()
    if warm.ids or not GetItemInfo then return end  -- collect once
    local ids, seen = {}, {}
    for _, inst in ipairs(LDB.Instances) do
        for _, boss in ipairs(inst.bosses) do
            for _, item in ipairs(boss.items) do
                if item.id and not seen[item.id] then
                    seen[item.id] = true
                    table.insert(ids, item.id)
                end
            end
        end
    end
    warm.ids = ids
    warm.pos = 1
    warm.elapsed = 0
    warm:SetScript("OnUpdate", function(self, elapsed)
        self = self or warm
        warm.elapsed = warm.elapsed + (elapsed or arg1 or 0)
        if warm.elapsed < 0.5 then return end
        warm.elapsed = 0
        local ids2 = warm.ids
        local n = 0
        while warm.pos <= #ids2 and n < 25 do
            GetItemInfo(ids2[warm.pos])
            warm.pos = warm.pos + 1
            n = n + 1
        end
        if warm.pos > #ids2 then
            warm:SetScript("OnUpdate", nil)  -- done - stop ticking
        end
    end)
end)
