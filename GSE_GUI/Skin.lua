local GSE = GSE

-- Optional ElvUI integration: when ElvUI is loaded, GSE's windows use ElvUI's
-- own Skins module so they automatically match whatever skin/colour the
-- player has configured. Every ElvUI call below is pcall-guarded: ElvUI's
-- skin functions are written for specific native Blizzard frame templates,
-- and AceGUI's widgets don't always match those templates exactly, so a
-- mismatch falls back to the flat skin instead of throwing an error.
local ElvE, ElvSkins
if ElvUI then
  local ok, e = pcall(function() return unpack(ElvUI) end)
  if ok and e then
    ElvE = e
    local okS, s = pcall(function() return ElvE:GetModule("Skins") end)
    if okS and s then ElvSkins = s end
  end
end

GSE.Skin = GSE.Skin or {}
local Skin = GSE.Skin

local FLAT_TEXTURE = "Interface\\Buttons\\WHITE8X8"

--- Accent colour for the flat fallback skin: uses ElvUI's own accent colour
--- when ElvUI is present (so the fallback still matches the player's ElvUI
--- setup even on widgets we don't hand to ElvUI directly), otherwise a fixed
--- blue that matches ElvUI's stock theme.
local function accentColor()
  if ElvE and ElvE.db and ElvE.db.general and ElvE.db.general.valuecolor then
    local c = ElvE.db.general.valuecolor
    return c.r, c.g, c.b
  end
  return 0.35, 0.65, 1
end

local flatBackdropTable = {
  bgFile = FLAT_TEXTURE,
  edgeFile = FLAT_TEXTURE,
  edgeSize = 1,
  insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

local function applyFlatBackdrop(frame)
  if not frame or not frame.SetBackdrop then return end
  frame:SetBackdrop(flatBackdropTable)
  frame:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
  frame:SetBackdropBorderColor(0, 0, 0, 1)
end

--- Same flat backdrop, but for actual INPUT controls (EditBox, Dropdown) -
--- a pure black 1px border on a near-black window fill is essentially
--- invisible (confirmed live: the Sequence Name field was reported as "not
--- visible"), so input fields get a visibly lighter fill + border than the
--- surrounding panel, reading as a distinct clickable/editable control
--- instead of blending into the window background.
local function applyInputBackdrop(frame)
  if not frame or not frame.SetBackdrop then return end
  frame:SetBackdrop(flatBackdropTable)
  frame:SetBackdropColor(0.1, 0.1, 0.1, 1)
  frame:SetBackdropBorderColor(0.32, 0.32, 0.32, 1)
end

function Skin.FlatFrame(frame)
  applyFlatBackdrop(frame)
end

function Skin.FlatButton(button)
  if not button then return end
  if button.SetNormalTexture then button:SetNormalTexture("") end
  if button.SetPushedTexture then button:SetPushedTexture("") end
  if button.SetDisabledTexture then button:SetDisabledTexture("") end
  if button.SetHighlightTexture then
    button:SetHighlightTexture(FLAT_TEXTURE)
    local hl = button.GetHighlightTexture and button:GetHighlightTexture()
    if hl then
      local r, g, b = accentColor()
      hl:SetVertexColor(r, g, b, 0.25)
    end
  end
  applyFlatBackdrop(button)
end

--- Hides the named Left/Middle/Right (or similarly suffixed) border pieces a
--- Blizzard template frame draws as separate child textures rather than as a
--- generic backdrop - InputBoxTemplate and UIDropDownMenuTemplate both work
--- this way, so SetBackdrop alone never changes their visible border.
local function hideNamedPieces(frame, parts)
  if not frame or not frame.GetName then return end
  local name = frame:GetName()
  if not name then return end
  for _, part in ipairs(parts) do
    local tex = _G[name .. part]
    if tex and tex.SetAlpha then tex:SetAlpha(0) end
  end
end

function Skin.FlatEditBox(editbox)
  hideNamedPieces(editbox, { "Left", "Middle", "Right" })
  applyInputBackdrop(editbox)
end

--- Public wrapper so other files (MultiLineEditBox's scroll background, e.g.
--- KeyPress/Sequence/KeyRelease/PostMacro) can opt into the same visibly-
--- bordered input look as EditBox/Dropdown, instead of the near-invisible
--- black-on-black Skin.FlatFrame border meant for outer window chrome.
function Skin.FlatInput(frame)
  applyInputBackdrop(frame)
end

--- AceGUI draws its own checkbox with plain textures rather than a native
--- CheckButton template, so there is no safe ElvUI hook for it - this is
--- always the flat/accent recolour, with or without ElvUI installed.
function Skin.FlatCheckBox(checkbg, check)
  if not checkbg or not checkbg.SetTexture then return end
  checkbg:SetTexture(FLAT_TEXTURE)
  checkbg:SetVertexColor(0.12, 0.12, 0.12, 1)
  if check and check.SetVertexColor then
    local r, g, b = accentColor()
    check:SetVertexColor(r, g, b, 1)
  end
end

--- Fallback dropdown skin: hides the carved Blizzard Left/Middle/Right
--- dropdown art and gives the dropdown frame itself a flat backdrop.
function Skin.FlatDropdown(dropdown)
  hideNamedPieces(dropdown, { "Left", "Middle", "Right" })
  applyInputBackdrop(dropdown)
end

local TITLE_HEADER_TEXTURE = "Interface\\DialogFrame\\UI-DialogBox-Header"

--- AceGUI's top-level "Frame" widget builds its close button, status-bar
--- pane and ornate title header art as plain native children/regions of
--- widget.frame rather than exposing them on the widget table, so neither
--- ElvUI's HandleFrame nor the AddChild-based tree walk ever reaches them.
--- This reaches them directly via the native frame API instead.
local function skinFrameChrome(frame)
  if not frame then return end
  if frame.GetRegions then
    local ok, regions = pcall(function() return { frame:GetRegions() } end)
    if ok then
      for _, region in ipairs(regions) do
        if region.GetObjectType and region:GetObjectType() == "Texture" then
          local tex = region.GetTexture and region:GetTexture()
          if tex == TITLE_HEADER_TEXTURE then
            region:SetAlpha(0)
          end
        end
      end
    end
  end
  if frame.GetChildren then
    local ok, children = pcall(function() return { frame:GetChildren() } end)
    if ok then
      for _, child in ipairs(children) do
        if child.GetObjectType and child:GetObjectType() == "Button" then
          Skin.Button(child)
        end
      end
    end
  end
end

--- Real ElvUI skin when available and compatible, flat skin otherwise.
function Skin.Frame(frame)
  if not frame then return end
  if ElvSkins then
    local ok = pcall(ElvSkins.HandleFrame, ElvSkins, frame, true)
    if ok then
      skinFrameChrome(frame)
      return
    end
  end
  Skin.FlatFrame(frame)
  skinFrameChrome(frame)
end

function Skin.Button(button)
  if not button then return end
  if ElvSkins then
    local ok = pcall(ElvSkins.HandleButton, ElvSkins, button)
    if ok then return end
  end
  Skin.FlatButton(button)
end

function Skin.EditBox(editbox)
  if not editbox then return end
  if ElvSkins then
    local ok = pcall(ElvSkins.HandleEditBox, ElvSkins, editbox)
    if ok then return end
  end
  Skin.FlatEditBox(editbox)
end

function Skin.Dropdown(dropdown)
  if not dropdown then return end
  if ElvSkins then
    local ok = pcall(ElvSkins.HandleDropDownBox, ElvSkins, dropdown, dropdown:GetWidth() or 150)
    if ok then return end
  end
  Skin.FlatDropdown(dropdown)
end

--- Fallback tab skin: Blizzard's tab template shows either its "active" or
--- "Disabled" (inactive) texture set to indicate which tab is selected -
--- that's the only cue the player has for which tab they're on, so this
--- dims both sets toward the flat theme rather than hiding them outright,
--- which would erase the selected/unselected distinction entirely.
function Skin.FlatTab(tab)
  if not tab or not tab.GetName then return end
  local name = tab:GetName()
  if not name then return end
  for _, part in ipairs({ "Left", "Middle", "Right", "LeftDisabled", "MiddleDisabled", "RightDisabled" }) do
    local tex = _G[name .. part]
    if tex and tex.SetVertexColor then tex:SetVertexColor(0.35, 0.35, 0.35) end
  end
end

function Skin.Tab(tab)
  if not tab then return end
  if ElvSkins then
    local ok = pcall(ElvSkins.HandleTab, ElvSkins, tab)
    if ok then return end
  end
  Skin.FlatTab(tab)
end

--- Skins a single AceGUI widget instance based on its known internal shape.
--- Errors from any one widget are swallowed (via pcall further up the chain)
--- so a mismatched widget can't break the rest of the skin pass.
local function skinWidget(widget)
  if type(widget) ~= "table" then return end
  local wtype = widget.type

  if wtype == "Button" then
    Skin.Button(widget.frame)
  elseif wtype == "CheckBox" then
    Skin.FlatCheckBox(widget.checkbg, widget.check)
  elseif wtype == "Dropdown" then
    if widget.dropdown then Skin.Dropdown(widget.dropdown) end
  elseif wtype == "MultiLineEditBox" then
    Skin.FlatInput(widget.scrollBG)
    if widget.button then Skin.Button(widget.button) end
  elseif wtype == "Slider" then
    Skin.FlatFrame(widget.frame)
  elseif wtype == "InlineGroup" then
    Skin.FlatFrame(widget.frame)
  elseif wtype == "TabGroup" then
    if type(widget.tabs) == "table" then
      for _, tab in ipairs(widget.tabs) do
        Skin.Tab(tab)
      end
    end
  elseif wtype == "Frame" then
    Skin.Frame(widget.frame)
  elseif widget.editbox then
    -- Covers EditBox and any EditBox-derived custom widget type (e.g. the
    -- autocomplete "EditBoxExampleAll" widget from
    -- AceGUI-3.0-Completing-EditBox) not recognised by exact type above.
    Skin.EditBox(widget.editbox)
  end
end

--- Recursively walks an AceGUI container tree - as built via :AddChild /
--- :AddChildren, which populate widget.children - and skins every widget it
--- reaches. Call this once after a container has finished laying out its
--- content (e.g. at the end of a "perform layout" function, or right before
--- :Show()) rather than at each individual AceGUI:Create call site - that
--- keeps the skin pass to a single integration point per window instead of
--- one at every widget creation site, and avoids hooking AceGUI:Create
--- itself (which would also skin every other addon sharing this client's
--- AceGUI-3.0 instance via LibStub).
function Skin.WalkAceContainer(container)
  if type(container) ~= "table" then return end
  pcall(skinWidget, container)
  if type(container.children) == "table" then
    for _, child in ipairs(container.children) do
      Skin.WalkAceContainer(child)
    end
  end
end
