local GSE = GSE
local L = GSE.L

GSE.GUIEditFrame = {}

StaticPopupDialogs["GSE_ConfirmReloadUIDialog"] = {
  text = L["You need to reload the User Interface to complete this task.  Would you like to do this now?"],
  button1 = L["Yes"],
  button2 = L["No"],
  OnAccept = function()
      ReloadUI();
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,  -- avoid some UI taint, see http://www.wowace.com/announcements/how-to-avoid-some-ui-taint/
}

StaticPopupDialogs["GS-DebugOutput"] = {
  text = L["Dump of GSE debug messages"],
  button1 = L["Update"],
  button2 = L["Close"],
  OnAccept = function(self, data)
      self.editBox:SetText(GSE.DebugOutput)
      -- returning true keeps the dialog open; "Update" is a refresh, not a confirmation
      return true
  end,
  OnShow = function (self, data)
    self.editBox:SetText(GSE.DebugOutput)
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,  -- avoid some UI taint, see http://www.wowace.com/announcements/how-to-avoid-some-ui-taint/
  hasEditBox = true,
}

-- Both link dialogs below reuse Blizzard's shared StaticPopup edit boxes. They used to shrink the edit box
-- and then reset it to a made-up 50px width, leaving other dialogs' edit boxes (add friend, guild MOTD...)
-- too narrow until a reload: remember the real width and put exactly that back.
local function rememberEditBoxWidth(editBox)
  if not editBox.gseOriginalWidth then
    editBox.gseOriginalWidth = editBox:GetWidth()
  end
end

local function restoreEditBoxWidth(editBox)
  if editBox.gseOriginalWidth then
    editBox:SetWidth(editBox.gseOriginalWidth)
  end
end

local UPDATE_URL = "https://github.com/iu-game/AutoInvitePlus-3.3.5a/releases"

StaticPopupDialogs['GSE_UPDATE_AVAILABLE'] = {
  text = L["A newer version of GSE is available: https://github.com/iu-game/AutoInvitePlus-3.3.5a/releases"],
  hasEditBox = 1,
  OnShow = function(self)
    rememberEditBoxWidth(self.editBox)
    self.editBox:SetAutoFocus(false)
    self.editBox:SetWidth(220)
    self.editBox:SetText(UPDATE_URL)
    self.editBox:HighlightText()
    ChatEdit_FocusActiveWindow();
  end,
  OnHide = function(self)
    restoreEditBoxWidth(self.editBox)
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = 1,
  button1 = OKAY,
  EditBoxOnEnterPressed = function(self)
    ChatEdit_FocusActiveWindow();
    self:GetParent():Hide();
  end,
  EditBoxOnEscapePressed = function(self)
    ChatEdit_FocusActiveWindow();
    self:GetParent():Hide();
  end,
  EditBoxOnTextChanged = function(self)
    if(self:GetText() ~= UPDATE_URL) then
      self:SetText(UPDATE_URL)
    end
    self:HighlightText()
    self:ClearFocus()
    ChatEdit_FocusActiveWindow();
  end,
}

StaticPopupDialogs['GSE_SEQUENCEHELP'] = {
  text = L["Copy this link and open it in a Browser."],
  hasEditBox = 1,
  url = "http://www.wowlazymacros.com",
  OnShow = function(self)
    rememberEditBoxWidth(self.editBox)
    self.editBox:SetAutoFocus(false)
    self.editBox:SetWidth(220)
    self.editBox:SetText(StaticPopupDialogs['GSE_SEQUENCEHELP'].url)
    self.editBox:HighlightText()
    ChatEdit_FocusActiveWindow();
  end,
  OnHide = function(self)
    restoreEditBoxWidth(self.editBox)
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = 1,
  button1 = OKAY,
  EditBoxOnEnterPressed = function(self)
    ChatEdit_FocusActiveWindow();
    self:GetParent():Hide();
  end,
  EditBoxOnEscapePressed = function(self)
    ChatEdit_FocusActiveWindow();
    self:GetParent():Hide();
  end,
  EditBoxOnTextChanged = function(self)
    if(self~=nil and self:GetText() ~= StaticPopupDialogs['GSE_SEQUENCEHELP'].url) then
      self:SetText(StaticPopupDialogs['GSE_SEQUENCEHELP'].url)
    end
    self:HighlightText()
    self:ClearFocus()
    ChatEdit_FocusActiveWindow();
  end,
}

StaticPopupDialogs["GSE-MacroImportSuccess"] = {
  text = L["Macro Import Successful."],
  button1 = L["Close"],
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,  -- avoid some UI taint, see http://www.wowace.com/announcements/how-to-avoid-some-ui-taint/
}

StaticPopupDialogs["GSE-MacroImportFailure"] = {
  text = L["Macro unable to be imported."],
  button1 = L["Close"],
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,  -- avoid some UI taint, see http://www.wowace.com/announcements/how-to-avoid-some-ui-taint/
}

StaticPopupDialogs["GSE-DeleteMacroDialog"] = {
  text = "",
  button1 = L["Delete"],
  button2 = L["Cancel"],
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,  -- avoid some UI taint, see http://www.wowace.com/announcements/how-to-avoid-some-ui-taint/
}
