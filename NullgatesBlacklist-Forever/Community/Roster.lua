-- Nullgate's Blacklist: who is a friend, who is online, and whether the player is in a
-- guild (section 8.7). Character friends only for now; Battle.net friends are
-- not read. The list is rebuilt when the client says it changed, at most once a
-- second, and listeners hear about friends who just came online.
local _, ns = ...

local Safe = ns.Safe
local Identity = ns.Identity

local Roster = {}
ns.Roster = Roster

local friends = nil          -- key -> { name =, online = }, nil until first built
local online = {}            -- key -> true for friends seen online at the last scan
local listeners = {}
local pending = false

-- Reads the friend list from the client. Always returns a table.
local function ReadFriends()
  local result = {}
  local api = C_FriendList
  if type(api) ~= "table" or type(api.GetNumFriends) ~= "function"
    or type(api.GetFriendInfoByIndex) ~= "function" then
    return result
  end
  local ok, count = pcall(api.GetNumFriends)
  if not ok or type(count) ~= "number" then return result end
  for index = 1, count do
    local good, info = pcall(api.GetFriendInfoByIndex, index)
    if good and type(info) == "table" then
      local name = Identity.Normalize(Safe.Str(info.name))
      if name then
        result[string.lower(name)] = { name = name, online = info.connected and true or false }
      end
    end
  end
  return result
end

-- Rebuilds the cache and tells listeners which friends just came online.
function Roster.Refresh()
  friends = ReadFriends()
  local now, arrived = {}, {}
  for key, friend in pairs(friends) do
    if friend.online then
      now[key] = true
      if not online[key] then arrived[#arrived + 1] = friend.name end
    end
  end
  online = now
  table.sort(arrived)
  if #arrived > 0 then
    for _, listener in ipairs(listeners) do listener(arrived) end
  end
end

local function Cache()
  if not friends then friends = ReadFriends() end
  return friends
end

-- True when the name is on the player's character friend list.
function Roster.IsFriend(name)
  local key = Identity.Key(name)
  return key ~= nil and Cache()[key] ~= nil
end

function Roster.IsOnline(name)
  local key = Identity.Key(name)
  local friend = key and Cache()[key]
  return friend ~= nil and friend.online
end

-- The friends who are online right now, sorted.
function Roster.OnlineNames()
  local names = {}
  for _, friend in pairs(Cache()) do
    if friend.online then names[#names + 1] = friend.name end
  end
  table.sort(names)
  return names
end

-- Registers a function(namesArray) called when friends come online.
function Roster.OnOnline(fn)
  listeners[#listeners + 1] = fn
end

function Roster.InGuild()
  return type(IsInGuild) == "function" and IsInGuild() and true or false
end

local function Schedule()
  if pending then return end
  pending = true
  C_Timer.After(1, function()
    pending = false
    Roster.Refresh()
  end)
end

local registered = false

-- Listens for friend list changes. Returns false when the client has no friend
-- list API; guild sharing still works.
function Roster.Register()
  if registered then return true end
  if type(CreateFrame) ~= "function" or type(C_Timer) ~= "table" then return false end
  local frame = CreateFrame("Frame")
  frame:RegisterEvent("FRIENDLIST_UPDATE")
  frame:RegisterEvent("PLAYER_ENTERING_WORLD")
  frame:SetScript("OnEvent", Schedule)
  if type(C_FriendList) == "table" and type(C_FriendList.ShowFriends) == "function" then
    pcall(C_FriendList.ShowFriends)
  end
  registered = true
  return true
end

-- Forgets what was seen (tests).
function Roster.Reset()
  friends, online, listeners, pending = nil, {}, {}, false
end
