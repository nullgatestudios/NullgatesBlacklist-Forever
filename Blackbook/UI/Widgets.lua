-- Blackbook: small widget helpers shared by every window (section 9). Each
-- helper returns nil when the client lacks the template it needs, so the
-- caller can disable just that feature (section 2 fallback policy).
local _, ns = ...

local Widgets = {}
ns.Widgets = Widgets

-- CreateFrame that never raises: nil when the template does not exist.
function Widgets.Create(kind, template, parent, name)
  if type(CreateFrame) ~= "function" then return nil end
  local ok, frame = pcall(CreateFrame, kind, name, parent, template)
  if ok and frame then return frame end
  return nil
end

function Widgets.Label(parent, text, fontObject)
  local label = parent:CreateFontString(nil, "ARTWORK", fontObject or "GameFontNormal")
  label:SetText(text or "")
  return label
end

function Widgets.SetEnabled(frame, enabled)
  if type(frame.SetEnabled) == "function" then
    frame:SetEnabled(enabled and true or false)
  elseif enabled then
    frame:Enable()
  else
    frame:Disable()
  end
end

-- Checkbox with a text label. onClick(check) runs after the box toggles.
function Widgets.Checkbox(parent, text, onClick)
  local check = Widgets.Create("CheckButton", "UICheckButtonTemplate", parent)
  if not check then return nil end
  if check.Text then
    check.Text:SetText(text)
  elseif type(check.SetText) == "function" then
    check:SetText(text)
  else
    local label = check:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("LEFT", check, "RIGHT", 4, 0)
    label:SetText(text)
  end
  check:SetScript("OnClick", function(self)
    if onClick then onClick(self) end
  end)
  return check
end

-- Row of mutually exclusive checkboxes. options = { { value =, text = }, ... }.
-- The caller anchors group.buttons[1]; Chain(gap) lines the rest up beside it.
function Widgets.RadioGroup(parent, options, onChange)
  local group = { buttons = {}, value = nil }
  for index, option in ipairs(options) do
    local button = Widgets.Checkbox(parent, option.text, function()
      group:SetValue(option.value)
      if onChange then onChange(option.value) end
    end)
    if not button then return nil end
    group.buttons[index] = { button = button, value = option.value }
  end
  function group:SetValue(value)
    self.value = value
    for _, entry in ipairs(self.buttons) do
      entry.button:SetChecked(entry.value == value)
    end
  end
  function group:GetValue()
    return self.value
  end
  function group:Chain(gap)
    for index = 2, #self.buttons do
      self.buttons[index].button:SetPoint("LEFT", self.buttons[index - 1].button, "RIGHT", gap, 0)
    end
  end
  return group
end

-- Single-line text box using the standard input template.
function Widgets.InputBox(parent, width, maxLetters, onChange)
  local box = Widgets.Create("EditBox", "InputBoxTemplate", parent)
  if not box then return nil end
  box:SetSize(width, 20)
  box:SetAutoFocus(false)
  box:SetMaxLetters(maxLetters)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  box:SetScript("OnTextChanged", function()
    if onChange then onChange() end
  end)
  return box
end

-- Multi-line text area on a dark background. Returns the container frame; the
-- edit box is container.edit.
function Widgets.TextArea(parent, width, height, maxLetters, onChange)
  local container = Widgets.Create("Frame", nil, parent)
  local edit = Widgets.Create("EditBox", nil, container)
  if not container or not edit then return nil end
  container:SetSize(width, height)
  local background = container:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints(container)
  background:SetColorTexture(0, 0, 0, 0.5)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetMaxLetters(maxLetters)
  if ChatFontNormal then edit:SetFontObject(ChatFontNormal) end
  edit:SetPoint("TOPLEFT", container, "TOPLEFT", 6, -6)
  edit:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -6, 6)
  edit:SetWidth(width - 12)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  edit:SetScript("OnTextChanged", function()
    if onChange then onChange() end
  end)
  container:EnableMouse(true)
  container:SetScript("OnMouseDown", function() edit:SetFocus() end)
  container.edit = edit
  return container
end

-- Box for a long single block of text, such as a list code. The text sits in a
-- scroll frame, so however long it gets it stays inside the box and cannot
-- cover the widgets around it. Without a scroll frame template it falls back to
-- a single-line edit box. Returns the container; the edit box is container.edit.
function Widgets.CodeBox(parent, width, height, maxLetters, onChange)
  local container = Widgets.Create("Frame", nil, parent)
  if not container then return nil end
  container:SetSize(width, height)
  local background = container:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints(container)
  background:SetColorTexture(0, 0, 0, 0.5)

  local scroll = Widgets.Create("ScrollFrame", "UIPanelScrollFrameTemplate", container)
  local edit = Widgets.Create("EditBox", nil, scroll or container)
  if not edit then return nil end
  edit:SetAutoFocus(false)
  edit:SetMaxLetters(maxLetters)
  if ChatFontNormal then edit:SetFontObject(ChatFontNormal) end
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  edit:SetScript("OnTextChanged", function()
    if onChange then onChange() end
  end)
  if scroll then
    scroll:SetPoint("TOPLEFT", container, "TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -28, 6)
    edit:SetMultiLine(true)
    edit:SetSize(width - 40, height - 12)
    scroll:SetScrollChild(edit)
  else
    edit:SetPoint("TOPLEFT", container, "TOPLEFT", 6, -6)
    edit:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -6, 6)
  end
  container:EnableMouse(true)
  container:SetScript("OnMouseDown", function() edit:SetFocus() end)
  container.edit = edit
  return container
end

function Widgets.Button(parent, text, width, onClick)
  local button = Widgets.Create("Button", "UIPanelButtonTemplate", parent)
  if not button then return nil end
  button:SetSize(width, 22)
  button:SetText(text)
  button:SetScript("OnClick", function(self)
    if onClick then onClick(self) end
  end)
  return button
end

-- Multi-select of labelled items. items = { { id =, text = }, ... }.
-- options.summary(selection) returns the caption for the closed dropdown.
-- Uses a dropdown menu when the client has one, otherwise a grid of checkboxes.
-- Returns picker with .frame, .height, :Set(set), :Get() -> set.
function Widgets.MultiSelect(parent, items, onChange, options)
  options = options or {}
  local selection = {}
  local picker = {}

  local function Changed()
    if onChange then onChange() end
  end

  local dropdown = Widgets.Create("DropdownButton", "WowStyle1DropdownTemplate", parent)
  if dropdown and type(dropdown.SetupMenu) == "function" and MenuResponse and MenuResponse.Refresh then
    picker.frame = dropdown
    picker.height = 26
    dropdown:SetWidth(options.width or 200)
    local function UpdateCaption()
      if options.summary and type(dropdown.SetDefaultText) == "function" then
        dropdown:SetDefaultText(options.summary(selection))
      end
    end
    dropdown:SetupMenu(function(_, root)
      for _, item in ipairs(items) do
        root:CreateCheckbox(item.text,
          function() return selection[item.id] == true end,
          function()
            if selection[item.id] then selection[item.id] = nil else selection[item.id] = true end
            UpdateCaption()
            Changed()
            return MenuResponse.Refresh
          end)
      end
    end)
    function picker:Set(set)
      for id in pairs(selection) do selection[id] = nil end
      for id, on in pairs(set or {}) do
        if on then selection[id] = true end
      end
      UpdateCaption()
    end
    UpdateCaption()
  else
    local grid = Widgets.Create("Frame", nil, parent)
    if not grid then return nil end
    local checks = {}
    local rows = math.ceil(#items / 2)
    grid:SetSize(options.width or 340, rows * 24)
    for index, item in ipairs(items) do
      local check = Widgets.Checkbox(grid, item.text, function(self)
        selection[item.id] = self:GetChecked() and true or nil
        Changed()
      end)
      if not check then return nil end
      check:SetPoint("TOPLEFT", grid, "TOPLEFT", ((index - 1) % 2) * 170, -math.floor((index - 1) / 2) * 24)
      checks[item.id] = check
    end
    picker.frame = grid
    picker.height = rows * 24
    function picker:Set(set)
      for id in pairs(selection) do selection[id] = nil end
      for id, on in pairs(set or {}) do
        if on then selection[id] = true end
      end
      for id, check in pairs(checks) do
        check:SetChecked(selection[id] == true)
      end
    end
  end

  function picker:Get()
    local copy = {}
    for id in pairs(selection) do copy[id] = true end
    return copy
  end
  return picker
end

-- Scrolling list built on the client's scroll box. setup(row, data) fills a
-- row and may create its child widgets (rows are recycled, so create them once:
-- check row.built). Returns list with .frame (the container), :SetData(array),
-- or nil when the client lacks the scroll box pieces. SetData keeps the scroll
-- position, so a refresh does not jump back to the top.
function Widgets.List(parent, rowHeight, setup)
  if not (CreateScrollBoxListLinearView and CreateDataProvider and ScrollUtil
    and type(ScrollUtil.InitScrollBoxListWithScrollBar) == "function") then
    return nil
  end
  local container = Widgets.Create("Frame", nil, parent)
  local box = Widgets.Create("Frame", "WowScrollBoxList", container)
  local bar = Widgets.Create("EventFrame", "MinimalScrollBar", container)
  if not (container and box and bar) then return nil end

  box:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
  box:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -18, 0)
  bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, -2)
  bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 2)

  local view = CreateScrollBoxListLinearView()
  view:SetElementExtent(rowHeight)
  view:SetElementInitializer("Button", setup)
  ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)

  local list = { frame = container }
  function list:SetData(array)
    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    box:SetDataProvider(CreateDataProvider(array), retain)
  end
  return list
end
