-- Blackbook: the "My list" tab (section 9): search, verdict and label
-- filters, sortable columns, a scrolling list with row tooltips, delete with
-- Shift-click and an add-player box.
local _, ns = ...

local Const = ns.Const
local Records = ns.Records
local Query = ns.Query
local Output = ns.Output
local Widgets = ns.Widgets
local Editor = ns.Editor

local Text, Escape = Output.Text, Output.Escape

local TabList = {}
ns.TabList = TabList

local ROW_HEIGHT = 22
local COLUMNS = {
  { key = "name", titleKey = "COL_NAME", x = 4, width = 126 },
  { key = "verdict", titleKey = "COL_VERDICT", x = 134, width = 58 },
  { key = "labels", titleKey = "COL_LABELS", x = 196, width = 146 },
  { key = "comment", titleKey = "COL_COMMENT", x = 346, width = 192 },
  { key = "date", titleKey = "COL_DATE", x = 542, width = 78 },
}
local VERDICT_COLOR = { ignore = { 1, 0.35, 0.35 }, warn = { 1, 0.7, 0.2 } }

-- The label names of a record as shown in the list, in label order.
function TabList.LabelText(record)
  return Output.LabelText(record.labels)
end

local function FormatDate(timestamp)
  local format = date or (os and os.date)
  if not format or not timestamp then return "" end
  return format("%Y-%m-%d", timestamp)
end

local function ShowTooltip(row)
  local record = row.record
  if not record or not GameTooltip then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:AddLine(Escape(record.name), 1, 1, 1)
  GameTooltip:AddLine(Text("VERDICT_" .. string.upper(record.verdict)) .. ": " ..
    Escape(TabList.LabelText(record)), 0.8, 0.8, 0.8, true)
  if record.comment and record.comment ~= "" then
    GameTooltip:AddLine(Escape(record.comment), 1, 0.82, 0, true)
  end
  GameTooltip:AddLine(Text("LIST_HINT"), 0.5, 0.8, 1)
  GameTooltip:Show()
end

local function SetupRow(row, record)
  if not row.built then
    row.built = true
    row.cells = {}
    row:RegisterForClicks("LeftButtonUp")
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(row)
    highlight:SetColorTexture(1, 1, 1, 0.1)
    for _, column in ipairs(COLUMNS) do
      local cell = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      cell:SetPoint("LEFT", row, "LEFT", column.x, 0)
      cell:SetWidth(column.width)
      cell:SetJustifyH("LEFT")
      cell:SetWordWrap(false)
      row.cells[column.key] = cell
    end
    row:SetScript("OnClick", function(self)
      if not self.record then return end
      if IsShiftKeyDown and IsShiftKeyDown() then
        Editor.Remove(self.record.name)
      else
        Editor.Open(self.record.name)
      end
    end)
    row:SetScript("OnEnter", ShowTooltip)
    row:SetScript("OnLeave", function()
      if GameTooltip then GameTooltip:Hide() end
    end)
  end
  row.record = record
  row.cells.name:SetText(Escape(record.name))
  row.cells.verdict:SetText(Text("VERDICT_" .. string.upper(record.verdict)))
  local color = VERDICT_COLOR[record.verdict] or { 1, 1, 1 }
  row.cells.verdict:SetTextColor(color[1], color[2], color[3])
  row.cells.labels:SetText(Escape(TabList.LabelText(record)))
  row.cells.comment:SetText(Escape(record.comment or ""))
  row.cells.date:SetText(FormatDate(record.updated or record.created))
end

local function LabelSummary(selection)
  local count = 0
  for _ in pairs(selection) do count = count + 1 end
  if count == 0 then return Text("FILTER_ALL_LABELS") end
  return string.format(Text("FILTER_LABELS_COUNT"), count)
end

local function Build(content)
  local state = { sortKey = "name", descending = false, verdict = "all" }
  local function Refresh() if state.refresh then state.refresh() end end

  state.search = Widgets.InputBox(content, 170, 60, Refresh)
  state.verdictGroup = Widgets.RadioGroup(content, {
    { value = "all", text = Text("FILTER_ALL") },
    { value = "ignore", text = Text("VERDICT_IGNORE") },
    { value = "warn", text = Text("VERDICT_WARN") },
  }, function(value)
    state.verdict = value
    Refresh()
  end)
  local items = {}
  for _, entry in ipairs(Const.Labels) do
    items[#items + 1] = { id = entry.id, text = Text(Const.LabelLocaleKey(entry.id)) }
  end
  state.labels = Widgets.MultiSelect(content, items, Refresh, { summary = LabelSummary, width = 210 })
  state.addBox = Widgets.InputBox(content, 150, Const.Limits.name)
  state.addButton = Widgets.Button(content, Text("LIST_ADD"), 90, function()
    local name = state.addBox:GetText()
    if name and name ~= "" then
      Editor.Open(name, "ignore")
      state.addBox:SetText("")
    end
  end)
  state.list = Widgets.List(content, ROW_HEIGHT, SetupRow)
  if not (state.search and state.verdictGroup and state.labels and state.addBox
    and state.addButton and state.list) then
    return nil
  end

  state.verdictGroup:SetValue("all")
  state.labels:Set({})

  local searchLabel = Widgets.Label(content, Text("LIST_SEARCH"))
  searchLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -6)
  state.search:SetPoint("TOPLEFT", content, "TOPLEFT", 66, -2)
  state.verdictGroup.buttons[1].button:SetPoint("TOPLEFT", content, "TOPLEFT", 270, 0)
  state.verdictGroup:Chain(62)

  state.labels.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -34)
  local addLabel = Widgets.Label(content, Text("LIST_ADD_NAME"))
  addLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 270, -40)
  state.addBox:SetPoint("TOPLEFT", content, "TOPLEFT", 376, -36)
  state.addButton:SetPoint("TOPLEFT", content, "TOPLEFT", 536, -36)

  state.headers = {}
  for _, column in ipairs(COLUMNS) do
    local header = Widgets.Button(content, Text(column.titleKey), column.width, function()
      if state.sortKey == column.key then
        state.descending = not state.descending
      else
        state.sortKey, state.descending = column.key, false
      end
      Refresh()
    end)
    if not header then return nil end
    header:SetPoint("TOPLEFT", content, "TOPLEFT", column.x - 2, -72)
    state.headers[column.key] = header
  end

  state.list.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -98)
  state.list.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 26)
  state.count = Widgets.Label(content, "", "GameFontHighlightSmall")
  state.count:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 4, 4)

  function state.refresh()
    local all = Records.All()
    local shown = Query.Run(all, {
      search = state.search:GetText(),
      verdict = state.verdict ~= "all" and state.verdict or nil,
      labels = state.labels:Get(),
      sortKey = state.sortKey,
      descending = state.descending,
      labelText = TabList.LabelText,
    })
    for _, column in ipairs(COLUMNS) do
      local title = Text(column.titleKey)
      if column.key == state.sortKey then
        title = title .. (state.descending and " v" or " ^")
      end
      state.headers[column.key]:SetText(title)
    end
    state.list:SetData(shown)
    state.count:SetText(string.format(Text("LIST_COUNT"), #shown, #all))
  end

  return { Refresh = state.refresh, state = state }
end

ns.Manager.RegisterTab("list", "TAB_LIST", Build)
