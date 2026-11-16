-- Blackbook: small widget helpers shared by every window (section 9). Each
-- helper returns nil when the client lacks the template it needs, so the
-- caller can disable just that feature (section 2 fallback policy).
local _, ns = ...

local Theme = ns.Theme

local Widgets = {}
ns.Widgets = Widgets

-- CreateFrame that never raises: nil when the template does not exist.
function Widgets.Create(kind, template, parent, name)
  if type(CreateFrame) ~= "function" then return nil end
  local ok, frame = pcall(CreateFrame, kind, name, parent, template)
  if ok and frame then return frame end
  return nil
end

-- A frame name that is free: the base name the first time, then base2, base3...
-- A window that is rebuilt (for a language change) must not reuse a global name.
local nameCount = {}
function Widgets.FrameName(base)
  nameCount[base] = (nameCount[base] or 0) + 1
  if nameCount[base] == 1 then return base end
  return base .. nameCount[base]
end

-- Text. fontObject is a Blizzard font name; it is mapped to the matching font of
-- the addon's own look (Theme.Font). Plain "GameFontNormal" text is a heading.
function Widgets.Label(parent, text, fontObject)
  local label = parent:CreateFontString(nil, "ARTWORK", Theme.Font(fontObject or "GameFontNormal"))
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

-- A window in the addon's own style: a dark panel with a thin border, a title bar
-- with a gold line on top and a close button. Movable by its title and clamped to
-- the screen. Returns the frame, which has :SetTitle(text), or nil.
function Widgets.Window(name, width, height, title)
  local frame = Widgets.Create("Frame", nil, UIParent, name)
  if not frame then return nil end
  frame.role = "window"
  frame:SetSize(width, height)
  frame:SetPoint("CENTER")
  frame:SetClampedToScreen(true)
  frame:SetFrameStrata("DIALOG") -- above other addons' HUD frames
  frame:SetToplevel(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

  local color = Theme.color
  Theme.Fill(frame, color.window)
  local bar = frame:CreateTexture(nil, "BORDER")
  bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
  bar:SetHeight(28)
  bar:SetColorTexture(Theme.Unpack(color.titlebar))
  local line = frame:CreateTexture(nil, "ARTWORK")
  line:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
  line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
  line:SetHeight(2)
  line:SetColorTexture(Theme.Unpack(color.accent))
  Theme.Border(frame, color.border)

  frame.titleText = frame:CreateFontString(nil, "OVERLAY", Theme.Font("GameFontNormal"))
  frame.titleText:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -8)
  frame.titleText:SetText(title or "")
  frame.SetTitle = function(self, text) self.titleText:SetText(text or "") end

  local close = Widgets.Button(frame, "\195\151", 28, function() frame:Hide() end, "ghost")
  if close then
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    close:SetHeight(28)
    frame.CloseButton = close
  end
  return frame
end

-- Checkbox with a text label: a small dark box that fills with the accent colour
-- when ticked. The label is clickable too. onClick(check) runs after it toggles.
function Widgets.Checkbox(parent, text, onClick)
  local check = Widgets.Create("CheckButton", nil, parent)
  if not check then return nil end
  check.role = "checkbox"
  check:SetSize(20, 20)

  local color = Theme.color
  local outline = check:CreateTexture(nil, "BACKGROUND")
  outline:SetPoint("LEFT", check, "LEFT", 0, 0)
  outline:SetSize(18, 18)
  outline:SetColorTexture(Theme.Unpack(color.border))
  local inner = check:CreateTexture(nil, "BORDER")
  inner:SetPoint("CENTER", outline, "CENTER", 0, 0)
  inner:SetSize(16, 16)
  inner:SetColorTexture(Theme.Unpack(color.field))
  local mark = check:CreateTexture(nil, "ARTWORK")
  mark:SetPoint("CENTER", outline, "CENTER", 0, 0)
  mark:SetSize(10, 10)
  mark:SetColorTexture(Theme.Unpack(color.accent))
  local label = check:CreateFontString(nil, "OVERLAY", Theme.Font("GameFontHighlight"))
  label:SetPoint("LEFT", check, "LEFT", 26, 0)
  check.label = label

  local state = { enabled = true }
  local nativeSetChecked = check.SetChecked
  local function Sync()
    if check:GetChecked() then mark:Show() else mark:Hide() end
  end
  local function Paint()
    local textColor = state.enabled and color.text or color.off
    label:SetTextColor(Theme.Unpack(textColor))
    outline:SetColorTexture(Theme.Unpack(state.enabled and color.border or color.buttonOff))
  end
  check.SetChecked = function(self, value)
    nativeSetChecked(self, value)
    Sync()
  end
  check.SetText = function(self, value)
    self.text = value
    label:SetText(value or "")
    -- Make the label part of the click area.
    local width = type(label.GetStringWidth) == "function" and label:GetStringWidth() or nil
    if type(width) == "number" and type(self.SetHitRectInsets) == "function" then
      self:SetHitRectInsets(0, -(width + 8), 0, 0)
    end
  end
  check.GetText = function(self) return self.text or "" end
  check.SetEnabled = function(self, value)
    state.enabled = value and true or false
    self.enabled = state.enabled
    if state.enabled then self:Enable() else self:Disable() end
    Paint()
  end
  check:SetScript("OnEnter", function()
    if state.enabled then outline:SetColorTexture(Theme.Unpack(color.accent)) end
  end)
  check:SetScript("OnLeave", Paint)
  check:SetScript("OnClick", function(self)
    Sync()
    if onClick then onClick(self) end
  end)
  check:SetText(text)
  Paint()
  Sync()
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

-- Single-line text box: a dark field with a thin border that turns to the
-- accent colour while it has the cursor.
function Widgets.InputBox(parent, width, maxLetters, onChange)
  local box = Widgets.Create("EditBox", nil, parent)
  if not box then return nil end
  box.role = "input"
  box:SetSize(width, 26)
  box:SetAutoFocus(false)
  box:SetMaxLetters(maxLetters)
  box:SetFontObject(Theme.Font("GameFontHighlight"))
  box:SetTextInsets(8, 8, 0, 0)
  Theme.Fill(box, Theme.color.field)
  local border = Theme.Border(box, Theme.color.border)
  box:SetScript("OnEditFocusGained", function() border.SetColor(Theme.color.accent) end)
  box:SetScript("OnEditFocusLost", function() border.SetColor(Theme.color.border) end)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  box:SetScript("OnTextChanged", function()
    if onChange then onChange() end
  end)
  return box
end

-- Multi-line text area on a dark field with a thin border. Returns the container
-- frame; the edit box is container.edit.
function Widgets.TextArea(parent, width, height, maxLetters, onChange)
  local container = Widgets.Create("Frame", nil, parent)
  local edit = Widgets.Create("EditBox", nil, container)
  if not container or not edit then return nil end
  container:SetSize(width, height)
  Theme.Fill(container, Theme.color.field)
  local border = Theme.Border(container, Theme.color.border)
  edit.role = "textedit"
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetMaxLetters(maxLetters)
  edit:SetFontObject(Theme.Font("GameFontHighlight"))
  edit:SetPoint("TOPLEFT", container, "TOPLEFT", 8, -8)
  edit:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -8, 8)
  edit:SetWidth(width - 16)
  edit:SetScript("OnEditFocusGained", function() border.SetColor(Theme.color.accent) end)
  edit:SetScript("OnEditFocusLost", function() border.SetColor(Theme.color.border) end)
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
  Theme.Fill(container, Theme.color.field)
  Theme.Border(container, Theme.color.border)

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

-- Flat button. style: nil (neutral), "primary" (gold, for the one main action of
-- a window), "danger" (red text, for destructive actions) or "ghost" (no
-- background until hovered, for the window's close button).
function Widgets.Button(parent, text, width, onClick, style)
  local button = Widgets.Create("Button", nil, parent)
  if not button then return nil end
  button.role = "button"
  button:SetSize(width, 26)

  local color = Theme.color
  local background = button:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints(button)
  local label = button:CreateFontString(nil, "OVERLAY", Theme.Font("GameFontHighlight"))
  label:SetPoint("CENTER", button, "CENTER", 0, 0)
  label:SetWidth(width - 8)
  label:SetWordWrap(false)
  button.label = label

  local state = { hover = false, down = false, enabled = true }
  local function Paint()
    local fill, textColor
    if not state.enabled then
      fill, textColor = style == "ghost" and { 0, 0, 0, 0 } or color.buttonOff, color.off
    elseif style == "primary" then
      fill = state.down and color.primaryDown or (state.hover and color.primaryHover or color.primary)
      textColor = color.primaryText
    elseif style == "danger" then
      fill = state.hover and color.dangerHover or color.button
      textColor = color.danger
    elseif style == "ghost" then
      fill = state.hover and color.dangerHover or { 0, 0, 0, 0 }
      textColor = state.hover and color.danger or color.muted
    else
      fill = state.down and color.buttonDown or (state.hover and color.buttonHover or color.button)
      textColor = color.text
    end
    background:SetColorTexture(Theme.Unpack(fill))
    label:SetTextColor(Theme.Unpack(textColor))
  end
  button.SetText = function(self, value)
    self.text = value
    label:SetText(value or "")
  end
  button.GetText = function(self) return self.text or "" end
  button.SetEnabled = function(self, value)
    state.enabled = value and true or false
    self.enabled = state.enabled
    if state.enabled then self:Enable() else self:Disable() end
    if not state.enabled then state.hover, state.down = false, false end
    Paint()
  end
  button:SetScript("OnEnter", function() state.hover = true Paint() end)
  button:SetScript("OnLeave", function() state.hover, state.down = false, false Paint() end)
  button:SetScript("OnMouseDown", function() state.down = true Paint() end)
  button:SetScript("OnMouseUp", function() state.down = false Paint() end)
  button:SetScript("OnClick", function(self)
    if state.enabled and onClick then onClick(self) end
  end)
  button:SetText(text)
  Paint()
  return button
end

-- A tab: plain text with an accent line under the active one. :SetActive(on)
-- switches it. Used by the window's tab bar.
function Widgets.TabButton(parent, text, width, onClick)
  local tab = Widgets.Create("Button", nil, parent)
  if not tab then return nil end
  tab.role = "tab"
  tab:SetSize(width, 26)

  local color = Theme.color
  local hoverFill = tab:CreateTexture(nil, "BACKGROUND")
  hoverFill:SetAllPoints(tab)
  hoverFill:SetColorTexture(Theme.Unpack(color.rowHover))
  hoverFill:Hide()
  local underline = tab:CreateTexture(nil, "ARTWORK")
  underline:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 6, 0)
  underline:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -6, 0)
  underline:SetHeight(2)
  underline:SetColorTexture(Theme.Unpack(color.accent))
  underline:Hide()
  local label = tab:CreateFontString(nil, "OVERLAY", Theme.Font("GameFontHighlight"))
  label:SetPoint("CENTER", tab, "CENTER", 0, 1)
  label:SetWidth(width - 8)
  label:SetWordWrap(false)
  tab.label = label

  local state = { active = false }
  local function Paint()
    label:SetTextColor(Theme.Unpack(state.active and color.text or color.muted))
    if state.active then underline:Show() else underline:Hide() end
  end
  tab.SetText = function(self, value)
    self.text = value
    label:SetText(value or "")
  end
  tab.GetText = function(self) return self.text or "" end
  tab.SetActive = function(self, active)
    state.active = active and true or false
    self.active = state.active
    Paint()
  end
  tab:SetScript("OnEnter", function() if not state.active then hoverFill:Show() end end)
  tab:SetScript("OnLeave", function() hoverFill:Hide() end)
  tab:SetScript("OnClick", function(self) if onClick then onClick(self) end end)
  tab:SetText(text)
  Paint()
  return tab
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

-- Single choice from a list: items = { { value =, text = }, ... }. A dropdown
-- with radio entries when the client has dropdown menus, otherwise a grid of
-- checkboxes of which one is ticked. onChange(value) runs after the player picks.
-- Returns choice with .frame, .height, :SetValue(value) and :GetValue().
function Widgets.Choice(parent, items, onChange, options)
  options = options or {}
  local choice = { value = nil }
  local function TextOf(value)
    for _, item in ipairs(items) do
      if item.value == value then return item.text end
    end
    return ""
  end

  local dropdown = Widgets.Create("DropdownButton", "WowStyle1DropdownTemplate", parent)
  if dropdown and type(dropdown.SetupMenu) == "function" and MenuResponse and MenuResponse.Refresh then
    choice.frame = dropdown
    choice.height = 26
    dropdown:SetWidth(options.width or 200)
    dropdown:SetupMenu(function(_, root)
      local create = root.CreateRadio or root.CreateCheckbox
      for _, item in ipairs(items) do
        create(root, item.text,
          function() return choice.value == item.value end,
          function()
            choice:SetValue(item.value)
            if onChange then onChange(item.value) end
          end)
      end
    end)
    function choice:SetValue(value)
      self.value = value
      if type(dropdown.SetDefaultText) == "function" then dropdown:SetDefaultText(TextOf(value)) end
    end
  else
    local grid = Widgets.Create("Frame", nil, parent)
    if not grid then return nil end
    local columns, width = options.columns or 3, options.columnWidth or 150
    local rows = math.ceil(#items / columns)
    grid:SetSize(columns * width, rows * 24)
    local checks = {}
    for index, item in ipairs(items) do
      local check = Widgets.Checkbox(grid, item.text, function()
        choice:SetValue(item.value)
        if onChange then onChange(item.value) end
      end)
      if not check then return nil end
      check:SetPoint("TOPLEFT", grid, "TOPLEFT", ((index - 1) % columns) * width, -math.floor((index - 1) / columns) * 24)
      checks[item.value] = check
    end
    choice.frame = grid
    choice.height = rows * 24
    function choice:SetValue(value)
      self.value = value
      for itemValue, check in pairs(checks) do check:SetChecked(itemValue == value) end
    end
  end

  function choice:GetValue() return self.value end
  return choice
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
