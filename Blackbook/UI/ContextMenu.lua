-- Blackbook: entries on player right-click menus (section 9). Build() is the
-- whole decision logic; Register() only hooks it into the client's menus.
local _, ns = ...

local Safe = ns.Safe
local Identity = ns.Identity
local Records = ns.Records
local Resolver = ns.Resolver
local Output = ns.Output
local Editor = ns.Editor

local ContextMenu = {}
ns.ContextMenu = ContextMenu

-- Menu tags of player menus: unit frames, party and raid, friends, chat names,
-- guild and community lists. A tag the client does not use is harmless.
local MENU_TAGS = {
  "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER",
  "MENU_UNIT_FRIEND", "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS",
  "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_COMMUNITIES_GUILD_MEMBER",
  "MENU_UNIT_COMMUNITIES_MEMBER", "MENU_UNIT_CHAT_ROSTER",
}

-- The player a menu was opened on, as a normalized name, or nil when the menu
-- is not about another player (non-player unit, own character, secret values).
function ContextMenu.TargetFromContext(context)
  if type(context) ~= "table" then return nil end
  local name
  if type(context.unit) == "string" then
    if type(UnitIsPlayer) == "function" and not UnitIsPlayer(context.unit) then return nil end
    name = Identity.FromUnit(context.unit)
  else
    name = Identity.Normalize(Safe.Str(context.name))
  end
  if not name or Identity.Same(name, Identity.Self()) then return nil end
  return name
end

-- Adds the Blackbook entries to a menu description.
function ContextMenu.Build(root, context)
  local name = ContextMenu.TargetFromContext(context)
  if not name then return false end

  root:CreateDivider()
  root:CreateTitle(Output.Text("CTX_TITLE"))

  if Records.Get(name) then
    root:CreateButton(Output.Text("CTX_EDIT"), function() Editor.Open(name) end)
    root:CreateButton(Output.Text("CTX_REMOVE"), function() Editor.Remove(name) end)
    return true
  end

  root:CreateButton(Output.Text("CTX_IGNORE"), function() Editor.Open(name, "ignore") end)
  root:CreateButton(Output.Text("CTX_WARN"), function() Editor.Open(name, "warn") end)

  -- A player only an imported list knows can be adopted into the own list.
  for _, reason in ipairs(Resolver.Sources(name)) do
    if reason.source == "list" then
      root:CreateButton(Output.Text("CTX_ADOPT"), function()
        Editor.Open(name, reason.verdict == "ignore" and "ignore" or "warn",
          { labels = reason.labels, comment = reason.comment })
      end)
      break
    end
  end

  -- A player flagged only by community reports can have that flag hidden here.
  -- This stays on this install; nothing is shared.
  for _, reason in ipairs(Resolver.Sources(name)) do
    if reason.source == "community" then
      root:CreateButton(Output.Text("CTX_WRONG"), function()
        ns.Rules.Hide(name)
        Output.Print(string.format(Output.Text("MSG_FLAG_HIDDEN"), Output.Escape(name)))
      end)
      break
    end
  end
  return true
end

local registered = false

-- Hooks Build into the player menus. Returns false when the client has no
-- menu modification API; slash commands keep working.
function ContextMenu.Register()
  if registered then return true end
  if not (Menu and type(Menu.ModifyMenu) == "function") then
    Output.Print(Output.Text("MSG_NO_MENU"))
    return false
  end
  for _, tag in ipairs(MENU_TAGS) do
    pcall(Menu.ModifyMenu, tag, function(_, root, context)
      ContextMenu.Build(root, context)
    end)
  end
  registered = true
  return true
end

ContextMenu.Tags = MENU_TAGS
