-- Blackbook: secret-value guards (sections 0.7 and 4.2). Values returned by
-- chat and unit APIs may be secret; they must never be compared,
-- concatenated or used as table keys. Every external string passes through
-- here first.
local _, ns = ...

local Safe = {}
ns.Safe = Safe

-- issecretvalue may be missing on older clients (section 2). Missing means
-- "not secret".
function Safe.IsSecret(value)
  if type(issecretvalue) ~= "function" then return false end
  return issecretvalue(value) and true or false
end

-- Returns the value only when it is a non-secret string, else nil.
function Safe.Str(value)
  if type(value) ~= "string" then return nil end
  if Safe.IsSecret(value) then return nil end
  return value
end
