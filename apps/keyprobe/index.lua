-- Key Probe for XTOS Licorice mini apps (API 2.0, 480 x 800 portrait, 1 bpp).
--
-- Paints the API version, the firmware, every on_input event with all its fields (newest first), and
-- boxes that show which drawing calls work here. It assumes no key names.
--
-- Leaving: Back, whose release is left to the host. Or press any other button 8 times in a row (more than
-- 250 ms from press to press, where there is a clock), which calls ctx:quit(). Should the app still be
-- there after that, or show an error, it claims no more events.

local g                                              -- the canvas, from on_draw

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
  local ok, v = pcall(function() return ctx.clock:millis() end)
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

  local key, st = field(ev, 'key'), field(ev, 'phase') or field(ev, 'state')
  count_press(tostring(field(ev, 'type')) .. '/' .. tostring(key or field(ev, 'gesture')), st, now)
  if streak >= LEAVE_AFTER then
    streak, let_go = 0, true
    pcall(function() ctx:quit() end)
  end
  ctx:invalidate()
  if key == 'back' and (not st or RELEASED[st]) then return false end
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

local WHITE = { color = 0 }
local BOX_W, BOX_H, BOX_STEP = 52, 48, 58

local function black(x, y)
  for i = 0, BOX_H - 1 do g:line(x, y + i, x + BOX_W - 1, y + i) end
end

-- One drawing call per box, A to H from the left.
local BOXES = {
  function(x, y) g:rect(x, y, BOX_W, BOX_H, { fill = true }) end,                              -- A: filled rect
  function(x, y) g:rect(x, y, BOX_W, BOX_H, { fill = true }); g:text(x + 6, y + 10, 'abc', WHITE) end,   -- B: white text on it
  function(x, y) black(x, y); g:text(x + 6, y + 10, 'abc', WHITE) end,                         -- C: white text on lines
  function(x, y)                                                                               -- D: white lines
    black(x, y)
    for i = 0, 5 do g:line(x + 4 + i, y + 4, x + 40 + i, y + 43, WHITE) end
  end,
  function(x, y)                                                                               -- E: white circles
    black(x, y)
    for i = 0, 4 do g:circle(x + 26, y + 24, 18 - i, WHITE) end
  end,
  function(x, y) g:round_rect(x, y, BOX_W, BOX_H, 12) end,                                     -- F: round_rect
  function(x, y) black(x, y); g:rect(x + 8, y + 8, 36, 32, { fill = true, color = 0 }) end,    -- G: white rect
  function(x, y) g:text(x, y + 8, 'Ab', { font = ctx.fonts.large }) end,                       -- H: large font
}

-- A call that fails shows as "err" in its box.
local function draw_boxes(y)
  for i, draw in ipairs(BOXES) do
    local x = LEFT + (i - 1) * BOX_STEP
    g:text(x, y, string.char(64 + i))
    if not pcall(draw, x, y + 26) then g:text(x + 4, y + 36, 'err') end
  end
end

-- The named field of ctx.device, or '?'.
local function device(name)
  local ok, v = pcall(function() return ctx.device[name] end)
  return ok and v ~= nil and tostring(v) or '?'
end

local function draw_impl()
  g:clear(0)
  local w, h = g:size()
  local api = ctx.api
  local ok, ver = pcall(function() return tostring(api.major) .. '.' .. tostring(api.minor) end)
  local caps = type(ctx.input) == 'table' and ctx.input.caps
  g:text(LEFT, 8, 'KEY PROBE  api ' .. (ok and ver or tostring(api)) .. '  ' .. tostring(w) .. 'x' .. tostring(h))
  g:text(LEFT, 34, 'fw ' .. device('firmware') .. '  ' .. device('model'))
  wrapped(LEFT, 60, ('caps ' .. (type(caps) == 'table' and fields(caps, 0) or tostring(caps))):sub(1, 2 * WIDE))
  draw_boxes(138)
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
  g = canvas
  if ERR then draw_error(); return end
  local ok, err = pcall(draw_impl)
  if not ok then ERR = 'on_draw: ' .. tostring(err); pcall(draw_error) end
end

function on_input(...)
  local ok, res = pcall(input_impl, ...)
  if ok then return res and not ERR end                -- the error screen claims nothing
  ERR = 'on_input: ' .. tostring(res)
  pcall(function() ctx:invalidate() end)
  return false                                         -- leave the host a way out of the error screen
end
