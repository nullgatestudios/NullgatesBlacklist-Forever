-- Blackbook: extra lines on player tooltips (section 6.6): the verdict with its
-- icon, then the reasons: your own record first, then up to three imported
-- lists and one line per community source. Lines() holds the content and is
-- testable; Register() hooks it in.
--
-- Test mode lets a player see what these tooltips look like without needing real
-- data: while it is on, every other player's tooltip shows sample lines (a
-- different example for different players, and a clear "sample" line at the end).
local _, ns = ...

local Const = ns.Const
local Safe = ns.Safe
local Identity = ns.Identity
local Resolver = ns.Resolver
local Hash = ns.Hash
local Markers = ns.Markers
local Output = ns.Output

local Text, Escape = Output.Text, Output.Escape

local Tooltip = {}
ns.Tooltip = Tooltip

local MAX_LISTS = 3
local GRAY = { 0.8, 0.8, 0.8 }
local GOLD = { 1, 0.82, 0 }

-- The tooltip lines for a verdict and its reasons: { text =, color =, wrap = }.
-- Player-provided text is escaped for the tooltip.
function Tooltip.LinesFor(verdict, reasons)
  local lines = {}
  local function Add(text, color, wrap)
    lines[#lines + 1] = { text = text, color = color, wrap = wrap }
  end

  Add(Const.ADDON_NAME .. ": " .. Markers.Icon(verdict) .. " " .. Text("VERDICT_" .. string.upper(verdict)),
    Markers.Look[verdict].color, false)

  local lists = 0
  for _, reason in ipairs(reasons) do
    local show = true
    if reason.source == "community" then
      -- One line per source, so friends and guild stay visibly apart.
      Add(string.format(Text("TT_COMMUNITY"), Text("SOURCE_" .. string.upper(reason.from)),
        reason.count, Text("TIER_" .. reason.tier)), Markers.Look[reason.verdict].color, true)
    elseif reason.source == "list" then
      lists = lists + 1
      if lists > MAX_LISTS then
        show = false
      else
        Add(string.format(Text("TT_SOURCE"), Escape(reason.list or "?"), Escape(reason.author or "?")),
          Markers.Look.notice.color, true)
      end
    end
    if show then
      local labels = Output.LabelText(reason.labels)
      if labels ~= "" then Add(Escape(labels), GRAY, true) end
      if reason.comment and reason.comment ~= "" then
        Add('"' .. Escape(reason.comment) .. '"', GOLD, true)
      end
    end
  end
  return lines
end

-- The lines to add for a player, or nil when the player has no verdict.
function Tooltip.Lines(name)
  local verdict, reasons = Resolver.Verdict(name)
  if not verdict then return nil end
  return Tooltip.LinesFor(verdict, reasons)
end

-- --- Test mode --------------------------------------------------------------------------

local testMode = false

-- Test mode lasts until the player logs out; it is never saved, so it cannot be
-- forgotten and leave sample data on tooltips for good.
function Tooltip.SetTestMode(on)
  testMode = on and true or false
end

function Tooltip.TestMode()
  return testMode
end

-- The sample situations, built when needed so their texts follow the language:
-- { verdict, reasons }, the same shape the resolver produces.
local function Community(from, verdict, tier, count, labels)
  local perLabel = {}
  for id in pairs(labels) do perLabel[id] = { tier = tier, count = count } end
  return { source = "community", from = from, verdict = verdict, tier = tier, count = count, labels = perLabel }
end

local function Scenarios()
  return {
    { "ignore", { { source = "own", verdict = "ignore", labels = { harassment = true, toxicity = true },
      comment = Text("SAMPLE_COMMENT_IGNORE") } } },
    { "warn", { { source = "own", verdict = "warn", labels = { scam = true },
      comment = Text("SAMPLE_COMMENT_WARN") } } },
    { "warn", { { source = "list", verdict = "warn", labels = { spam = true }, list = Text("SAMPLE_LIST_NAME"),
      author = Text("SAMPLE_AUTHOR"), comment = Text("SAMPLE_COMMENT_LIST") } } },
    { "notice", { Community("guild", "notice", 2, 7, { scam = true }) } },
    { "warn", { Community("guild", "warn", 3, 12, { ninja_loot = true, scam = true }),
      Community("friends", "notice", 1, 3, { scam = true }) } },
    { "warn", { Community("global", "warn", 3, 24, { spam = true }) } },
  }
end

Tooltip.SampleCount = 6

-- The sample tooltip number `index` (1 to SampleCount): the lines of that
-- situation and a last line saying that this is sample data.
function Tooltip.SampleLinesAt(index)
  local scenario = Scenarios()[index]
  local lines = Tooltip.LinesFor(scenario[1], scenario[2])
  lines[#lines + 1] = { text = Text("TT_TEST_BANNER"), color = GRAY, wrap = true }
  return lines
end

-- The sample for a player: the same player always gets the same example, and
-- different players get different ones, so hovering around shows them all.
function Tooltip.SampleLines(name)
  -- The high bits of the hash: the low ones barely differ for similar names.
  local number = math.floor(Hash.Fnv32(string.lower(name), 2166136261) / 65536) % Tooltip.SampleCount
  return Tooltip.SampleLinesAt(number + 1)
end

local function AddToTooltip(tooltip)
  if not GameTooltip or tooltip ~= GameTooltip then return end
  local _, unit = tooltip:GetUnit()
  unit = Safe.Str(unit)
  if not unit or not UnitIsPlayer(unit) then return end
  local name = Identity.FromUnit(unit)
  if not name then return end
  local lines
  if testMode then
    if Identity.Same(name, Identity.Self()) then return end
    lines = Tooltip.SampleLines(name)
  else
    lines = Tooltip.Lines(name)
  end
  if not lines then return end
  for _, line in ipairs(lines) do
    tooltip:AddLine(line.text, line.color[1], line.color[2], line.color[3], line.wrap)
  end
  tooltip:Show()
end

local registered = false

-- Hooks the tooltip. Returns false when the client offers neither hook.
function Tooltip.Register()
  if registered then return true end
  if TooltipDataProcessor and type(TooltipDataProcessor.AddTooltipPostCall) == "function"
    and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, AddToTooltip)
  elseif GameTooltip and type(GameTooltip.HookScript) == "function" then
    GameTooltip:HookScript("OnTooltipSetUnit", AddToTooltip)
  else
    Output.Print(Text("MSG_NO_TOOLTIP"))
    return false
  end
  registered = true
  return true
end
