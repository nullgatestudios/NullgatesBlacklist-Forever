-- Blackbook: extra lines on player tooltips (section 6.6): the verdict with its
-- icon, then the reasons: your own record first, then up to three imported
-- lists. Lines() holds the content and is testable; Register() hooks it in.
local _, ns = ...

local Const = ns.Const
local Safe = ns.Safe
local Identity = ns.Identity
local Resolver = ns.Resolver
local Markers = ns.Markers
local Output = ns.Output

local Text, Escape = Output.Text, Output.Escape

local Tooltip = {}
ns.Tooltip = Tooltip

local MAX_LISTS = 3
local GRAY = { 0.8, 0.8, 0.8 }
local GOLD = { 1, 0.82, 0 }

-- The lines to add for a player: { text =, color =, wrap = }, or nil when the
-- player has no verdict. Player-provided text is escaped for the tooltip.
function Tooltip.Lines(name)
  local verdict, reasons = Resolver.Verdict(name)
  if not verdict then return nil end
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

local function AddToTooltip(tooltip)
  if not GameTooltip or tooltip ~= GameTooltip then return end
  local _, unit = tooltip:GetUnit()
  unit = Safe.Str(unit)
  if not unit or not UnitIsPlayer(unit) then return end
  local name = Identity.FromUnit(unit)
  if not name then return end
  local lines = Tooltip.Lines(name)
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
