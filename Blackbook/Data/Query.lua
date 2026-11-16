-- Blackbook: filtering and sorting of record arrays for the list window
-- (section 9). Pure module: no frames, no client calls.
local _, ns = ...

local Const = ns.Const

local Query = {}
ns.Query = Query

local function Lower(text)
  return string.lower(text or "")
end

-- The value a column sorts by. Strings are compared case-insensitively.
local function SortValue(record, key, labelText)
  if key == "verdict" then return Const.VerdictRank[record.verdict] or 0 end
  if key == "date" then return record.updated or record.created or 0 end
  if key == "comment" then return Lower(record.comment) end
  if key == "labels" then return Lower(labelText(record)) end
  return Lower(record.name)
end

-- Returns the records that pass the filters, sorted.
-- opts.search      text matched (plain, ignoring case) against name, comment and labels
-- opts.verdict     "ignore", "warn" or nil for both
-- opts.labels      set { [labelId] = true }; a record needs at least one of them
-- opts.sortKey     "name" (default), "verdict", "labels", "comment" or "date"
-- opts.descending  reverse the primary order; ties always sort by name
-- opts.labelText   function(record) -> the label names as displayed
function Query.Run(records, opts)
  opts = opts or {}
  local labelText = opts.labelText or function(_) return "" end
  local needle = Lower(opts.search):gsub("^%s+", ""):gsub("%s+$", "")
  local wanted = opts.labels
  if wanted and next(wanted) == nil then wanted = nil end

  local result = {}
  for _, record in ipairs(records) do
    local keep = true
    if opts.verdict and record.verdict ~= opts.verdict then keep = false end
    if keep and wanted then
      keep = false
      for id in pairs(wanted) do
        if record.labels and record.labels[id] then
          keep = true
          break
        end
      end
    end
    if keep and needle ~= "" then
      local haystack = Lower(record.name) .. "\n" .. Lower(record.comment) .. "\n" .. Lower(labelText(record))
      keep = string.find(haystack, needle, 1, true) ~= nil
    end
    if keep then result[#result + 1] = record end
  end

  local key, descending = opts.sortKey or "name", opts.descending and true or false
  table.sort(result, function(a, b)
    local valueA, valueB = SortValue(a, key, labelText), SortValue(b, key, labelText)
    if valueA ~= valueB then
      if descending then return valueA > valueB end
      return valueA < valueB
    end
    local nameA, nameB = Lower(a.name), Lower(b.name)
    if nameA ~= nameB then return nameA < nameB end
    return a.name < b.name
  end)
  return result
end
