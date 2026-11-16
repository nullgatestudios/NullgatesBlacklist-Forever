-- Blackbook: text lookup and chat output shared by every module. Locale
-- strings are read at call time because the language is chosen after load.
local _, ns = ...

local Const = ns.Const

local Output = {}
ns.Output = Output

local PREFIX = "|cff66ccff" .. Const.ADDON_NAME .. "|r: "

-- Locale string for key; the key itself when it is missing.
function Output.Text(key)
  local value = ns.L and ns.L[key]
  if value == nil then return key end
  return value
end

-- Player-provided text goes into chat, so a pipe must be escaped (section 10).
function Output.Escape(value)
  return (tostring(value):gsub("|", "||"))
end

-- Prints one line to the default chat frame with the addon prefix.
function Output.Print(message)
  local frame = DEFAULT_CHAT_FRAME
  if frame then frame:AddMessage(PREFIX .. tostring(message)) end
end
