-- AutoInvite Plus - Post-Pull Report ("how'd that go", foolproof coaching)
-- Silent during combat; on a real boss pull ending it prints a short summary:
-- duration, your DPS/HPS (READ from Details!/Skada/Recount - interop, not a rebuilt
-- meter), avoidable damage you took (from the mechanic spell set), and the
-- interrupts/dispels you landed. Opt-in (AIP.db.postPull). This is the
-- highest-value-to-annoyance coaching aid: no in-combat nagging.

local AIP = AutoInvitePlus
if not AIP then return end

AIP.PostPull = AIP.PostPull or {}
local PP = AIP.PostPull

PP.tracking = false
PP.startTime = 0
PP.playerGUID = nil
PP.avoidableDmg = 0
PP.interrupts = 0
PP.dispels = 0

-- The mechanic spell set doubles as "damage you should have avoided": taking
-- damage from one of these means you were standing in it.
local function avoidableSet()
    return (AIP.RaidTools and AIP.RaidTools.MechanicSpells) or {}
end

-- ---- meter interop: return (dps, hps) for the player from Skada or Recount ----
local function readMeters()
    local me = UnitName("player")
    -- Details! Damage Meter (global `Details` / `_detalhes`). 3.3.5a API verified
    -- against the Bunny67 backport source: GetCombat(0) = current segment (NOT
    -- GetCurrentCombat, which is doc-only here); combat:GetActor(attr, name).total /
    -- combat:GetCombatTime(), with attr 1 = damage, 2 = heal.
    local D = _G.Details or _G._detalhes
    if D and D.GetCombat then
        local ok, dps, hps = pcall(function()
            local combat = D:GetCombat(0) or D.tabela_vigente
            if not (combat and combat.GetCombatTime and combat.GetActor) then return nil end
            local t = combat:GetCombatTime(); if not t or t <= 0 then return nil end
            local da = combat:GetActor(_G.DETAILS_ATTRIBUTE_DAMAGE or 1, me)
            local ha = combat:GetActor(_G.DETAILS_ATTRIBUTE_HEAL or 2, me)
            local d = (da and da.total) and (da.total / t) or nil
            local h = (ha and ha.total) and (ha.total / t) or nil
            if d or h then return d, h end
            return nil
        end)
        if ok and dps then return dps, hps end
    end
    -- Skada (global `Skada`): current set, iterate players, dps = damage/activetime.
    if Skada and Skada.GetSet then
        local ok, dps, hps = pcall(function()
            local set = Skada:GetSet("current") or Skada:GetSet("last")
            if not set then return nil end
            local iter = set.players or set.actors
            if not iter then return nil end
            for _, p in pairs(iter) do
                if p.name == me then
                    local t = (Skada.PlayerActiveTime and Skada:PlayerActiveTime(set, p)) or set.time or 1
                    if t < 1 then t = 1 end
                    return (p.damage or p.damaged or 0) / t, (p.healing or 0) / t
                end
            end
        end)
        if ok and dps then return dps, hps end
    end
    -- Recount (global `Recount`): db2.combatants[name].Fights[FightNum]
    if Recount and Recount.db2 and Recount.db2.combatants then
        local ok, dps, hps = pcall(function()
            local c = Recount.db2.combatants[me]
            if not c or not c.Fights then return nil end
            local fnum = Recount.db2.FightNum or #c.Fights
            local ft = c.Fights[fnum] or c.Fights[#c.Fights]
            if not ft then return nil end
            local t = (ft.ActiveTime and ft.ActiveTime > 0) and ft.ActiveTime or 1
            return (ft.Damage or 0) / t, (ft.Healing or 0) / t
        end)
        if ok and dps then return dps, hps end
    end
    return nil, nil
end

local function fmtNum(n)
    if not n then return "?" end
    if n >= 1000 then return string.format("%.1fk", n / 1000) end
    return string.format("%.0f", n)
end

-- ============================================================================
-- Combat lifecycle + CLEU accumulation
-- ============================================================================
local function startPull()
    PP.tracking = true
    PP.startTime = GetTime()
    PP.playerGUID = UnitGUID("player")
    PP.avoidableDmg = 0
    PP.interrupts = 0
    PP.dispels = 0
end

local function endPull()
    if not PP.tracking then return end
    PP.tracking = false
    local dur = GetTime() - (PP.startTime or GetTime())
    -- Only report real boss-length fights inside an instance (skip trash).
    local inInst = (AIP.RaidTools and AIP.RaidTools.InPveInstance and AIP.RaidTools.InPveInstance())
    if not inInst or dur < 25 then return end

    local dps, hps = readMeters()
    AIP.Print(string.format("|cFF66CCFFPost-pull|r (%.0fs):", dur))
    if dps then
        AIP.Print(string.format("  Your DPS: |cFFFFFFFF%s|r%s", fmtNum(dps),
            (hps and hps > 1) and ("   HPS: |cFFFFFFFF" .. fmtNum(hps) .. "|r") or ""))
    else
        AIP.Print("  (install Details!, Skada or Recount for DPS/HPS numbers)")
    end
    if PP.avoidableDmg > 0 then
        AIP.Print(string.format("  |cFFFF6060Avoidable damage taken:|r %s - watch the ground!", fmtNum(PP.avoidableDmg)))
    else
        AIP.Print("  |cFF00FF00No avoidable damage taken.|r")
    end
    if PP.interrupts > 0 then AIP.Print("  Interrupts landed: " .. PP.interrupts) end
    if PP.dispels > 0 then AIP.Print("  Dispels: " .. PP.dispels) end
end

local function onCLEU(...)
    if not PP.tracking or not PP.playerGUID then return end
    local sub = select(2, ...)
    local srcGUID = select(3, ...)
    local dstGUID = select(6, ...)

    if sub == "SPELL_DAMAGE" or sub == "SPELL_PERIODIC_DAMAGE" then
        if dstGUID == PP.playerGUID then
            local spellName = select(10, ...)
            if spellName and avoidableSet()[spellName] then
                local amount = select(12, ...) or 0
                PP.avoidableDmg = PP.avoidableDmg + amount
            end
        end
    elseif sub == "SPELL_INTERRUPT" then
        if srcGUID == PP.playerGUID then PP.interrupts = PP.interrupts + 1 end
    elseif sub == "SPELL_DISPEL" then
        if srcGUID == PP.playerGUID then PP.dispels = PP.dispels + 1 end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_REGEN_DISABLED")   -- entered combat
f:RegisterEvent("PLAYER_REGEN_ENABLED")    -- left combat
f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
f:SetScript("OnEvent", function(self, event, ...)
    if not (AIP.db and AIP.db.postPull) then
        if PP.tracking then PP.tracking = false end
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        startPull()
    elseif event == "PLAYER_REGEN_ENABLED" then
        endPull()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        onCLEU(...)
    end
end)
