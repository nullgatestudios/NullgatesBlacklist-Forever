-- Nullgate's Blacklist: the mark on the target frame portrait (section 6.6): a diagonal
-- strike for "ignore", a corner icon for "warn" and "notice". The portrait is
-- looked up defensively because the target frame layout varies by client.
local _, ns = ...

local Const = ns.Const
local Events = ns.Events
local Identity = ns.Identity
local Resolver = ns.Resolver
local Markers = ns.Markers

local Portrait = {}
ns.Portrait = Portrait

local overlay

local function FindPortrait()
  if not TargetFrame then return nil end
  local container = TargetFrame.TargetFrameContainer
  if container and container.Portrait then return container.Portrait end
  if TargetFrame.portrait then return TargetFrame.portrait end
  return TargetFramePortrait
end

local function Create()
  local frame = CreateFrame("Frame", "NullgateBlacklistTargetMark", TargetFrame)
  local portrait = FindPortrait()
  if portrait then
    frame:SetAllPoints(portrait)
  else
    frame:SetSize(64, 64)
    frame:SetPoint("TOPRIGHT", TargetFrame, "TOPRIGHT", -40, -10)
  end
  frame:SetFrameLevel(TargetFrame:GetFrameLevel() + 10)

  frame.strike = frame:CreateTexture(nil, "OVERLAY")
  frame.strike:SetColorTexture(0.9, 0.1, 0.1, 0.9)
  frame.strike:SetPoint("CENTER")
  frame.strike:SetRotation(math.rad(45))

  frame.icon = frame:CreateTexture(nil, "OVERLAY")
  frame.icon:SetSize(24, 24)
  frame.icon:SetPoint("CENTER", frame, "TOPRIGHT", -6, -6)

  frame:Hide()
  return frame
end

-- The verdict of the current target, or nil (no target, not a player, no flag).
function Portrait.TargetVerdict()
  if type(UnitExists) ~= "function" or not UnitExists("target") then return nil end
  if type(UnitIsPlayer) ~= "function" or not UnitIsPlayer("target") then return nil end
  local name = Identity.FromUnit("target")
  if not name then return nil end
  return (Resolver.Verdict(name))
end

-- Redraws the mark for the current target. Returns the verdict shown.
function Portrait.Update()
  if not TargetFrame then return nil end
  if not overlay then overlay = Create() end
  local verdict = Portrait.TargetVerdict()
  local look = verdict and Markers.Look[verdict]
  if not look then
    overlay:Hide()
    return nil
  end

  local size = overlay:GetWidth()
  if not size or size < 10 then size = 64 end
  overlay.strike:Hide()
  overlay.icon:Hide()
  if look.strike then
    overlay.strike:SetSize(6, size * 1.3)
    overlay.strike:Show()
  elseif look.icon then
    overlay.icon:SetTexture(look.icon)
    local tint = look.tint or { 1, 1, 1 }
    overlay.icon:SetVertexColor(tint[1], tint[2], tint[3])
    overlay.icon:Show()
  end
  overlay:Show()
  return verdict
end

local registered = false

-- Starts following the target. Returns false when the client has no target
-- frame; the rest of the addon is unaffected.
function Portrait.Register()
  if registered then return true end
  if not TargetFrame or type(CreateFrame) ~= "function" then return false end
  local frame = CreateFrame("Frame")
  frame:RegisterEvent("PLAYER_TARGET_CHANGED")
  frame:SetScript("OnEvent", function() Portrait.Update() end)
  Events:On(Const.Events.RECORDS_CHANGED, Portrait.Update)
  Events:On(Const.Events.SUBSCRIPTIONS_CHANGED, Portrait.Update)
  Events:On(Const.Events.COMMUNITY_CHANGED, Portrait.Update)
  registered = true
  Portrait.Update()
  return true
end
