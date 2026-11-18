-- Nullgate's Blacklist: a tiny internal event bus (section 4.3). Pure module: data and
-- UI modules talk through this instead of calling each other.
local _, ns = ...

local Events = {}
ns.Events = Events

local handlers = {}

-- Registers fn for name. Returns fn so callers can keep a handle.
function Events:On(name, fn)
  if type(name) ~= "string" or type(fn) ~= "function" then return nil end
  local list = handlers[name]
  if not list then
    list = {}
    handlers[name] = list
  end
  list[#list + 1] = fn
  return fn
end

-- Calls every handler registered for name with the given arguments. A failing
-- handler is reported and never stops the others or the caller.
function Events:Fire(name, ...)
  local list = handlers[name]
  if not list then return end
  for index = 1, #list do
    local ok, err = pcall(list[index], ...)
    if not ok and type(geterrorhandler) == "function" then
      geterrorhandler()(err)
    end
  end
end
