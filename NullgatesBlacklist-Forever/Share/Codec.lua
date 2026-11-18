-- Nullgate's Blacklist: the portable list code (section 7). Encode and Decode are pure;
-- ExportOwn only gathers the player's own records and export settings first.
--
--   BK1C:<Base64 of the compressed payload>:<checksum>
--   BK1R:<Base64 of the raw payload>:<checksum>
--
-- The checksum covers the uncompressed payload. Decode never trusts its input:
-- every size, count and field is checked before anything is returned.
local _, ns = ...

local Const = ns.Const
local Identity = ns.Identity
local Wire = ns.Wire

local Codec = {}
ns.Codec = Codec

local Limits = Const.Limits

-- The client's compression is optional (section 2). A compressed code is only
-- produced when the result shrinks and decompresses back to the same payload.
local function Api()
  local api = C_EncodingUtil
  if type(api) == "table" and type(api.CompressString) == "function"
    and type(api.DecompressString) == "function" then
    return api
  end
  return nil
end

local function TryCompress(payload)
  local api = Api()
  if not api then return nil end
  local ok, packed = pcall(api.CompressString, payload)
  if not ok or type(packed) ~= "string" or #packed >= #payload then return nil end
  local restored, back = pcall(api.DecompressString, packed)
  if not restored or back ~= payload then return nil end
  return packed
end

local function Integer(value)
  return string.format("%d", math.floor(value))
end

-- list = { id =, name =, author =, exported =, records = array of
-- { name =, verdict =, labels = set, created =, comment = } }.
-- Returns the code and the number of records it holds (a record without any
-- label is skipped, since a list entry needs at least one).
function Codec.Encode(list)
  local lines = {
    Wire.Line("H", "1", list.id, list.name, list.author, list.exported and Integer(list.exported) or ""),
  }
  local count = 0
  for _, record in ipairs(list.records) do
    local mask = Const.LabelsToMask(record.labels)
    if mask > 0 then
      count = count + 1
      lines[#lines + 1] = Wire.Line("R", record.name, record.verdict or "", Integer(mask),
        record.created and Integer(record.created) or "", record.comment or "")
    end
  end
  local payload = table.concat(lines, "\n")
  local mode, body = "R", payload
  local packed = TryCompress(payload)
  if packed then mode, body = "C", packed end
  return Const.CODE_PREFIX .. mode .. ":" .. Wire.Base64Encode(body) .. ":" .. Wire.Checksum(payload), count
end

-- --- Decoding ----------------------------------------------------------------

local function Clean(text)
  return (text:gsub("%c", " "))
end

local function WholeNumber(text)
  local number = tonumber(text)
  if number and number == math.floor(number) then return number end
  return nil
end

-- Parses the header line. Returns the list skeleton or nil.
local function ParseHeader(line)
  local fields = Wire.Split(line)
  if #fields ~= 6 or fields[1] ~= "H" or fields[2] ~= "1" then return nil end
  local id = fields[3]
  if #id < 1 or #id > 32 or id:find("[^0-9a-f]") then return nil end
  local name, author = Clean(Wire.Unescape(fields[4])), Clean(Wire.Unescape(fields[5]))
  if name == "" or author == "" then return nil end
  if Identity.CharCount(name) > Limits.listName or Identity.CharCount(author) > Limits.author then
    return nil
  end
  local exported
  if fields[6] ~= "" then
    exported = tonumber(fields[6])
    if not exported then return nil end
  end
  return { id = id, name = name, author = author, exported = exported, records = {}, count = 0 }
end

-- Parses one record line. Returns the stored entry or nil.
local function ParseRecord(line)
  local fields = Wire.Split(line)
  if #fields ~= 6 or fields[1] ~= "R" then return nil end
  local rawName = Wire.Unescape(fields[2])
  if rawName:find("[%c|]") then return nil end
  local name = Identity.Normalize(rawName)
  if not name or Identity.CharCount(name) > Limits.name then return nil end
  local mask = WholeNumber(fields[4])
  if not mask or mask < 1 or mask > Const.LabelMaskAll then return nil end
  local created
  if fields[5] ~= "" then
    created = tonumber(fields[5])
    if not created or created < 0 then return nil end
  end
  local comment = Clean(Wire.Unescape(fields[6]))
  if Identity.CharCount(comment) > Limits.comment then return nil end
  local hint = fields[3]
  if hint ~= "ignore" and hint ~= "warn" then hint = nil end
  return { name = name, labels = Const.MaskToLabels(mask), comment = comment,
    created = created, verdictHint = hint }
end

-- Decodes pasted text. Returns the list { id, name, author, exported,
-- records = { [target key] = entry }, count } or nil, a locale key naming the
-- problem and, for a bad record, its line number.
function Codec.Decode(text)
  if type(text) ~= "string" then return nil, "ERR_CODE_EMPTY" end
  if #text > Limits.codeBytes then return nil, "ERR_CODE_TOO_BIG" end
  text = text:gsub("%s+", "")
  if text == "" then return nil, "ERR_CODE_EMPTY" end

  local mode, body, checksum = text:match("^BK1([CR]):([A-Za-z0-9+/=]*):(%x%x%x%x%x%x%x%x)$")
  if not mode then
    local version = text:match("^BK(%d+)")
    if version and version ~= "1" then return nil, "ERR_CODE_VERSION" end
    return nil, "ERR_CODE_FORMAT"
  end

  local payload = Wire.Base64Decode(body)
  if not payload then return nil, "ERR_CODE_BASE64" end
  if mode == "C" then
    local api = Api()
    if not api then return nil, "ERR_CODE_NOCOMPRESS" end
    local ok, restored = pcall(api.DecompressString, payload)
    if not ok or type(restored) ~= "string" then return nil, "ERR_CODE_CORRUPT" end
    payload = restored
  end
  if #payload > Limits.payloadBytes then return nil, "ERR_CODE_TOO_BIG" end
  if Wire.Checksum(payload) ~= checksum:lower() then return nil, "ERR_CODE_CHECKSUM" end

  local lines = {}
  for line in (payload .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
  local list = ParseHeader(lines[1])
  if not list then return nil, "ERR_CODE_HEADER" end
  if #lines - 1 > Limits.recordsPerList then return nil, "ERR_CODE_TOO_MANY" end
  for index = 2, #lines do
    if lines[index] ~= "" then
      local entry = ParseRecord(lines[index])
      if not entry then return nil, "ERR_CODE_RECORD", index end
      local key = string.lower(entry.name)
      if not list.records[key] then list.count = list.count + 1 end
      list.records[key] = entry
    end
  end
  return list
end

-- --- Exporting the player's own list -------------------------------------------

-- The name the own list is exported under: the configured one, otherwise one
-- built from the player's first name.
function Codec.ListName()
  local name = ns.Settings.Get("export.name")
  if type(name) == "string" and name ~= "" then return name end
  local me = Identity.Self()
  return string.format(ns.Output.Text("EXPORT_DEFAULT_NAME"), me:match("^(%S+)") or me)
end

-- Builds the code for the own list from the export settings. Returns the code
-- and the number of records in it (0 when nothing qualifies).
function Codec.ExportOwn()
  local Settings, Records = ns.Settings, ns.Records
  local wanted = Settings.Get("export.labels") or {}
  local withComments = Settings.Get("export.comments") ~= false

  local records = {}
  for _, record in ipairs(Records.All()) do
    local kept = {}
    for id, on in pairs(record.labels or {}) do
      if on and wanted[id] then kept[id] = true end
    end
    if next(kept) then
      records[#records + 1] = { name = record.name, verdict = record.verdict, labels = kept,
        created = record.created, comment = withComments and record.comment or "" }
    end
  end

  return Codec.Encode({ id = Settings.Get("export.id"), name = Codec.ListName(),
    author = Identity.Self(), exported = time(), records = records })
end
