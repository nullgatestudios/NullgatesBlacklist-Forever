-- Blackbook: the "Imported" tab (section 9): every entry of every imported
-- list with the verdict that applies to it. Clicking a row opens the editor
-- prefilled, to adopt the player into the own list.
local _, ns = ...

local Query = ns.Query
local Subscriptions = ns.Subscriptions
local Output = ns.Output
local Widgets = ns.Widgets
local Editor = ns.Editor

local Text, Escape = Output.Text, Output.Escape

local TabImported = {}
ns.TabImported = TabImported

local ROW_HEIGHT = 22
local COLUMNS = {
  { key = "name", titleKey = "COL_NAME", x = 4, width = 126 },
  { key = "verdict", titleKey = "COL_VERDICT", x = 134, width = 58 },
  { key = "labels", titleKey = "COL_LABELS", x = 196, width = 150 },
  { key = "comment", titleKey = "COL_COMMENT", x = 350, width = 170 },
  { key = "list", titleKey = "COL_LIST", x = 524, width = 96 },
}
local VERDICT_COLOR = { ignore = { 1, 0.35, 0.35 }, warn = { 1, 0.7, 0.2 }, notice = { 0.4, 0.73, 1 } }

local function LabelText(entry)
  return Output.LabelText(entry.labels)
end

local function ShowTooltip(row)
  local entry = row.entry
  if not entry or not GameTooltip then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:AddLine(Escape(entry.name), 1, 1, 1)
  GameTooltip:AddLine(Text("VERDICT_" .. string.upper(entry.verdict)) .. ": " ..
    Escape(LabelText(entry)), 0.8, 0.8, 0.8, true)
  if entry.comment and entry.comment ~= "" then
    GameTooltip:AddLine(Escape(entry.comment), 1, 0.82, 0, true)
  end
  GameTooltip:AddLine(Escape(entry.list), 0.6, 0.6, 0.6)
  GameTooltip:AddLine(Text(entry.own and "IMPORTED_OWN" or "IMPORTED_HINT"), 0.5, 0.8, 1, true)
  GameTooltip:Show()
end

local function SetupRow(row, entry)
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
      local current = self.entry
      if not current then return end
      -- An own record is opened as it is; otherwise the entry fills a new one.
      Editor.Open(current.name, current.verdict == "ignore" and "ignore" or "warn",
        { labels = current.labels, comment = current.comment })
    end)
    row:SetScript("OnEnter", ShowTooltip)
    row:SetScript("OnLeave", function()
      if GameTooltip then GameTooltip:Hide() end
    end)
  end
  row.entry = entry
  row.cells.name:SetText(Escape(entry.name))
  row.cells.verdict:SetText(Text("VERDICT_" .. string.upper(entry.verdict)))
  local color = VERDICT_COLOR[entry.verdict] or { 1, 1, 1 }
  row.cells.verdict:SetTextColor(color[1], color[2], color[3])
  row.cells.labels:SetText(Escape(LabelText(entry)))
  row.cells.comment:SetText(Escape(entry.comment or ""))
  row.cells.list:SetText(Escape(entry.list))
end

local function Build(content)
  local state = { sortKey = "name", descending = false, verdict = "all" }
  local function Refresh() if state.refresh then state.refresh() end end

  state.search = Widgets.InputBox(content, 170, 60, Refresh)
  state.verdictGroup = Widgets.RadioGroup(content, {
    { value = "all", text = Text("FILTER_ALL") },
    { value = "ignore", text = Text("VERDICT_IGNORE") },
    { value = "warn", text = Text("VERDICT_WARN") },
    { value = "notice", text = Text("VERDICT_NOTICE") },
  }, function(value)
    state.verdict = value
    Refresh()
  end)
  state.list = Widgets.List(content, ROW_HEIGHT, SetupRow)
  if not (state.search and state.verdictGroup and state.list) then return nil end
  state.verdictGroup:SetValue("all")

  local searchLabel = Widgets.Label(content, Text("LIST_SEARCH"))
  searchLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -6)
  state.search:SetPoint("TOPLEFT", content, "TOPLEFT", 66, -2)
  state.verdictGroup.buttons[1].button:SetPoint("TOPLEFT", content, "TOPLEFT", 260, 0)
  state.verdictGroup:Chain(70)

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
    header:SetPoint("TOPLEFT", content, "TOPLEFT", column.x - 2, -36)
    state.headers[column.key] = header
  end

  state.list.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -62)
  state.list.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 26)
  state.count = Widgets.Label(content, "", "GameFontHighlightSmall")
  state.count:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 4, 4)

  function state.refresh()
    local all = Subscriptions.Entries()
    local shown = Query.Run(all, {
      search = state.search:GetText(),
      verdict = state.verdict ~= "all" and state.verdict or nil,
      sortKey = state.sortKey,
      descending = state.descending,
      labelText = LabelText,
    })
    -- Entries have no "updated" time, so the list column sorts by list name.
    if state.sortKey == "list" then
      table.sort(shown, function(a, b)
        local listA, listB = string.lower(a.list), string.lower(b.list)
        if listA ~= listB then
          if state.descending then return listA > listB end
          return listA < listB
        end
        return string.lower(a.name) < string.lower(b.name)
      end)
    end
    for _, column in ipairs(COLUMNS) do
      local title = Text(column.titleKey)
      if column.key == state.sortKey then
        title = title .. (state.descending and " v" or " ^")
      end
      state.headers[column.key]:SetText(title)
    end
    state.list:SetData(shown)
    state.count:SetText(string.format(Text("IMPORTED_COUNT"), #shown, #all))
  end

  return { Refresh = state.refresh, state = state }
end

ns.Manager.RegisterTab("imported", "TAB_IMPORTED", Build)
