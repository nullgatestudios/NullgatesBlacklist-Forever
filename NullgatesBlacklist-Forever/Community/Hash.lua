-- Nullgate's Blacklist: hashing and tokens for community reports (section 8.2). Pure
-- module. Lua 5.1 has no 64-bit integers and no bit library, so a 64-bit
-- target hash is built from two independent 32-bit FNV-1a hashes, using
-- arithmetic only.
--
-- The hash keeps casual readers from browsing names; anyone can hash a list of
-- known names, so it is not encryption.
local _, ns = ...

local Const = ns.Const

local Hash = {}
ns.Hash = Hash

local TWO32 = 4294967296
local OFFSET_A = 2166136261 -- the standard FNV-1a 32-bit offset basis
local OFFSET_B = 2654435769 -- an unrelated basis for the second half

-- XOR of two bytes without a bit library.
local function XorByte(a, b)
  local result, bit = 0, 1
  for _ = 1, 8 do
    if (a % 2) ~= (b % 2) then result = result + bit end
    a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
  end
  return result
end

-- 32-bit FNV-1a. The prime is 16777619 = 256 * 65536 + 403; multiplying by it
-- modulo 2^32 only needs the low 16 bits of the cross terms, so every product
-- stays far below 2^53 and no precision is lost.
local function Fnv32(text, offset)
  local hash = offset
  for index = 1, #text do
    local low = hash % 256
    hash = hash - low + XorByte(low, text:byte(index))
    local hi, lo = math.floor(hash / 65536), hash % 65536
    local cross = (hi * 403 + lo * 256) % 65536
    hash = (cross * 65536 + lo * 403) % TWO32
  end
  return hash
end
Hash.Fnv32 = Fnv32

-- The server time in seconds; the local clock where the client call is missing.
function Hash.ServerTime()
  if type(GetServerTime) == "function" then return GetServerTime() end
  return time()
end

function Hash.Season(serverTime)
  return math.floor(serverTime / (Const.SeasonDays * 86400))
end

function Hash.Day(serverTime)
  return math.floor(serverTime / 86400)
end

-- 16 lowercase hex digits for a target key in a season.
-- group is a source group ("friends" for friends and guild, or "global"); global
-- hashes use their own salt, so the two worlds can't be matched against each other.
function Hash.Target(targetKey, seasonId, group)
  local salt = group == "global" and Const.GlobalSeasonSalt or Const.SeasonSalt
  local text = salt .. seasonId .. ":" .. targetKey
  return string.format("%08x%08x", Fnv32(text, OFFSET_A), Fnv32(text, OFFSET_B))
end

-- The hashes a name can be filed under right now in one group: this season's and
-- the previous one's, because a report may have been made just before a boundary.
function Hash.Candidates(targetKey, serverTime, group)
  local season = Hash.Season(serverTime)
  return { Hash.Target(targetKey, season, group), Hash.Target(targetKey, season - 1, group) }
end

-- The candidates of both groups (for data kept about a name in every group).
function Hash.AllCandidates(targetKey, serverTime)
  local list = Hash.Candidates(targetKey, serverTime, "friends")
  for _, hash in ipairs(Hash.Candidates(targetKey, serverTime, "global")) do list[#list + 1] = hash end
  return list
end

-- 8 hex digits, stable for one install and target, unlinkable across targets.
function Hash.Token(installSecret, targetHash)
  return string.format("%08x", Fnv32(installSecret .. targetHash, OFFSET_A))
end
