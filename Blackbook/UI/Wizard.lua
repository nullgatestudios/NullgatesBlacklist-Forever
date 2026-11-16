-- Blackbook: the first-run setup wizard (section 9). Four pages: welcome and
-- language, what Ignore does, the automatic reply, and finish with the minimap
-- button. It appears once; closing it in any way counts as done, and /bb setup
-- or the Settings tab opens it again. Sharing is never switched on here; the
-- Community tab owns that.
local _, ns = ...

local Settings = ns.Settings
local Output = ns.Output
local Widgets = ns.Widgets
local ReplyControl = ns.ReplyControl

local Text, Print, Escape = Output.Text, Output.Print, Output.Escape

local Wizard = {}
ns.Wizard = Wizard

local PAGE_COUNT = 4
local WIDTH, HEIGHT = 500, 330

local ui -- built on first use

local function SetTitle(frame, title)
  if type(frame.SetTitle) == "function" then
    frame:SetTitle(title)
  elseif frame.TitleContainer and frame.TitleContainer.TitleText then
    frame.TitleContainer.TitleText:SetText(title)
  end
end

-- A page frame with its title and body text. Returns the frame and a function
-- place(widget, indent, height) that stacks widgets below the text.
local function NewPage(frame, titleKey, bodyKey)
  local page = Widgets.Create("Frame", nil, frame)
  if not page then return nil end
  page:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -40)
  page:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 50)
  local title = Widgets.Label(page, Text(titleKey), "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
  local body = Widgets.Label(page, Text(bodyKey), "GameFontHighlight")
  body:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -30)
  body:SetWidth(WIDTH - 40)
  body:SetJustifyH("LEFT")
  body:SetJustifyV("TOP")
  local y = 110 -- the body text sits in the first 110 pixels
  local function Place(widget, indent, height)
    widget:SetPoint("TOPLEFT", page, "TOPLEFT", indent, -y)
    y = y + height
  end
  page:Hide()
  return page, Place
end

local function Build()
  local name = Widgets.FrameName("BlackbookWizard")
  local frame = Widgets.Create("Frame", "BasicFrameTemplateWithInset", UIParent, name)
  if not frame then return nil end
  frame:SetSize(WIDTH, HEIGHT)
  frame:SetPoint("CENTER")
  frame:SetClampedToScreen(true)
  frame:SetFrameStrata("DIALOG")
  frame:SetToplevel(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  SetTitle(frame, Text("WIZ_TITLE"))

  local state = { pages = {}, refreshers = {}, page = 1 }

  -- Page 1: welcome and language.
  local welcome, welcomePlace = NewPage(frame, "WIZ_WELCOME_TITLE", "WIZ_WELCOME")
  local language = Widgets.Choice(welcome or frame, ns.Locale.Choices(), function(value)
    -- The language changes at once: the wizard is rebuilt in it and reopens here.
    if ns.Locale.Set(value) then
      Print(string.format(Output.Text("MSG_LANG_SET"), Escape(ns.Locale.NameOf(value))))
    end
  end)

  -- Page 2: what Ignore does, with the two switches.
  local ignore, ignorePlace = NewPage(frame, "WIZ_IGNORE_TITLE", "WIZ_IGNORE")
  local hideChat = Widgets.Checkbox(ignore or frame, Text("OPT_HIDE_CHAT"), function(self)
    Settings.Set("hideChat", self:GetChecked() and true or false)
  end)
  local autoDecline = Widgets.Checkbox(ignore or frame, Text("OPT_AUTO_DECLINE"), function(self)
    Settings.Set("autoDecline", self:GetChecked() and true or false)
  end)

  -- Page 3: automatic reply.
  local reply, replyPlace = NewPage(frame, "WIZ_REPLY_TITLE", "WIZ_REPLY")
  local replyControl = reply and ReplyControl.Create(reply, replyPlace)

  -- Page 4: finish.
  local finish, finishPlace = NewPage(frame, "WIZ_FINISH_TITLE", "WIZ_FINISH")
  local minimap = Widgets.Checkbox(finish or frame, Text("OPT_SHOW_MINIMAP"), function(self)
    Settings.Set("showMinimap", self:GetChecked() and true or false)
  end)

  state.back = Widgets.Button(frame, Text("WIZ_BACK"), 100, function() Wizard.Go(state.page - 1) end)
  state.next = Widgets.Button(frame, Text("WIZ_NEXT"), 100, function()
    if state.page >= PAGE_COUNT then frame:Hide() else Wizard.Go(state.page + 1) end
  end)
  if not (welcome and ignore and reply and finish and language and hideChat and autoDecline
    and replyControl and minimap and state.back and state.next) then
    frame:Hide()
    return nil
  end

  welcomePlace(language.frame, 0, language.height + 8)
  ignorePlace(hideChat, 0, 30)
  ignorePlace(autoDecline, 0, 30)
  finishPlace(minimap, 0, 30)
  state.pages = { welcome, ignore, reply, finish }
  state.refreshers = {
    function() language:SetValue(Settings.Get("language") or "auto") end,
    function()
      hideChat:SetChecked(Settings.Get("hideChat") and true or false)
      autoDecline:SetChecked(Settings.Get("autoDecline") and true or false)
    end,
    replyControl.Refresh,
    function() minimap:SetChecked(Settings.Get("showMinimap") and true or false) end,
  }

  state.step = Widgets.Label(frame, "", "GameFontDisableSmall")
  state.step:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 22)
  state.next:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 14)
  state.back:SetPoint("RIGHT", state.next, "LEFT", -8, 0)

  -- Closing the wizard any way at all counts as done: it never nags twice. The
  -- frame is hidden before the handler exists, and the handler only acts once
  -- the wizard has really been shown, so building it cannot finish the setup.
  frame:Hide()
  frame:SetScript("OnHide", function()
    if state.opened then Settings.Set("setupDone", true) end
  end)
  if UISpecialFrames then tinsert(UISpecialFrames, name) end

  state.frame = frame
  return state
end

-- Shows page n (1 to 4).
function Wizard.Go(page)
  if not ui then return end
  page = math.max(1, math.min(PAGE_COUNT, page))
  ui.page = page
  for index, frame in ipairs(ui.pages) do
    if index == page then frame:Show() else frame:Hide() end
  end
  ui.refreshers[page]()
  if page == 1 then ui.back:Hide() else ui.back:Show() end
  ui.next:SetText(Text(page == PAGE_COUNT and "WIZ_DONE" or "WIZ_NEXT"))
  ui.step:SetText(string.format(Text("WIZ_STEP"), page, PAGE_COUNT))
end

-- Opens the wizard at a page (the first by default). Returns true when it opened.
function Wizard.Open(page)
  if not ui then ui = Build() end
  if not ui then
    Print(Text("MSG_NO_UI"))
    return false
  end
  ui.opened = true
  ui.frame:Show()
  Wizard.Go(page or 1)
  return true
end

-- Throws the window away and, if it was open, opens a fresh one on the same page
-- (used when the language changes). Closing it this way does not finish the setup.
function Wizard.Reset()
  local old = ui
  ui = nil
  if not old then return end
  local wasShown, page = old.frame:IsShown(), old.page
  old.opened = false
  old.frame:Hide()
  if wasShown then Wizard.Open(page) end
end
ns.Locale.OnChange(Wizard.Reset)

-- Opens the wizard on the first run only.
function Wizard.MaybeOpen()
  if Settings.Get("setupDone") == false then return Wizard.Open() end
  return false
end
