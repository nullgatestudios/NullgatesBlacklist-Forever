-- Blackbook: the "Settings" tab (section 9): language, enforcement toggles, the
-- minimap button, the automatic reply and a way back into the setup wizard.
local _, ns = ...

local Settings = ns.Settings
local Output = ns.Output
local Widgets = ns.Widgets

local Text, Print, Escape = Output.Text, Output.Print, Output.Escape

local TabSettings = {}
ns.TabSettings = TabSettings

-- { setting path, locale key }
local TOGGLES = {
  { "hideChat", "OPT_HIDE_CHAT" },
  { "autoDecline", "OPT_AUTO_DECLINE" },
  { "showNotices", "OPT_SHOW_NOTICES" },
  { "showMinimap", "OPT_SHOW_MINIMAP" },
}

local function Build(content)
  local controls = {}

  local language = Widgets.Choice(content, ns.Locale.Choices(), function(value)
    -- The language changes at once: the window is rebuilt in it.
    if ns.Locale.Set(value) then
      Print(string.format(Output.Text("MSG_LANG_SET"), Escape(ns.Locale.NameOf(value))))
    end
  end)
  if not language then return nil end

  local y = 4
  local function Place(widget, indent, height)
    widget:SetPoint("TOPLEFT", content, "TOPLEFT", indent, -y)
    y = y + height
  end

  Place(Widgets.Label(content, Text("OPT_LANGUAGE")), 4, 22)
  Place(language.frame, 4, language.height + 14)

  Place(Widgets.Label(content, Text("OPT_ENFORCEMENT")), 4, 22)
  for _, toggle in ipairs(TOGGLES) do
    local path = toggle[1]
    local check = Widgets.Checkbox(content, Text(toggle[2]), function(self)
      Settings.Set(path, self:GetChecked() and true or false)
    end)
    if not check then return nil end
    Place(check, 0, 28)
    controls[path] = check
  end

  -- Test mode shows sample tooltips on other players; it is never saved.
  local testMode = Widgets.Checkbox(content, Text("OPT_TEST_MODE"), function(self)
    local on = self:GetChecked() and true or false
    ns.Tooltip.SetTestMode(on)
    Print(Text(on and "MSG_TEST_MODE_ON" or "MSG_TEST_MODE_OFF"))
  end)
  if not testMode then return nil end
  Place(testMode, 0, 28)

  Place(Widgets.Label(content, Text("OPT_REPLY")), 4, 24)
  local reply = ns.ReplyControl.Create(content, Place)
  if not reply then return nil end

  local setup = Widgets.Button(content, Text("OPT_RUN_SETUP"), 200, function() ns.Wizard.Open() end)
  if not setup then return nil end
  Place(setup, 0, 30)

  return {
    Refresh = function()
      language:SetValue(Settings.Get("language") or "auto")
      for path, check in pairs(controls) do
        check:SetChecked(Settings.Get(path) and true or false)
      end
      testMode:SetChecked(ns.Tooltip.TestMode())
      reply.Refresh()
    end,
  }
end

ns.Manager.RegisterTab("settings", "TAB_SETTINGS", Build)
