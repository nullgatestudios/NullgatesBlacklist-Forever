-- Nullgate's Blacklist: the automatic-reply control (section 6.4), shared by the Settings
-- tab and the setup wizard: three choices (off, short, with reasons) and a
-- preview of the sentence that would be sent. The caller positions the widgets
-- through place(widget, indent, height) so each window keeps its own layout.
local _, ns = ...

local Settings = ns.Settings
local Output = ns.Output
local Widgets = ns.Widgets
local Reply = ns.Reply

local Text, Escape = Output.Text, Output.Escape

local ReplyControl = {}
ns.ReplyControl = ReplyControl

-- Two reasons stand in for the real ones in the preview.
local SAMPLE_LABELS = { toxicity = true, spam = true }

-- The preview line for a mode.
function ReplyControl.PreviewText(mode)
  if mode ~= "short" and mode ~= "labels" then return Text("OPT_REPLY_OFF") end
  return string.format(Text("OPT_REPLY_PREVIEW"), Escape(Reply.Text(mode, SAMPLE_LABELS)))
end

-- Builds the control inside parent. Returns { Refresh = fn } or nil when the
-- client lacks the checkbox template.
function ReplyControl.Create(parent, place)
  local preview = Widgets.Label(parent, "", "GameFontHighlightSmall")
  local group
  group = Widgets.RadioGroup(parent, {
    { value = "none", text = Text("OPT_REPLY_NONE") },
    { value = "short", text = Text("OPT_REPLY_SHORT") },
    { value = "labels", text = Text("OPT_REPLY_LABELS") },
  }, function(value)
    Settings.Set("replyMode", value)
    preview:SetText(ReplyControl.PreviewText(value))
  end)
  if not group then return nil end
  preview:SetWidth(600)
  preview:SetJustifyH("LEFT")

  place(group.buttons[1].button, 0, 30)
  group:Chain(110)
  place(preview, 4, 38)

  return {
    Refresh = function()
      local mode = Settings.Get("replyMode") or "none"
      group:SetValue(mode)
      preview:SetText(ReplyControl.PreviewText(mode))
    end,
  }
end
