-- Nullgate's Blacklist: the language registry and the switch (section 10). Each language
-- file registers its table here. Changing the language takes effect at once:
-- the registered windows are rebuilt from scratch in the new language, so no
-- text can be left over from the old one and no /reload is needed.
local _, ns = ...

local Locale = {}
ns.Locale = Locale

Locale.Tables = {}  -- code -> text table
Locale.Names = {}   -- code -> the language's own name ("Deutsch")
Locale.Order = {}   -- codes in the order they were registered; English first
Locale.Base = nil   -- the English table: every other language falls back to it
Locale.current = nil

local hooks = {}

-- Client locale -> language code. Only codes that are registered are used.
local CLIENT = {
  enUS = "en", enGB = "en", deDE = "de", frFR = "fr", esES = "es", esMX = "es",
  ptBR = "pt", ptPT = "pt", ruRU = "ru", koKR = "ko", zhCN = "zh", zhTW = "zh",
  itIT = "it",
}

-- Called by every language file.
function Locale.Register(code, name, textTable)
  if not Locale.Tables[code] then Locale.Order[#Locale.Order + 1] = code end
  Locale.Tables[code] = textTable
  Locale.Names[code] = name
  if code == "en" then Locale.Base = textTable end
end

-- True for "auto" and for a registered language code.
function Locale.IsValid(choice)
  return choice == "auto" or (type(choice) == "string" and Locale.Tables[choice] ~= nil)
end

-- The language code a saved choice stands for ("auto" follows the client). A saved
-- language that is no longer offered also follows the client.
function Locale.Resolve(choice)
  if choice == "auto" or choice == nil or not Locale.Tables[choice] then
    local client = "enUS"
    if type(GetLocale) == "function" then client = GetLocale() or client end
    local code = CLIENT[client]
    return (code and Locale.Tables[code]) and code or "en"
  end
  return choice
end

-- The languages as { code =, name = }, English first.
function Locale.List()
  local list = {}
  for _, code in ipairs(Locale.Order) do list[#list + 1] = { code = code, name = Locale.Names[code] } end
  return list
end

-- The choices for a language picker: "automatic" first, then every language under
-- its own name. Each is { value =, text = }.
function Locale.Choices()
  local choices = { { value = "auto", text = ns.Output.Text("LANG_AUTO") } }
  for _, entry in ipairs(Locale.List()) do
    choices[#choices + 1] = { value = entry.code, text = entry.name }
  end
  return choices
end

-- The name to show for a saved choice.
function Locale.NameOf(choice)
  if choice == "auto" then return ns.Output.Text("LANG_AUTO") end
  return Locale.Names[choice] or tostring(choice)
end

-- Registers a function to run after the language changed (windows rebuild here).
function Locale.OnChange(fn)
  hooks[#hooks + 1] = fn
end

-- Makes the saved choice the active language. Returns true when it changed.
function Locale.Apply()
  local code = Locale.Resolve(ns.Settings.Get("language"))
  if code == Locale.current then return false end
  Locale.current = code
  ns.L = Locale.Tables[code] or Locale.Base
  for _, hook in ipairs(hooks) do hook() end
  return true
end

-- Saves a choice ("auto" or a code) and applies it at once. Returns the choice,
-- or nil when it is not valid.
function Locale.Set(choice)
  if not ns.Settings.SetLanguage(choice) then return nil end
  Locale.Apply()
  return choice
end
