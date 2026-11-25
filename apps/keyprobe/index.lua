-- Key Probe for XTOS Licorice mini apps (default API 0.8, 480 x 800 portrait, 1 bpp).
--
-- Paints every on_input event with all its fields, newest first, and four boxes that show which
-- drawing calls work here. It assumes no key names. Every event is claimed (returns true), so a
-- button that leaves the app anyway is one the host keeps for itself.
--
-- Leaving: press any one button 8 times in a row (more than 250 ms from press to press, where there is
-- a clock); this calls ctx.quit(). Should the app still be there after that, or show an error, it claims
-- no more events, so that the host's own way out works.

local LEFT, LOG_Y, LINE_H, WIDE, LOG_MAX = 12, 272, 24, 36, 24
local LEAVE_AFTER, PRESS_GAP_MS = 8, 250
local PRESSED = { down = true, press = true, pressed = true }
local RELEASED = { up = true, release = true, released = true }

local log, count = {}, 0
local last_id, last_ms, press_ms, streak = nil, 0, nil, 0
local held, sees_up = {}, false                      -- a button still down is repeating, not pressed again
local let_go = false                                 -- events are left to the host
local ERR = nil

-- nil without a clock
local function millis()
  local ok, v = pcall(function() return ctx.sys.millis() end)
  return ok and type(v) == 'number' and v or nil
end

local function show(v)
  if type(v) == 'string' then return '"' .. v .. '"' end
  return tostring(v)
end

-- Every field of a table as "name=value", sorted; a nested table is opened once.
local function fields(t, depth)
  local out = {}
  for k, v in pairs(t) do
    local s = show(v)
    if type(v) == 'table' and depth < 1 then s = '{' .. fields(v, depth + 1) .. '}' end
    out[#out + 1] = tostring(k) .. '=' .. s
  end
  table.sort(out)
  return table.concat(out, ' ')
end

-- An event that is not a plain table cannot be listed, so ask it for the names we know of.
local NAMES = { 'type', 'key', 'phase', 'state', 'gesture', 'code', 'name', 'action', 'repeat', 'x', 'y',
                'time_ms', 'duration_ms' }
local function field(ev, n)
  local ok, v = pcall(function() return ev[n] end)
  if ok then return v end
end

local function describe(ev)
  if type(ev) == 'table' then return fields(ev, 0) end
  local out = { type(ev) .. ':' }
  for _, n in ipairs(NAMES) do
    local v = field(ev, n)
    if v ~= nil then out[#out + 1] = n .. '=' .. show(v) end
  end
  return table.concat(out, ' ')
end

-- Counts the presses of one button in a row. Times are taken from press to press, not from a release.
local function count_press(id, st, now)
  if RELEASED[st or ''] then held[id], sees_up = nil, true; return end
  if st and not PRESSED[st] then return end
  local repeating = held[id] and sees_up
  if st then held[id] = true end
  if repeating then return end
  if id ~= last_id then streak = 1
  elseif not now or not press_ms or now - press_ms > PRESS_GAP_MS then streak = streak + 1
  else return end
  last_id, press_ms = id, now
end

local function input_impl(...)
  local args = table.pack(...)
  local ev = args.n >= 2 and args[2] or args[1]
  count = count + 1
  local now = millis()
  log[#log + 1] = '#' .. count .. ' +' .. (now and now - last_ms or '?') .. 'ms ' .. describe(ev)
  if #log > LOG_MAX then table.remove(log, 1) end
  last_ms = now or last_ms

  local id = tostring(field(ev, 'type')) .. '/' .. tostring(field(ev, 'key') or field(ev, 'gesture'))
  count_press(id, field(ev, 'phase') or field(ev, 'state'), now)
  if streak >= LEAVE_AFTER then
    streak, let_go = 0, true
    pcall(function() ctx.quit() end)
  end
  ctx.invalidate()
  return not let_go
end

------------------------------------------------------------------ drawing

-- Text wrapped at WIDE characters; returns the y after it.
local function wrapped(x, y, s)
  while #s > 0 and y < 790 do
    g:text(x, y, s:sub(1, WIDE))
    s = s:sub(WIDE + 1)
    y = y + LINE_H
  end
  return y
end

-- Runs one drawing test; a call that fails shows as "err" in its box.
local function try(x, y, fn)
  if not pcall(fn) then g:text(x + 4, y + 20, 'err') end
end

local function tests(y)
  for i = 0, 3 do g:text(12 + i * 118, y, string.sub('ABCD', i + 1, i + 1)) end
  y = y + 28
  try(12, y, function()                                -- A: solid from stacked g:line calls
    for i = 0, 59 do g:line(12, y + i, 111, y + i) end
  end)
  try(130, y, function()                               -- B: solid from one zigzag polyline per 30 rows
    for part = 0, 1 do
      local pts = {}
      for i = 0, 29 do
        local a, b = 130, 229
        if i % 2 == 1 then a, b = b, a end
        local yy = y + part * 30 + i
        pts[#pts + 1] = a; pts[#pts + 1] = yy; pts[#pts + 1] = b; pts[#pts + 1] = yy
      end
      g:polyline(pts)
    end
  end)
  try(248, y, function() g:rect(248, y, 100, 60, { fill = true }) end)   -- C: filled rect
  try(366, y, function()                               -- D: white text on black stacked lines
    for i = 0, 59 do g:line(366, y + i, 465, y + i) end
    g:text(376, y + 18, 'white', { color = 0 })
  end)
end

local function draw_impl()
  g:clear(0)
  local w, h = g:size()
  local api, sc = ctx.api, ctx.screen
  local caps = type(ctx.input) == 'table' and ctx.input.caps
  local ver = type(api) == 'table' and tostring(api.major) .. '.' .. tostring(api.minor) or tostring(api)
  local size = type(sc) == 'table' and tostring(sc.width) .. 'x' .. tostring(sc.height) or tostring(sc)
  g:text(LEFT, 8, 'KEY PROBE  api ' .. ver .. '  ' .. tostring(w) .. 'x' .. tostring(h))
  g:text(LEFT, 34, 'screen ' .. size .. '  quit ' .. type(ctx.quit))
  wrapped(LEFT, 60, 'caps ' .. (type(caps) == 'table' and fields(caps, 0) or tostring(caps)))
  tests(138)
  g:text(LEFT, 238, let_go and 'ctx.quit did not leave: use Back'
    or 'Leave: same button x' .. LEAVE_AFTER .. '  (' .. streak .. ')')
  g:line(0, LOG_Y - 4, w, LOG_Y - 4)
  local y = LOG_Y
  for i = #log, 1, -1 do
    if y >= 780 then break end
    y = wrapped(LEFT, y, log[i]) + 4
  end
end

local function draw_error()
  g:clear(0)
  g:text(LEFT, 20, 'Key Probe: Lua error')
  wrapped(LEFT, 60, ERR)
end

function on_load()
  last_ms = millis() or 0
end

function on_draw(_, canvas)
  if canvas then g = canvas end
  if ERR then draw_error(); return end
  local ok, err = pcall(draw_impl)
  if not ok then ERR = 'on_draw: ' .. tostring(err); pcall(draw_error) end
end

function on_input(...)
  local ok, res = pcall(input_impl, ...)
  if ok then return res and not ERR end                -- the error screen claims nothing
  ERR = 'on_input: ' .. tostring(res)
  pcall(ctx.invalidate)
  return false                                         -- leave the host a way out of the error screen
end
