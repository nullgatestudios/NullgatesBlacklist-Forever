-- Blackbook: the "Settings" tab (section 9): language, enforcement toggles and
-- the minimap button. The auto-reply control joins in M7 with the feature.
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

  local language = Widgets.RadioGroup(content, {
    { value = "auto", text = Text("LANG_AUTO") },
    { value = "en", text = Text("LANG_EN") },
    { value = "de", text = Text("LANG_DE") },
  }, function(value)
    if Settings.SetLanguage(value) then
      Print(string.format(Text("MSG_LANG_SET"), Escape(value)))
    end
  end)
  if not language then return nil end

  local y = 4
  local function Place(widget, indent, height)
    widget:SetPoint("TOPLEFT", content, "TOPLEFT", indent, -y)
    y = y + height
  end

  Place(Widgets.Label(content, Text("OPT_LANGUAGE")), 4, 22)
  Place(language.buttons[1].button, 0, 40)
  language:Chain(120)

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

  return {
    Refresh = function()
      language:SetValue(Settings.Get("language") or "auto")
      for path, check in pairs(controls) do
        check:SetChecked(Settings.Get(path) and true or false)
      end
    end,
  }
end

ns.Manager.RegisterTab("settings", "TAB_SETTINGS", Build)
