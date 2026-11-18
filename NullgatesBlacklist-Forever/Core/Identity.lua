-- Nullgate's Blacklist: name parsing and the same-player check (section 6.1).
-- Pure module: UnitName is only read inside FromUnit, never at load time.
local _, ns = ...

local Safe = ns.Safe

local Identity = {}
ns.Identity = Identity

local function Trim(text)
  if type(strtrim) == "function" then return strtrim(text) end
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Trim, drop a trailing "-Realm" suffix (the part after the last hyphen),
-- collapse internal whitespace. Returns nil for empty, non-string or secret
-- input.
function Identity.Normalize(text)
  local value = Safe.Str(text)
  if not value then return nil end
  value = Trim(value)
  if value == "" then return nil end
  local withoutRealm = value:match("^(.*)%-")
  if withoutRealm then value = withoutRealm end
  value = value:gsub("%s+", " ")
  value = Trim(value)
  if value == "" then return nil end
  return value
end

-- Number of characters in a UTF-8 string (continuation bytes are not counted),
-- so limits such as "255 characters" do not punish umlauts.
function Identity.CharCount(text)
  if type(text) ~= "string" then return 0 end
  local count = 0
  for index = 1, #text do
    local byte = string.byte(text, index)
    if byte < 0x80 or byte >= 0xC0 then count = count + 1 end
  end
  return count
end

-- Target key: lowercased normalized name, used as the record table key.
function Identity.Key(name)
  local normalized = Identity.Normalize(name)
  if not normalized then return nil end
  return string.lower(normalized)
end

-- True when both names normalize to the same key.
function Identity.Same(a, b)
  local keyA = Identity.Key(a)
  if not keyA then return false end
  return keyA == Identity.Key(b)
end

-- The joined first and last name of a unit, normalized. nil when the unit
-- does not exist or any part is secret.
function Identity.FromUnit(unit)
  if type(unit) ~= "string" then return nil end
  if type(UnitName) ~= "function" then return nil end
  local first, last = UnitName(unit)
  if first == nil then return nil end
  if type(first) ~= "string" or Safe.IsSecret(first) then return nil end
  if last ~= nil then
    if type(last) ~= "string" or Safe.IsSecret(last) then return nil end
    if last ~= "" then
      return Identity.Normalize(first .. " " .. last)
    end
  end
  return Identity.Normalize(first)
end

-- The player's own normalized name, "?" when it is unavailable.
function Identity.Self()
  return Identity.FromUnit("player") or "?"
end
