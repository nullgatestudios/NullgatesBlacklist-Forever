-- Blackbook: the add/edit dialog (section 9). Opened from slash commands, the
-- manager and the context menu. Save stays disabled until Records.Check
-- accepts the fields, so the dialog and the data layer share one set of rules.
local _, ns = ...

local Const = ns.Const
local Identity = ns.Identity
local Records = ns.Records
local Output = ns.Output
local Widgets = ns.Widgets

local Text, Escape, Print = Output.Text, Output.Escape, Output.Print

local Editor = {}
ns.Editor = Editor

local ui -- built on first use

local function VerdictText(verdict)
  return Text("VERDICT_" .. string.upper(tostring(verdict or "")))
end

local function LabelSummary(selection)
  local count = 0
  for _ in pairs(selection) do count = count + 1 end
  if count == 0 then return Text("EDITOR_LABELS_NONE") end
  return string.format(Text("EDITOR_LABELS_COUNT"), count)
end

local function Build()
  local frame = Widgets.Create("Frame", "BasicFrameTemplateWithInset", UIParent, "BlackbookEditor")
  if not frame then return nil end

  local state = {}
  local function Refresh()
    if not state.ready then return end
    local comment = state.area.edit:GetText()
    local err = Records.Check(state.nameBox:GetText(), state.group:GetValue(), state.picker:Get(), comment)
    Widgets.SetEnabled(state.save, err == nil)
    state.hint:SetText(err and Text(err) or "")
    state.counter:SetText(string.format("%d/%d", Identity.CharCount(comment), Const.Limits.comment))
  end

  state.nameBox = Widgets.InputBox(frame, 336, Const.Limits.name, Refresh)
  state.group = Widgets.RadioGroup(frame, {
    { value = "ignore", text = Text("VERDICT_IGNORE") },
    { value = "warn", text = Text("VERDICT_WARN") },
  }, Refresh)
  local items = {}
  for _, entry in ipairs(Const.Labels) do
    items[#items + 1] = { id = entry.id, text = Text(Const.LabelLocaleKey(entry.id)) }
  end
  state.picker = Widgets.MultiSelect(frame, items, Refresh, { summary = LabelSummary, width = 220 })
  state.area = Widgets.TextArea(frame, 336, 80, Const.Limits.comment, Refresh)
  state.save = Widgets.Button(frame, Text("EDITOR_SAVE"), 100, function() Editor.Commit() end)
  state.cancel = Widgets.Button(frame, Text("EDITOR_CANCEL"), 100, function() frame:Hide() end)
  if not (state.nameBox and state.group and state.picker and state.area and state.save and state.cancel) then
    frame:Hide()
    return nil
  end

  state.hint = Widgets.Label(frame, "", "GameFontHighlightSmall")
  state.counter = Widgets.Label(frame, "", "GameFontDisableSmall")

  -- Every widget is placed from the top of the frame by one running offset,
  -- and the frame height is the sum, so the content can never overlap the
  -- buttons (the multi-line comment box would otherwise swallow their clicks).
  local LEFT, ROW_LABEL, FOOTER = 20, 20, 36
  local y = 34
  local function Place(widget, indent, height)
    widget:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT + indent, -y)
    y = y + height
  end

  Place(Widgets.Label(frame, Text("EDITOR_NAME")), 0, ROW_LABEL)
  Place(state.nameBox, 6, 32)

  Place(Widgets.Label(frame, Text("EDITOR_VERDICT")), 0, ROW_LABEL)
  Place(state.group.buttons[1].button, -4, 36)
  state.group:Chain(100)

  Place(Widgets.Label(frame, Text("EDITOR_LABELS")), 0, ROW_LABEL)
  Place(state.picker.frame, 0, state.picker.height + 14)

  Place(Widgets.Label(frame, Text("EDITOR_COMMENT")), 0, ROW_LABEL)
  Place(state.area, 0, 80 + 4)
  state.hint:SetPoint("TOPLEFT", state.area, "BOTTOMLEFT", 0, -4)
  state.counter:SetPoint("TOPRIGHT", state.area, "BOTTOMRIGHT", 0, -4)
  y = y + 24

  state.save:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -6, 14)
  state.cancel:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 6, 14)

  frame:SetSize(376, y + FOOTER)
  frame:SetPoint("CENTER")
  frame:SetClampedToScreen(true)
  frame:SetFrameStrata("DIALOG") -- above other addons' HUD frames; the last shown window is on top
  frame:SetToplevel(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  if UISpecialFrames then tinsert(UISpecialFrames, "BlackbookEditor") end
  frame:Hide()

  state.frame = frame
  state.refresh = Refresh
  state.ready = true
  return state
end

local function SetTitle(frame, title)
  if type(frame.SetTitle) == "function" then
    frame:SetTitle(title)
  elseif frame.TitleContainer and frame.TitleContainer.TitleText then
    frame.TitleContainer.TitleText:SetText(title)
  end
end

-- Opens the dialog for a player. verdict is the preselected verdict for a new
-- record; prefill = { labels =, comment = } fills a new record (used by
-- "Adopt"). An existing record is always loaded as it is stored.
-- Returns true when the dialog opened.
function Editor.Open(name, verdict, prefill)
  local normalized = Identity.Normalize(name)
  if not normalized then
    Print(Text("ERR_NAME"))
    return false
  end
  if Identity.Same(normalized, Identity.Self()) then
    Print(Text("MSG_SELF"))
    return false
  end
  if not ui then ui = Build() end
  if not ui then
    Print(Text("MSG_NO_UI"))
    return false
  end

  local record = Records.Get(normalized)
  ui.original = record and record.name or nil
  ui.nameBox:SetText(record and record.name or normalized)
  if record then
    ui.group:SetValue(record.verdict)
    ui.picker:Set(record.labels)
    ui.area.edit:SetText(record.comment or "")
  else
    ui.group:SetValue(verdict == "warn" and "warn" or "ignore")
    ui.picker:Set(prefill and prefill.labels or {})
    ui.area.edit:SetText(prefill and prefill.comment or "")
  end
  SetTitle(ui.frame, Text(record and "EDITOR_TITLE_EDIT" or "EDITOR_TITLE_NEW"))
  ui.refresh()
  ui.frame:Show()
  return true
end

-- Saves what the dialog shows. Editing the name of an existing record moves it
-- instead of leaving the old entry behind; a name that belongs to a different
-- record is refused.
function Editor.Commit()
  if not ui then return false end
  local name = Identity.Normalize(ui.nameBox:GetText())
  if name then
    local existing = Records.Get(name)
    if existing and not (ui.original and Identity.Same(ui.original, name)) then
      Print(string.format(Text("MSG_NAME_TAKEN"), Escape(existing.name)))
      return false
    end
  end
  local record, err = Records.Save(ui.nameBox:GetText(), ui.group:GetValue(),
    ui.picker:Get(), ui.area.edit:GetText())
  if not record then
    Print(Text(err))
    return false
  end
  if ui.original and not Identity.Same(ui.original, record.name) then
    Records.Remove(ui.original)
  end
  ui.original = record.name
  Print(string.format(Text("MSG_RECORD_SAVED"), Escape(record.name), VerdictText(record.verdict)))
  ui.frame:Hide()
  return true
end

-- Deletes a record and says so. Shared by the slash command and the menu.
function Editor.Remove(name)
  local record = Records.Get(name)
  if not record then
    local display = Identity.Normalize(name) or tostring(name)
    Print(string.format(Text("MSG_RECORD_NOT_FOUND"), Escape(display)))
    return false
  end
  Records.Remove(name)
  Print(string.format(Text("MSG_RECORD_REMOVED"), Escape(record.name)))
  return true
end
