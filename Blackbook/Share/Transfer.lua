-- Blackbook: sending the own list to another player in game (section 7.4).
-- Whispers only, over the addon prefix BKX:
--
--   OFFER  id, partCount, recordCount, listName    sender proposes
--   ACCEPT id                                      receiver agrees
--   DECLINE id                                     receiver declines or is busy
--   PART   id, index, chunk                        one slice of the list code
--
-- Sender: OFFERED -> SENDING -> DONE.  Receiver: OFFERED -> ACCEPTED ->
-- RECEIVING -> DONE. Anything that fails or times out closes the session.
local _, ns = ...

local Const = ns.Const
local Safe = ns.Safe
local Identity = ns.Identity
local Output = ns.Output
local Wire = ns.Wire
local Codec = ns.Codec

local Text, Print, Escape = Output.Text, Output.Print, Output.Escape

local Transfer = {}
ns.Transfer = Transfer

local PREFIX = Const.TRANSFER_PREFIX
local POPUP = "BLACKBOOK_TRANSFER_OFFER"
local OFFER_TIMEOUT = 60     -- the sender stops waiting for an answer
local POPUP_TIMEOUT = 55     -- the receiver's popup gives up slightly sooner
local SESSION_EXPIRY = 300   -- a receiving session is dropped after this long
local SEND_INTERVAL = 0.3
local MAX_TRIES = 20
local BUSY_REPLY_SECONDS = 10

-- The few client calls this module needs. Tests replace them.
Transfer.io = {
  send = function(message, target)
    local api = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if type(api) ~= "function" then return false end
    local ok, result = pcall(api, PREFIX, message, "WHISPER", target)
    -- Newer clients return a result code (0 = sent), older ones nothing or a boolean.
    return ok and (result == nil or result == true or result == 0)
  end,
  after = function(seconds, fn) C_Timer.After(seconds, fn) end,
  now = function()
    if type(GetTime) == "function" then return GetTime() end
    return time()
  end,
}

local function Key(name) return string.lower(name) end

local function Hex(byteCount)
  local parts = {}
  for index = 1, byteCount do parts[index] = string.format("%02x", math.random(0, 255)) end
  return table.concat(parts)
end

-- Text that goes into a message field or a popup: no control characters, bounded.
local function FieldText(text)
  return Wire.Truncate((tostring(text):gsub("%c", " ")), Const.Limits.offerName)
end

-- --- Outgoing queue: one message per SEND_INTERVAL ----------------------------

local queue = {}
local pumping = false
local outgoing = {}   -- target key -> sender session
local incoming        -- the one receiving session, or nil
local lastBusy = {}   -- sender key -> time of the last busy reply

local function Close(session)
  session.closed = true
  if session.outKey and outgoing[session.outKey] == session then outgoing[session.outKey] = nil end
  if incoming == session then incoming = nil end
end

local function Fail(session)
  if session.closed then return end
  Close(session)
  Print(string.format(Text("TRANSFER_FAILED"), Escape(session.peer)))
end

local function Pump()
  while queue[1] and queue[1].session and queue[1].session.closed do table.remove(queue, 1) end
  local item = queue[1]
  if not item then
    pumping = false
    return
  end
  if Transfer.io.send(item.text, item.target) then
    table.remove(queue, 1)
    if item.onSent then item.onSent() end
  else
    item.tries = (item.tries or 0) + 1
    if item.tries >= MAX_TRIES then
      table.remove(queue, 1)
      if item.session then Fail(item.session) end
    end
  end
  Transfer.io.after(SEND_INTERVAL, Pump)
end

-- session may be nil (a reply that belongs to no session of ours).
local function Enqueue(target, text, session, onSent)
  queue[#queue + 1] = { target = target, text = text, session = session, onSent = onSent }
  if not pumping then
    pumping = true
    Pump()
  end
end

-- --- Sending -------------------------------------------------------------------

local function Chunks(code)
  local size, parts = Const.Limits.transferChunk, {}
  for start = 1, #code, size do parts[#parts + 1] = code:sub(start, start + size - 1) end
  return parts
end

-- Offers the own list to a player. Returns true, or false and a locale key.
function Transfer.Send(name)
  local target = Identity.Normalize(name)
  if not target then return false, "ERR_NAME" end
  if Identity.Same(target, Identity.Self()) then return false, "MSG_SELF" end
  local key = Key(target)
  if outgoing[key] then return false, "ERR_TRANSFER_BUSY" end

  local code, count = Codec.ExportOwn()
  if count == 0 then return false, "ERR_EXPORT_EMPTY" end
  local parts = Chunks(code)
  if #parts > Const.Limits.transferParts then return false, "ERR_TRANSFER_TOO_BIG" end

  local listName = Codec.ListName()
  local session = { id = Hex(4), peer = target, outKey = key, state = "OFFERED", parts = parts }
  outgoing[key] = session
  Enqueue(target, table.concat({ "OFFER", session.id, #parts, count, FieldText(listName) }, "\t"), session)
  Print(string.format(Text("TRANSFER_OFFERED"), Escape(target)))
  Transfer.io.after(OFFER_TIMEOUT, function()
    if session.closed or session.state ~= "OFFERED" then return end
    Close(session)
    Print(string.format(Text("TRANSFER_NO_ANSWER"), Escape(target)))
  end)
  return true
end

local function OnAccept(sender, fields)
  local session = outgoing[Key(sender)]
  if not session or session.closed or session.state ~= "OFFERED" or fields[2] ~= session.id then return end
  session.state = "SENDING"
  for index, chunk in ipairs(session.parts) do
    local last = index == #session.parts
    Enqueue(session.peer, table.concat({ "PART", session.id, index, chunk }, "\t"), session, last and function()
      session.state = "DONE"
      Close(session)
      Print(string.format(Text("TRANSFER_SENT"), Escape(session.peer)))
    end or nil)
  end
end

local function OnDecline(sender, fields)
  local session = outgoing[Key(sender)]
  if not session or session.closed or fields[2] ~= session.id then return end
  Close(session)
  Print(string.format(Text("TRANSFER_DECLINED"), Escape(session.peer)))
end

-- --- Receiving -----------------------------------------------------------------

local function HidePopup()
  if type(StaticPopup_Hide) == "function" then pcall(StaticPopup_Hide, POPUP) end
end

local function Expire(session)
  if session.closed then return end
  Close(session)
  HidePopup()
  Print(string.format(Text("TRANSFER_EXPIRED"), Escape(session.peer)))
end

-- Called when the player clicks Accept in the popup.
function Transfer.AcceptIncoming()
  local session = incoming
  if not session or session.state ~= "OFFERED" then return end
  session.state = "ACCEPTED"
  Enqueue(session.peer, "ACCEPT\t" .. session.id, session)
  Transfer.io.after(SESSION_EXPIRY, function() Expire(session) end)
end

-- Called for Decline, Escape and the popup's own timeout.
function Transfer.DeclineIncoming()
  local session = incoming
  if not session or session.state ~= "OFFERED" then return end
  Close(session)
  Enqueue(session.peer, "DECLINE\t" .. session.id, nil)
end

-- False when the client has no popup system.
local function ShowOffer(session)
  if type(StaticPopupDialogs) ~= "table" or type(StaticPopup_Show) ~= "function" then return false end
  StaticPopupDialogs[POPUP] = {
    text = "%s\n%s",
    button1 = Text("TRANSFER_ACCEPT"),
    button2 = Text("TRANSFER_DECLINE"),
    OnAccept = function() Transfer.AcceptIncoming() end,
    OnCancel = function() Transfer.DeclineIncoming() end,
    timeout = POPUP_TIMEOUT,
    whileDead = true,
    hideOnEscape = true,
  }
  StaticPopup_Show(POPUP,
    string.format(Text("TRANSFER_OFFER_FROM"), Escape(session.peer)),
    string.format(Text("TRANSFER_OFFER_LIST"), Escape(session.listName), session.recordCount))
  Transfer.io.after(POPUP_TIMEOUT + 1, function()
    if not session.closed and session.state == "OFFERED" then
      Transfer.DeclineIncoming()
      HidePopup()
    end
  end)
  return true
end

local function WholeBetween(text, low, high)
  local number = tonumber(text)
  if number and number == math.floor(number) and number >= low and number <= high then return number end
  return nil
end

local function OnOffer(sender, fields)
  if #fields ~= 5 then return end
  local id = fields[2]
  local parts = WholeBetween(fields[3], 1, Const.Limits.transferParts)
  local records = WholeBetween(fields[4], 0, Const.Limits.recordsPerList)
  if #id ~= 8 or id:find("[^0-9a-f]") or not parts or not records then return end
  if ns.Resolver.Verdict(sender) == "ignore" then return end -- silence for ignored players

  if incoming and not incoming.closed then
    -- Busy: say so once in a while, so a flood does not become a flood of replies.
    local now, key = Transfer.io.now(), Key(sender)
    if not lastBusy[key] or now - lastBusy[key] >= BUSY_REPLY_SECONDS then
      lastBusy[key] = now
      Enqueue(sender, "DECLINE\t" .. id, nil)
    end
    return
  end

  local session = { id = id, peer = sender, state = "OFFERED", partCount = parts,
    recordCount = records, listName = FieldText(fields[5]), got = {}, received = 0, chunks = {} }
  incoming = session
  if not ShowOffer(session) then
    Close(session)
    Enqueue(sender, "DECLINE\t" .. id, nil)
    Print(Text("TRANSFER_NO_POPUP"))
  end
end

local function Finish(session)
  Close(session)
  local list, err, detail = Codec.Decode(table.concat(session.chunks))
  if not list then
    Print(string.format(Text("TRANSFER_INVALID"), Escape(session.peer), Output.Error(err, detail)))
    return
  end
  local subscription, replaced = ns.Subscriptions.Import(list)
  if not subscription then
    Print(string.format(Text("TRANSFER_INVALID"), Escape(session.peer), Text(replaced)))
    return
  end
  Print(ns.Subscriptions.Summary(subscription, replaced))
end

local function OnPart(sender, fields)
  local session = incoming
  if not session or session.closed then return end
  if session.state ~= "ACCEPTED" and session.state ~= "RECEIVING" then return end
  if not Identity.Same(sender, session.peer) or fields[2] ~= session.id or #fields ~= 4 then return end
  local index = WholeBetween(fields[3], 1, session.partCount)
  local chunk = fields[4]
  if not index or session.got[index] or #chunk < 1 or #chunk > Const.Limits.transferChunk then return end
  session.state = "RECEIVING"
  session.got[index] = true
  session.chunks[index] = chunk
  session.received = session.received + 1
  if session.received == session.partCount then Finish(session) end
end

-- --- Events --------------------------------------------------------------------

local HANDLERS = { OFFER = OnOffer, ACCEPT = OnAccept, DECLINE = OnDecline, PART = OnPart }

function Transfer.OnMessage(prefix, message, channel, sender)
  if prefix ~= PREFIX or channel ~= "WHISPER" then return end
  local text = Safe.Str(message)
  local name = Identity.Normalize(sender)
  if not text or not name or Identity.Same(name, Identity.Self()) then return end
  local fields = Wire.Split(text)
  local handler = HANDLERS[fields[1]]
  if handler then handler(name, fields) end
end

local registered = false

-- Registers the prefix and listens for addon messages. Returns false when the
-- client has no addon message API; the rest of Blackbook keeps working.
function Transfer.Register()
  if registered then return true end
  local register = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
  if type(register) ~= "function" or type(CreateFrame) ~= "function" then
    Print(Text("MSG_NO_TRANSFER"))
    return false
  end
  pcall(register, PREFIX)
  local frame = CreateFrame("Frame")
  frame:RegisterEvent("CHAT_MSG_ADDON")
  frame:SetScript("OnEvent", function(_, _, prefix, message, channel, sender)
    Transfer.OnMessage(prefix, message, channel, sender)
  end)
  registered = true
  return true
end
