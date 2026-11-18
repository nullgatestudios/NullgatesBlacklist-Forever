-- Nullgate's Blacklist: text lookup and chat output shared by every module. Locale
-- strings are read at call time because the language is chosen after load.
local _, ns = ...

local Const = ns.Const

local Output = {}
ns.Output = Output

local PREFIX = "|cff66ccff" .. Const.DISPLAY_NAME .. "|r: "

-- Locale string for key; the key itself when it is missing.
function Output.Text(key)
  local value = ns.L and ns.L[key]
  if value == nil then return key end
  return value
end

-- The text of an error key; a detail such as a line number fills its "%d".
function Output.Error(key, detail)
  local text = Output.Text(key)
  if detail ~= nil then return string.format(text, detail) end
  return text
end

-- A timestamp as YYYY-MM-DD, or nil when there is none.
function Output.Date(timestamp)
  local format = date or (os and os.date)
  if not format or type(timestamp) ~= "number" then return nil end
  return format("%Y-%m-%d", timestamp)
end

-- The display names of a label set { [id] = true }, in label order, joined by
-- ", ". Empty for no labels.
function Output.LabelText(labels)
  local names = {}
  if type(labels) == "table" then
    for _, entry in ipairs(Const.Labels) do
      if labels[entry.id] then names[#names + 1] = Output.Text(Const.LabelLocaleKey(entry.id)) end
    end
  end
  return table.concat(names, ", ")
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
