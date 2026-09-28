local GSE = GSE
local L = GSE.L

local Statics = GSE.Static
local GetSpecialization=GetSpecialization or GSE.GetCurrentSpecID
if not GetSpecialization then
	GetSpecialization=GSE.GetCurrentSpecID
end
--- Return the characters current spec id
function GSE.GetSpecialization()
return GSE.GetCurrentSpecID()
end
function GSE.GetCurrentSpecID()
--local  name, iconTexture, pointsSpent, background, previewPointsSpent = GetTalentTabInfo(tabIndex[, inspect[, isPet]][, talentGroup])
-- if event == "INSPECT_READY" then
  -- local spec = ""
  -- _, name = GetTalentTabInfo(GetPrimaryTalentTree(GetActiveTalentGroup()))
  -- spec = name
  -- return spec
-- else
  -- NotifyInspect(unit)
-- end
 -- local currentSpec = GetSpecialization() --local index = GetActiveTalentGroup(isInspect, isPet);
  --return currentSpec and select(1, GetSpecializationInfo(currentSpec)) or 0 ---specid Statics.wotlkSpecIDList 

--local name, icon, pointsSpent, background, previewPointsSpent = GetTalentTabInfo(tab,isInspect,isPet,activeSpec);


  local activeSpec = GetActiveTalentGroup()
local maxpointspents=0
local  primarytree=0
----print(GetTalentTabInfo(activeTalentGroup))
for tab = 1, GetNumTalentTabs() do
   local tabname, tabicon, nopointsSpent, tabbackground, tabpreviewPointsSpent = GetTalentTabInfo(tab,false,false,activeSpec)
   if (nopointsSpent>maxpointspents) then
      maxpointspents=nopointsSpent
      primarytree=tab
   end
   if (primarytree==0) then
      primarytree=1
   end
end

	local name1,icon=GetTalentTabInfo(primarytree,false,false,activeSpec);
	if name1 then
		name1=string.upper(name1)
	else
		name1 = ""
	end
  -- The 3.3.5a Druid feral tab is "Feral Combat"; the spec list stores "Feral - Druid"
  if name1 == "FERAL COMBAT" then
    name1 = "FERAL"
  end
  local specid;
  if name1 == "" then
    -- talents not loaded yet: "" would match every spec entry and pick an arbitrary one
    return nil,name1,icon
  end

	  for k,v in pairs(Statics.wotlkSpecIDList) do

		local searchStr = v and string.upper(v) or ""
		local st,ed=string.find(searchStr,name1,1,true)
		local isClass,isClass1=UnitClass("player")
		isClass = isClass and string.upper(isClass) or ""
		isClass1 = isClass1 and string.upper(isClass1) or ""
		local st1,ed1=string.find(searchStr,isClass)
		local st2,ed2=string.find(searchStr,isClass1)
			if(st~=nil) then 
				if(st1~=nil or st2~=nil) then 
					specid=k 
				end	
			end
	  end
  return specid,name1,icon;
end

--- Return the characters class id
function GSE.GetCurrentClassID()
  --local _, _, currentclassId = UnitClass("player")--classDisplayName, class, classID = UnitClass("unit");
  local class1, class = UnitClass("player")
  local currentclassId1=""
  for k,v in pairs(Statics.wotlkClassIDList) do
	if (string.upper(v)==string.upper(class) or string.upper(v)==string.upper(class1)) then 
		currentclassId1=k 
	end
  end
 -- DEFAULT_CHAT_FRAME:AddMessage("currentclassId1 "..currentclassId1)
  return currentclassId1
end

--- Return the characters class id
function GSE.GetCurrentClassNormalisedName()
  --local _, classnormalisedname, _ = UnitClass("player")--classDisplayName, class, classID = UnitClass("unit");
  local _, classnormalisedname = UnitClass("player")--classDisplayName, class, classID = UnitClass("unit");
  return string.upper(classnormalisedname)
end

function GSE.GetClassIDforSpec(specid)
  --local id, name, description, icon, role, class = GetSpecializationInfoByID(specid)
--classid
	local value,classid,class;
	for k,v in pairs(Statics.wotlkClassIDList) do
		if (k==specid) then 
			classid=k  
		end
	end
  
  for k,v in pairs(Statics.wotlkSpecIDList) do
	if (k==specid) then 
		--value=Statics.wotlkSpecIDList[specID]
		-- plain find: as a pattern " - " matches the first space ("Beast Mastery - Hunter" -> wrong split)
		local idx=string.find(v," - ",1,true)
		if(idx~=nil) then
			class=string.sub(v,idx+3)
		end
		--print(v,last,last[#last])
	    --local class=string.upper(last[#last])
		for k1,v1 in pairs(Statics.wotlkClassIDList) do
			-- class-level ids (0-11) have no " - Class" suffix, so class is nil (classid already set above)
			if class and (string.upper(v1)==string.upper(class)) then
			classid=k1
			end
		end
	end
  end
	--local last = string.split( value, "% " )
	--local class=string.upper(last[#last])

  
  -- local classid = 0
  -- if specid <= 12 then
    -- classid = specid
  -- else
    -- for i=1, 12, 1 do
    -- local cdn, st, cid = GetClassInfo(i)--classDisplayName, classTag, classID = GetClassInfo(index)

	 -- st=string.upper(st)
      -- if class == st then
        -- classid = i
      -- end
    -- end
  -- end
   return classid
end

function GSE.GetClassIcon(classid)
  local classicon = {}
  -- classicon[1] = "Interface\\Icons\\inv_sword_27" -- Warrior
  -- classicon[2] = "Interface\\Icons\\ability_thunderbolt" -- Paladin
  -- classicon[3] = "Interface\\Icons\\inv_weapon_bow_07" -- Hunter
  -- classicon[4] = "Interface\\Icons\\inv_throwingknife_04" -- Rogue
  -- classicon[5] = "Interface\\Icons\\inv_staff_30" -- Priest
  -- classicon[6] = "Interface\\Icons\\inv_sword_27" -- Death Knight
  -- classicon[7] = "Interface\\Icons\\inv_jewelry_talisman_04" -- SWhaman
  -- classicon[8] = "Interface\\Icons\\inv_staff_13" -- Mage
  -- classicon[9] = "Interface\\Icons\\spell_nature_drowsy" -- Warlock
 -- classicon[10] = "Interface\\Icons\\Spell_Holy_FistOfJustice" -- Monk
  -- classicon[11] = "Interface\\Icons\\inv_misc_monsterclaw_04" -- Druid
 --classicon[12] = "Interface\\Icons\\INV_Weapon_Glave_01" -- DEMONHUNTER

	
	
   classicon[1] = "Interface\\Icons\\inv_sword_27" -- Warrior
  classicon[2] = "Interface\\Icons\\ability_thunderbolt" -- Paladin
  classicon[3] = "Interface\\Icons\\inv_weapon_bow_07" -- Hunter
  classicon[4] = "Interface\\Icons\\inv_throwingknife_04" -- Rogue
  classicon[5] = "Interface\\Icons\\INV_Staff_30" -- Priest
  classicon[6] = "Interface\\Icons\\Spell_Deathknight_ClassIcon" -- Death Knight
  classicon[7] = "Interface\\Icons\\Spell_Nature_BloodLust" -- SWhaman
  classicon[8] = "Interface\\Icons\\INV_Staff_13" -- Mage
  classicon[9] = "Interface\\Icons\\Spell_Nature_FaerieFire" -- Warlock
	classicon[10] = "Interface\\Icons\\INV_Misc_MonsterClaw_04" -- Monk
  classicon[11] = "Interface\\Icons\\INV_Misc_MonsterClaw_04" -- Druid
	classicon[12] = "Interface\\Icons\\inv_weapon_bow_07" -- DEMONHUNTER
  return classicon[classid]

end

--- Check if the specID provided matches the plauers current class.
function GSE.isSpecIDForCurrentClass(specID)
for k,v in pairs(Statics.wotlkSpecIDList) do
	if (k==specID) then 
		local value=Statics.wotlkSpecIDList[specID]
		if value then
			local parts = GSE.split(value, " - ")
	    local class = string.upper(parts[#parts])
		local currentenglishclass, currentclassDisplayName = UnitClass("player")
		
		currentenglishclass=string.upper(currentenglishclass)
		local currentclassId=string.upper(currentclassDisplayName)
		
		for k1,v1 in pairs(Statics.wotlkClassIDList) do
			if (string.upper(v1)==string.upper(class)) then currentclassId=k1 end
		end
		
		return (class==currentenglishclass or specID==currentclassId)
		end
	end
 end
  return false
end


function GSE.GetSpecNames()
  local keyset={}
  for k,v in pairs(Statics.wotlkSpecIDList) do
    keyset[v] = v
  end
  return keyset
end

--- Returns the Character Name in the form Player@server
function GSE.GetCharacterName()
  return  GetUnitName("player", true) .. '@' .. GetRealmName()
end

--- Returns the current Talent Selections as a string
--- The player's talent build as the usual WotLK point spread, e.g. "51/20/0". This used to be a
--- placeholder ("?,?,?,?,?,?,?,") that got saved into every new macro's Talents field.
function GSE.GetCurrentTalents()
  local spread = {}
  local activeGroup = GetActiveTalentGroup and GetActiveTalentGroup() or 1
  for tab = 1, (GetNumTalentTabs and GetNumTalentTabs() or 0) do
    local _, _, points = GetTalentTabInfo(tab, false, false, activeGroup)
    spread[#spread + 1] = tostring(points or 0)
  end
  if #spread == 0 then
    return "?"
  end
  return table.concat(spread, "/")
end


--- Experimental attempt to load a WeakAuras string.
function GSE.LoadWeakauras(str)
  local WeakAuras = WeakAuras

  if WeakAuras then
    WeakAuras.ImportString(str)
  end
end
