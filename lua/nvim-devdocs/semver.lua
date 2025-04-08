M = {}

local function split(s)
  local ret = {}
  for w in string.gmatch(s, "([^.]+)%.?") do
    table.insert(ret, w)
  end
  return ret
end

local function cmp(a, b)
  if a > b then
    return 1
  elseif b > a then
    return -1
  end
  return 0
end

---Compares two semver strings and returns 1 if `a` is higher, -1 if `b` is higher or `0` if equivalent.
---Strings are treated as `-1` for comparison, unless both are strings, in which case
---they are compared lexigraphically.
---@param a string
---@param b string
---@return number
M.compare = function(a, b)
  local sa = split(a)
  local sb = split(b)

  for i = 1, math.min(#sa, #sb) do
    local na = tonumber(sa[i]) or -1
    local nb = tonumber(sb[i]) or -1

    -- two strings, compare them lexigraphically
    if na == -1 and nb == -1 then
      local c = cmp(sa[i], sb[i])
      if c ~= 0 then return c end
    end

    local c = cmp(na, nb)
    if c ~= 0 then return c end
  end

  return cmp(#sa, #sb)
end

---Checks if version `a` is greater than or equivalent to version `b`.
---@param a string
---@param b string
---@return boolean
M.gte = function(a, b) return M.compare(a, b) > -1 end

---Checks if version `a` is greater than version `b`.
---@param a string
---@param b string
---@return boolean
M.gt = function(a, b) return M.compare(a, b) == 1 end

-- local function test(a, b) print(a, " <> ", b, " -> ", M.compare(a, b)) end
--
-- test("10", "10")
-- test("10.beta", "10.alpha")
-- test("10.bla", "10.0")
-- test("10.bla", "10")
-- test("10", "9.1")
-- test("9.1", "10")

return M
