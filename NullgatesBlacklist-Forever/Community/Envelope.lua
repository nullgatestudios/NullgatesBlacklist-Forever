-- Nullgate's Blacklist: the envelope around messages on the global channel (section 8.10).
-- The text is scrambled with a keystream that depends on the server hour, so
-- that a log of the channel is not a plain list of reports and reports from
-- different hours do not look alike on the wire.
--
-- THIS IS OBFUSCATION, NOT SECRECY. The key comes from this public code and the
-- hour, so anyone who modifies a client can read everything. Pure module.
--
-- A message only ever contains the symbols of a report (digits, a to f, ":", ";",
-- a TAB and the letters R, X, H). Each symbol is moved along a 32 symbol alphabet
-- by the next number of the keystream, so the result has the same length, uses
-- only printable characters and survives an addon message unchanged.
local _, ns = ...

local Const = ns.Const
local Hash = ns.Hash

local Envelope = {}
ns.Envelope = Envelope

-- 32 printable symbols. "~" stands for the TAB of a report while it is enveloped.
local ALPHABET = "0123456789abcdef:;~RXHghijklmnop"
local SIZE = #ALPHABET
local INDEX = {}
for position = 1, SIZE do INDEX[ALPHABET:byte(position)] = position - 1 end

local TWO32 = 4294967296

function Envelope.Hour(serverTime)
  return math.floor(serverTime / 3600)
end

-- The numbers 0..31 that move the symbols, for one hour. A linear congruential
-- generator seeded from a hash of the constant salt and the hour; the products
-- stay below 2^53, so the arithmetic is exact in Lua 5.1.
local function Keystream(hour)
  local state = Hash.Fnv32(Const.EnvelopeSalt .. hour, 2166136261)
  return function()
    state = (1664525 * state + 1013904223) % TWO32
    return math.floor(state / 65536) % SIZE
  end
end

-- Scrambles a report message. Returns nil for text that is not made of report symbols.
function Envelope.Encode(text, hour)
  local nextShift = Keystream(hour)
  local out = {}
  for position = 1, #text do
    local byte = text:byte(position)
    if byte == 9 then byte = 126 end -- TAB becomes "~"
    local index = INDEX[byte]
    if not index then return nil end
    local shifted = (index + nextShift()) % SIZE
    out[position] = ALPHABET:sub(shifted + 1, shifted + 1)
  end
  return table.concat(out)
end

-- Undoes Encode for one hour. The result is only meaningful if that hour was the
-- right one; a wrong hour gives text that no report parser accepts. Returns nil
-- for text with a symbol outside the alphabet.
function Envelope.Decode(text, hour)
  local nextShift = Keystream(hour)
  local out = {}
  for position = 1, #text do
    local index = INDEX[text:byte(position)]
    if not index then return nil end
    local plain = (index - nextShift()) % SIZE
    local char = ALPHABET:sub(plain + 1, plain + 1)
    out[position] = char == "~" and "\t" or char
  end
  return table.concat(out)
end

-- The hours a receiver tries, in order: this one, the one before (a message sent
-- just before the hour turned) and the one after (the sender's clock is ahead).
function Envelope.Hours(serverTime)
  local hour = Envelope.Hour(serverTime)
  return { hour, hour - 1, hour + 1 }
end
