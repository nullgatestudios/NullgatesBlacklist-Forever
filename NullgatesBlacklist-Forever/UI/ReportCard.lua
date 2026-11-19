-- Nullgate's Blacklist: the report card, opened from a player's right-click menu.
-- It shows everything known about one player: your own record, imported lists and
-- what each community source holds. Friends and guild reports name the characters
-- who sent them; global reports only ever give a count. Lines() holds the content
-- and is testable; Open() shows it in a window.
local _, ns = ...

local Const = ns.Const
local Identity = ns.Identity
local Records = ns.Records
local Resolver = ns.Resolver
local Rules = ns.Rules
local Hash = ns.Hash
local Output = ns.Output
local Widgets = ns.Widgets

local Text, Escape, Print = Output.Text, Output.Escape, Output.Print

local ReportCard = {}
ns.ReportCard = ReportCard

local GOLD = "ffd100"
local WHITE = "ffffff"
local GRAY = "b3b3b3"
local SOURCE_ORDER = { friends = 1, guild = 2, global = 3 }

local function When(day, today)
  local ago = today - day
  if ago <= 0 then return Text("CARD_TODAY") end
  return string.format(Text("CARD_DAYS_AGO"), ago)
end

local function LabelCounts(labels)
  local parts = {}
  for _, entry in ipairs(Const.Labels) do
    local count = labels[entry.id]
    if count then parts[#parts + 1] = string.format("%s (%d)", Text(Const.LabelLocaleKey(entry.id)), count) end
  end
  return table.concat(parts, ", ")
end

-- The card's lines for a player: { text =, color = hex }. Player-provided text is escaped.
function ReportCard.Lines(name)
  local lines = {}
  local function Add(text, color) lines[#lines + 1] = { text = text, color = color or WHITE } end
  local today = Hash.Day(Hash.ServerTime())

  -- Your own record.
  Add(Text("CARD_OWN"), GOLD)
  local record = Records.Get(name)
  if record then
    Add(Text("VERDICT_" .. string.upper(record.verdict)))
    local labels = Output.LabelText(record.labels)
    if labels ~= "" then Add(Escape(labels), GRAY) end
    if record.comment and record.comment ~= "" then Add('"' .. Escape(record.comment) .. '"', GRAY) end
  else
    Add(Text("CARD_OWN_NONE"), GRAY)
  end

  -- Imported lists.
  local lists = {}
  for _, reason in ipairs(Resolver.Sources(name)) do
    if reason.source == "list" then lists[#lists + 1] = reason end
  end
  if #lists > 0 then
    Add(" ")
    Add(Text("CARD_LISTS"), GOLD)
    for _, reason in ipairs(lists) do
      Add(string.format(Text("TT_SOURCE"), Escape(reason.list or "?"), Escape(reason.author or "?")))
      local labels = Output.LabelText(reason.labels)
      if labels ~= "" then Add(Escape(labels), GRAY) end
    end
  end

  -- Community reports, one block per source.
  Add(" ")
  Add(Text("CARD_COMMUNITY"), GOLD)
  local card = Rules.Card(name)
  if not card.receiving then
    Add(Text("CARD_OFF"), GRAY)
    return lines
  end
  if card.hidden then Add(Text("CARD_HIDDEN"), GRAY) end
  if #card.sources == 0 then
    Add(Text("CARD_NONE"), GRAY)
    return lines
  end
  table.sort(card.sources, function(a, b) return SOURCE_ORDER[a.source] < SOURCE_ORDER[b.source] end)
  for _, entry in ipairs(card.sources) do
    local tier = entry.tier > 0 and Text("TIER_" .. entry.tier) or Text("CARD_BELOW_TIER")
    Add(string.format(Text("TT_COMMUNITY"), Text("SOURCE_" .. string.upper(entry.source)), entry.count, tier))
    Add(LabelCounts(entry.labels), GRAY)
    if entry.reporters then
      for _, reporter in ipairs(entry.reporters) do
        local who = reporter.name and Escape(Identity.Normalize(reporter.name) or reporter.name) or Text("CARD_UNKNOWN")
        Add(string.format("  %s: %s (%s)", who, Escape(Output.LabelText(reporter.labels)), When(reporter.day, today)), GRAY)
      end
    else
      Add(Text("CARD_ANONYMOUS"), GRAY)
    end
  end
  return lines
end

local ui

local function Build()
  local frame = Widgets.Window(Widgets.FrameName("NullgateBlacklistReportCard"), 420, 380, "")
  if not frame then return nil end
  local scroll = Widgets.Create("ScrollFrame", "UIPanelScrollFrameTemplate", frame)
  local content = Widgets.Create("Frame", nil, scroll or frame)
  if not content then
    frame:Hide()
    return nil
  end
  local text = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  text:SetJustifyH("LEFT")
  text:SetJustifyV("TOP")
  text:SetWidth(360)
  text:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  content:SetSize(360, 10)
  if scroll then
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -32)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 14)
    scroll:SetScrollChild(content)
  else
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -32)
  end
  return { frame = frame, content = content, text = text, scroll = scroll }
end

-- Opens the card for a player. Returns false (with a message) when it can't.
function ReportCard.Open(name)
  local normalized = Identity.Normalize(name)
  if not normalized then
    Print(Text("ERR_NAME"))
    return false
  end
  if not ui then ui = Build() end
  if not ui then
    Print(Text("MSG_NO_UI"))
    return false
  end
  local parts = {}
  for _, line in ipairs(ReportCard.Lines(normalized)) do
    parts[#parts + 1] = "|cff" .. line.color .. line.text .. "|r"
  end
  ui.frame:SetTitle(string.format(Text("CARD_TITLE"), Escape(normalized)))
  ui.text:SetText(table.concat(parts, "\n"))
  local height = ui.text:GetStringHeight()
  ui.content:SetHeight(math.max(10, (type(height) == "number" and height or 0) + 4))
  if ui.scroll and ui.scroll.SetVerticalScroll then ui.scroll:SetVerticalScroll(0) end
  ui.frame:Show()
  return true
end
