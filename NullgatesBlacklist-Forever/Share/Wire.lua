-- Nullgate's Blacklist: escaping, line format, Base64 and the checksum of the portable
-- list code (section 7). Pure module: nothing here touches the client.
local _, ns = ...

local Wire = {}
ns.Wire = Wire

-- --- Field escaping ----------------------------------------------------------

-- Escapes a field value: backslash, tab and newline become \\, \t and \n. A
-- carriage return is dropped (chat tools add them when they wrap lines).
function Wire.Escape(text)
  text = tostring(text or "")
  text = text:gsub("\r", ""):gsub("\\", "\\\\"):gsub("\t", "\\t"):gsub("\n", "\\n")
  return text
end

local UNESCAPED = { t = "\t", n = "\n", ["\\"] = "\\" }

-- Reverses Escape. An unknown escape keeps the character after the backslash.
function Wire.Unescape(text)
  return (text:gsub("\\(.)", function(char) return UNESCAPED[char] or char end))
end

-- Joins values into one TAB separated line, each escaped.
function Wire.Line(...)
  local fields = { ... }
  for index = 1, select("#", ...) do
    fields[index] = Wire.Escape(fields[index])
  end
  return table.concat(fields, "\t", 1, select("#", ...))
end

-- Splits a line at TABs. An empty line gives one empty field.
function Wire.Split(line)
  local fields, start = {}, 1
  while true do
    local position = line:find("\t", start, true)
    if not position then
      fields[#fields + 1] = line:sub(start)
      return fields
    end
    fields[#fields + 1] = line:sub(start, position - 1)
    start = position + 1
  end
end

-- Cuts text to at most maxBytes without splitting a UTF-8 character.
function Wire.Truncate(text, maxBytes)
  if #text <= maxBytes then return text end
  local cut = maxBytes
  while cut > 0 do
    local following = text:byte(cut + 1)
    if following and following >= 0x80 and following < 0xC0 then
      cut = cut - 1
    else
      break
    end
  end
  return text:sub(1, cut)
end

-- --- Base64 (standard alphabet, "=" padding) -----------------------------------

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local CHAR, VALUE = {}, {}
for index = 1, 64 do
  local char = ALPHABET:sub(index, index)
  CHAR[index - 1] = char
  VALUE[char:byte()] = index - 1
end

function Wire.Base64Encode(data)
  local out, count = {}, 0
  for index = 1, #data, 3 do
    local a, b, c = data:byte(index, index + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    count = count + 1
    out[count] = CHAR[math.floor(n / 262144)] .. CHAR[math.floor(n / 4096) % 64]
      .. (b and CHAR[math.floor(n / 64) % 64] or "=") .. (c and CHAR[n % 64] or "=")
  end
  return table.concat(out)
end

-- Returns the decoded bytes, or nil for anything that is not canonical enough
-- to trust: a length that is not a multiple of 4, a character outside the
-- alphabet, or padding anywhere but the end.
function Wire.Base64Decode(text)
  if type(text) ~= "string" or #text % 4 ~= 0 then return nil end
  local out, count = {}, 0
  for index = 1, #text, 4 do
    local c1, c2, c3, c4 = text:byte(index, index + 3)
    local pad3, pad4 = c3 == 61, c4 == 61
    local v1, v2 = VALUE[c1], VALUE[c2]
    local v3 = pad3 and 0 or VALUE[c3]
    local v4 = pad4 and 0 or VALUE[c4]
    if not (v1 and v2 and v3 and v4) then return nil end
    if pad3 and not pad4 then return nil end
    if (pad3 or pad4) and index + 3 ~= #text then return nil end
    local n = v1 * 262144 + v2 * 4096 + v3 * 64 + v4
    local b1, b2, b3 = math.floor(n / 65536), math.floor(n / 256) % 256, n % 256
    count = count + 1
    if pad3 then
      out[count] = string.char(b1)
    elseif pad4 then
      out[count] = string.char(b1, b2)
    else
      out[count] = string.char(b1, b2, b3)
    end
  end
  return table.concat(out)
end

-- --- Checksum ------------------------------------------------------------------

-- Adler-32 as 8 lowercase hex digits. The two 16-bit halves are formatted
-- separately so the value never overflows a number format.
function Wire.Checksum(data)
  local a, b = 1, 0
  for index = 1, #data do
    a = (a + data:byte(index)) % 65521
    b = (b + a) % 65521
  end
  return string.format("%04x%04x", b, a)
end
