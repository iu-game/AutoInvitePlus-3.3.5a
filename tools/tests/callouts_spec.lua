-- Headless tests for RaidTools' mechanic call-out classifier / banner spec builder.
-- Run from the repo root:  luajit tools/tests/callouts_spec.lua

AutoInvitePlus = { db = {}, Utils = {}, Print = function() end }
local AIP = AutoInvitePlus
CLASS_ICON_TCOORDS = { MAGE = { 0.25, 0.5, 0, 0.25 } }
GetSpellInfo = function(name) if name == "Defile" then return "Defile", nil, "Interface\\Icons\\Spell_Shadow_Defile" end end
local chunk = assert(loadfile("AutoInvitePlus/modules/RaidTools.lua"))
local okLoad, err = pcall(chunk, "AutoInvitePlus", AIP)
if not okLoad then print("LOAD FAIL: " .. tostring(err)); os.exit(1) end
local RT = AIP.RaidTools

local pass, fail = 0, 0
local function eq(a, b, label)
    if a == b then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. label .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end
end

local function cat(text) return RT.ClassifyCallout(text).id end
eq(cat(RT.MechanicSpells["Empowered Shock Vortex"]), "spread", "shock vortex -> spread")
eq(cat(RT.MechanicSpells["Defile"]), "move", "defile -> move")
eq(cat(RT.MechanicSpells["Blistering Cold"]), "move", "blistering cold -> move")
eq(cat(RT.MechanicSpells["Dominate Mind"]), "cc", "dominate mind -> crowd control")
eq(cat(RT.MechanicSpells["Bellowing Roar"]), "fear", "bellowing roar -> fear")
eq(cat(RT.MechanicSpells["Nether Power"]), "dispel", "nether power -> dispel")
eq(cat(RT.MechanicSpells["Soul Reaper"]), "tank", "soul reaper -> tank")
eq(cat(RT.MechanicSpells["Frost Blast"]), "heal", "frost blast -> heal")
eq(cat(RT.MechanicSpells["Overcharge"]), "kill", "overcharge -> kill")
eq(cat(RT.MechanicSpells["Polarity Shift"]), "stack", "polarity shift -> group up")
eq(cat("Lord Marrowgar at 35%!"), "phase", "boss health milestone")
eq(cat("something unexpected"), "alert", "unknown -> default alert")

local s = RT.BuildCallout(RT.MechanicSpells["Call Blood Beast"], { spell = "Defile", zone = "Icecrown Citadel", key = "k" })
eq(s.text, "Blood Beasts up", "headline is the ability")
eq(s.body ~= nil and s.body:find("95%% AoE%-resistant") ~= nil, true, "parenthetical moves to its own body line")
eq(s.textIcon, "Interface\\Icons\\Spell_Shadow_Defile", "real spell icon beside the headline")
eq(s.title:find("Icecrown Citadel", 1, true) ~= nil, true, "zone shown in the title")
eq(s.duration > 4.5, true, "longer text holds longer")

local d = RT.BuildCallout("Polymorph the mind-controlled player!", { duty = true, class = "MAGE", mechanic = "Dominate Mind" })
eq(d.text, "Dominate Mind", "duty headline is the mechanic")
eq(d.body, "Polymorph the mind-controlled player!", "duty body is the action")
eq(#d.badges, 1, "duty carries your class badge")
eq(d.badges[1].tex, "Interface\\WorldStateFrame\\Icons-Classes", "class badge uses the class sheet")

local t = RT.BuildCallout("Soul Reaper on the tank - healers big cooldown!")
eq(#t.badges, 2, "tank + healer medallions")

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
