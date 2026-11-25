-- Tic-tac-toe for two players, for XTOS Licorice mini apps (Lua API 2.0, portrait, 1 bpp).
-- Written for the button-only Xteink X4 Classic; touch and pointer events are ignored.
--
-- P1 is X and P2 is O. The first player alternates every game; each launch starts at game 1 with
-- P1. One cursor (the focus) moves over the empty cells, then Restart once a move was made; after a game
-- it is in the "New game?" box, where Yes starts the next game and No leaves the app.
--
-- Host facts: every ctx function is a method, and the canvas comes with on_draw only. The host reads the
-- answer to a Back release: true keeps the app open, false closes it, without a question (seen on an X4
-- Classic with XTOS Licorice 20261124). g:text takes the TOP of its ~24 px line box. { color = 0 } draws
-- white. A frame keeps its first 1024 drawing commands and drops the rest. Solid shapes are made of nested
-- outlines and lines, which API 0.8 needed and 2.0 draws the same.

local g                                              -- the canvas, from on_draw

-- Every key name the app knows, with what it does. Confirmed on the X4 Classic: left, right and ok
-- (front; system menus label left / right Up and Down) and prev, next (the side buttons).
local KEYMAP = {
  left  = 'prev',
  right = 'next',
  prev  = 'up',                                      -- the side buttons jump a row
  next  = 'down',
  ok    = 'select',
  back  = 'back',                                    -- see back_impl
  up    = 'up',                                      -- X4 Pro side buttons
  down  = 'down',
}
-- Values of ev.state (ev.phase on API 2.x). The X4 Classic sends down and up; whatever is in neither
-- list (a repeat, a hold) is not a press.
local PRESSED = { down = true, press = true, pressed = true }
local RELEASED = { up = true, release = true, released = true }
local DEBOUNCE_MS = 250

------------------------------------------------------------------ game logic (pure, no g / ctx)

local RESTART, YES, NO = 10, 11, 12                  -- focus ids; 1..9 are the cells, row by row
local LINES = { { 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 }, { 1, 4, 7 }, { 2, 5, 8 }, { 3, 6, 9 }, { 1, 5, 9 }, { 3, 5, 7 } }
local NAME = { X = 'P1', O = 'P2' }
local OTHER = { X = 'O', O = 'X' }

-- A game: board[1..9] is 'X', 'O' or false; state is 'PLAYING' or 'GAME_OVER'; winner is 'X', 'O' or
-- nil; line holds the three winning cells; confirm is nil or { action = 'restart' | 'exit',
-- choice = 'cancel' | 'yes' }; wins counts the games won since the launch and is handed from game to game.
local function new_game(number, starter, wins)
  local m = { number = number, starter = starter, turn = starter, moves = 0, state = 'PLAYING', focus = 1, board = {},
              wins = wins or { X = 0, O = 0 } }
  for i = 1, 9 do m.board[i] = false end
  return m
end

local function find_win(board)
  for _, l in ipairs(LINES) do
    local v = board[l[1]]
    if v and board[l[2]] == v and board[l[3]] == v then return v, l end
  end
end

-- Everything focusable now, in order.
local function focus_ring(m)
  if m.state == 'GAME_OVER' then return { YES, NO } end
  local ring = {}
  for i = 1, 9 do if not m.board[i] then ring[#ring + 1] = i end end
  if m.moves > 0 then ring[#ring + 1] = RESTART end
  return ring
end

-- The focus id `step` (+1 / -1) places along the ring, wrapping.
local function ring_step(m, step)
  local ring = focus_ring(m)
  for i, id in ipairs(ring) do
    if id == m.focus then return ring[(i - 1 + step) % #ring + 1] end
  end
  return ring[1]
end

-- The empty cell of a row (0..2) nearest to a column (the left one on a tie), or nil.
local function nearest_in_row(m, row, col)
  local best, best_d
  for c = 0, 2 do
    local d = math.abs(c - col)
    if not m.board[row * 3 + c + 1] and (not best or d < best_d) then best, best_d = row * 3 + c + 1, d end
  end
  return best
end

-- The focus id after the up (dir -1) or down (dir 1) key: rows without an empty cell are passed over.
local function row_step(m, dir)
  if m.state ~= 'PLAYING' then return m.focus end
  local row, col = (m.focus - 1) // 3, (m.focus - 1) % 3
  if m.focus == RESTART then row, col = 3, 2 end      -- at the bottom right
  row = row + dir
  while row >= 0 and row <= 2 do
    local cell = nearest_in_row(m, row, col)
    if cell then return cell end
    row = row + dir
  end
  if dir > 0 and m.focus <= 9 and m.moves > 0 then return RESTART end
  return m.focus
end

-- The next empty cell after `cell`, wrapping; only called while there is one.
local function next_empty(m, cell)
  for k = 0, 8 do
    local i = (cell + k) % 9 + 1
    if not m.board[i] then return i end
  end
end

-- Puts the player's mark into an empty cell. Returns false when that is not allowed.
local function place(m, cell)
  if m.state ~= 'PLAYING' or m.board[cell] ~= false then return false end
  m.board[cell] = m.turn
  m.moves = m.moves + 1
  m.winner, m.line = find_win(m.board)
  if m.winner then m.wins[m.winner] = m.wins[m.winner] + 1 end
  if m.winner or m.moves == 9 then
    m.state = 'GAME_OVER'
    m.focus = YES
  else
    m.turn = OTHER[m.turn]
    m.focus = next_empty(m, cell)
  end
  return true
end

-- Restart or exit at once. Returns the game to go on with, and the effect.
local function run(m, action)
  if action == 'exit' then return m, 'quit' end
  return new_game(m.number + 1, OTHER[m.starter], m.wins), 'draw'
end

-- Restart or exit, asking first in the middle of a game.
local function request(m, action)
  if m.state == 'PLAYING' and m.moves > 0 then
    m.confirm = { action = action, choice = 'cancel' }
    return m, 'draw'
  end
  return run(m, action)
end

local function press_confirm(m, key)
  local c = m.confirm
  if key == 'prev' or key == 'next' then
    c.choice = c.choice == 'cancel' and 'yes' or 'cancel'
    return m, 'draw'
  end
  if key == 'back' or (key == 'select' and c.choice == 'cancel') then
    m.confirm = nil
    return m, 'draw'
  end
  if key == 'select' then
    m.confirm = nil
    return run(m, c.action)
  end
  return m, nil
end

-- One button press (a KEYMAP value). Returns the game to go on with and the effect: 'draw',
-- 'quit', or nil when nothing changed.
local function press(m, key)
  if m.confirm then return press_confirm(m, key) end
  if key == 'back' then return request(m, 'exit') end
  if key == 'select' then
    if m.focus == RESTART then return request(m, 'restart') end
    if m.focus == YES then return run(m, 'restart') end
    if m.focus == NO then return run(m, 'exit') end
    return m, place(m, m.focus) and 'draw' or nil
  end
  local old = m.focus
  if key == 'next' then m.focus = ring_step(m, 1)
  elseif key == 'prev' then m.focus = ring_step(m, -1)
  elseif key == 'up' then m.focus = row_step(m, -1)
  elseif key == 'down' then m.focus = row_step(m, 1) end
  return m, m.focus ~= old and 'draw' or nil
end

local function headline(m)
  if m.state == 'PLAYING' then return NAME[m.turn] .. "'s turn (" .. m.turn .. ')' end
  return m.winner and NAME[m.winner] .. ' wins!' or 'Draw'
end

local function tally(m)
  return 'P1 ' .. m.wins.X .. ' - ' .. m.wins.O .. ' P2'
end

-- What input remembers between events; reset_input starts it afresh.
local held, sees_up, last_key, last_ms
local function reset_input()
  held, sees_up, last_key, last_ms = {}, false, nil, 0
end

-- Whether a key event is a new press. A button that is still down is repeating, which only counts as
-- known where releases are sent: on API 2.x, or once one was seen. A host that sends none (one down per
-- press) goes on working. Where a release gets lost, the next press of that button is lost with it.
local function is_press(ev)
  local st = ev.phase or ev.state
  if not st then return true end
  if RELEASED[st] then held[ev.key], sees_up = nil, true; return false end
  if not PRESSED[st] then return false end
  local repeating = held[ev.key] and (sees_up or ev.phase ~= nil)
  held[ev.key] = true
  return not repeating
end

-- The same key again within DEBOUNCE_MS of its last accepted press is dropped.
local function accept(key, now)
  if key == last_key and now - last_ms >= 0 and now - last_ms < DEBOUNCE_MS then return false end
  last_key, last_ms = key, now
  return true
end

------------------------------------------------------------------ painting

local WHITE = { color = 0 }
local HALF_LINE = 12                                 -- half the system font's ~24 px line box
local BUTTON_RADIUS, BOX_RADIUS = 12, 16

-- A solid black box: nested outlines take half the commands of stacked lines. The host draws no
-- outline 1 or 2 px wide, so lines finish the middle.
local function fill(x, y, w, h)
  while w >= 3 and h >= 3 do
    g:rect(x, y, w, h)
    x, y, w, h = x + 1, y + 1, w - 2, h - 2
  end
  if w <= h then
    for i = 0, w - 1 do g:line(x + i, y, x + i, y + h - 1) end
  else
    for i = 0, h - 1 do g:line(x, y + i, x + w - 1, y + i) end
  end
end

local function frame(b, thick)
  for i = 0, thick - 1 do g:rect(b.x + i, b.y + i, b.w - 2 * i, b.h - 2 * i) end
end

-- How far row i (from 0) of a quarter circle of radius r is set in.
local function inset(r, i)
  local d = r - i - 0.5
  return r - math.floor(math.sqrt(r * r - d * d) + 0.5)
end

-- A solid black box with rounded corners.
local function round_fill(b, r)
  r = math.min(r, b.h // 3)
  fill(b.x, b.y + r, b.w, b.h - 2 * r)
  for i = 0, r - 1 do
    local x1, x2 = b.x + inset(r, i), b.x + b.w - 1 - inset(r, i)
    g:line(x1, b.y + i, x2, b.y + i)
    g:line(x1, b.y + b.h - 1 - i, x2, b.y + b.h - 1 - i)
  end
end

-- A frame with rounded corners: straight sides, and the rows of the corners left and right.
local function round_frame(b, thick, r)
  r = math.min(r, b.h // 3)
  local x2, y2 = b.x + b.w - 1, b.y + b.h - 1
  for i = 0, thick - 1 do
    g:line(b.x + i, b.y + r, b.x + i, y2 - r)
    g:line(x2 - i, b.y + r, x2 - i, y2 - r)
  end
  for i = 0, r - 1 do
    local a = inset(r, i)
    for _, y in ipairs({ b.y + i, y2 - i }) do
      if i < thick then
        g:line(b.x + a, y, x2 - a, y)
      else
        local e = thick + inset(r - thick, i - thick) - 1
        g:line(b.x + a, y, b.x + e, y)
        g:line(x2 - e, y, x2 - a, y)
      end
    end
  end
end

-- 5 x 7 letters for the result banner (the host has one text size).
local BANNER_FONT = {
  ['P'] = '####. #...# #...# ####. #.... #.... #....', ['1'] = '..#.. .##.. ..#.. ..#.. ..#.. ..#.. .###.',
  ['2'] = '.###. #...# ....# ..##. .#... #.... #####', [' '] = '..... ..... ..... ..... ..... ..... .....',
  ['w'] = '..... ..... #...# #...# #.#.# #.#.# .#.#.', ['i'] = '..#.. ..... .##.. ..#.. ..#.. ..#.. .###.',
  ['n'] = '..... ..... #.##. ##..# #...# #...# #...#', ['s'] = '..... ..... .#### #.... .###. ....# ####.',
  ['!'] = '..#.. ..#.. ..#.. ..#.. ..#.. ..... ..#..', ['D'] = '####. #...# #...# #...# #...# #...# ####.',
  ['r'] = '..... ..... #.##. ##..# #.... #.... #....', ['a'] = '..... ..... .###. ....# .#### #...# .####',
}

-- The turn line's letters, 2.5 times the host's one text size: Lexend (SIL Open Font License), 60 px.
-- { advance, 'v' or 'h', runs }: each run is three characters, position, start and end, all plus
-- GLYPH_BASE, for a column (v) or a row (h) of pixels.
local GLYPH_BASE = 35
local TURN_FONT = {
  [' '] = { 17, 'v', "" },
  ["'"] = { 12, 'v', "%/2&$3'$3($3)$1*$-+$*,$'-$$" },
  ['('] = { 22, 'v', "%<@&6F'3I(1K)/M*-O+,:+BP,+6,FQ-*3-IS.(1.KT/(//MT0'.0NU1&,1PV2%+2QW3$*3RX4$)4SX5%(5TW6&(6TV7''7UU" },
  [')'] = { 22, 'v', "$''$UU%&(%TV&%(&TW'$)'SX($*(RX)%+)QW*&,*PV+'.+NU,(/,MT-(1-KS.*3.IR/+6/FQ0,;0AP1-O2/M31K43I56F6<@" },
  ['1'] = { 30, 'v', "()*))-)HM*(.*HM+(-+HM,'-,HM-',-HM.&,.HM/%+/HM0%M1$M2$M3#M4#M5#M6$M7HM8HM9HM:HM;HM<HM" },
  ['2'] = { 33, 'h', "#26$/9%-;&+<'*=()>)(>*(/*7?+'.+9?,'-,9?-&,-:@.&,.:@/(+/:@0)+0:@1:?29?39?48?57>67>76=85<94<:3;;3:<29=19>08?/7@.6A-5B,4C+3D+2E*1F)0G(0H'AI'AJ'AK'AL(AM(A" },
  ['O'] = { 47, 'v', "&3>'0A(.C),E*+F+*G,)H-(2-?I.'0.AJ/&./CK0&-0DK1%,1EL2%+2FL3%+3FM4$*4GM5$*5GM6$)6HM7$)7HM8#)8HN9#)9HN:#):HN;#);HN<#)<HN=$)=HM>$)>HM?$*?GM@$*@GMA%+AFLB%+BFLC%,CELD&-DDKE&/EBKF'0FAJG(2G?IH)HI*GJ+FK,EL.CM0AN4=" },
  ['P'] = { 38, 'v', ")$M*$M+$M,$M-$M.$M/$*/7=0$)08=1$)18=2$)28=3$)38=4$)48=5$)58=6$)68=7$)78=8$)88=9$)98=:$):8=;$*;7=<$*<7==$+=6<>%,>5<?%/?2<@&;A':B'9C)8D*7E,5" },
  ['X'] = { 41, 'v', "%$$%LM&$&&KM'$''JM($((HM)$*)GM*$+*EM+$,+DM,$.,BL-%/-AK.&1.@J/(2/>H0)30=G1+51;E2,62:D3-B4/A50?62>73=83?92@:0B;.C<-7<:E=+5=<F>*4>=G?(3??I@'1@@JA%0AALB$.BCMC$-CDMD$+DEME$*EGMF$(FHMG$'GJMH$%HKMI$$ILM" },
  ['n'] = { 36, 'v', "'/M(.M).M*.M+.M,.M-/M.27/150041042/33/34.35.36.37.38.39.3:.4;.6</M=/M>0M?1M@2MA4MB8M" },
  ['r'] = { 24, 'v', "'/M(.M).M*.M+.M,.M-/M.38/260151052/43/44.45.46.47.48.49.2" },
  ['s'] = { 29, 'h', ".-5/+80)91(;2'<3'.34<4',46;5&,58:6&+6997&,8&,9&-:'/;'3<(6=)8>*9?,:@/;A3<B5<C7<D7<E7<F(*F7<G'+G7<H&-H6<I&;J':K(9L)8M+6N/3" },
  ['t'] = { 23, 'v', "%.4&.4'.4(.4).4*.4+'M,&M-&M.&M/&M0&M1.42.43.44.45.46.47.48/3" },
  ['u'] = { 36, 'v', "'/D(.G).I*.J+.K,.L-/M.EM/GM0HN1HN2IN3IN4IM5IM6IM7IM8HL9HK:GK;FJ<CI=.M>.M?.M@.MA.MB.M" },
}
local TURN_MIDDLE = 22                               -- from the top of the letters to the middle of a capital

-- Calls box(col, row, w, h) for a few boxes that together cover the cells of a grid where on(col,
-- row) holds. Boxes may overlap.
local function cover(cols, rows, on, box)
  local done = {}
  local function all(c, r, w, h)
    for y = r, r + h - 1 do
      for x = c, c + w - 1 do if x >= cols or y >= rows or not on(x, y) then return false end end
    end
    return true
  end
  for r = 0, rows - 1 do
    for c = 0, cols - 1 do
      if on(c, r) and not done[r * cols + c] then
        local w, h = 1, 1                             -- as wide as it goes, then down
        while all(c + w, r, 1, 1) do w = w + 1 end
        while all(c, r + h, w, 1) do h = h + 1 end
        local w2, h2 = 1, 1                           -- as tall as it goes, then across
        while all(c, r + h2, 1, 1) do h2 = h2 + 1 end
        while all(c + w2, r, 1, h2) do w2 = w2 + 1 end
        if w2 * h2 > w * h then w, h = w2, h2 end
        for y = r, r + h - 1 do for x = c, c + w - 1 do done[y * cols + x] = true end end
        box(c, r, w, h)
      end
    end
  end
end

-- Big white text centred in a black box: the black around the letters is what gets painted.
local function big_text_inverted(b, s, scale)
  local cols = #s * 6 - 1
  local left, top = b.x + (b.w - cols * scale) // 2, b.y + (b.h - 7 * scale) // 2
  local right, bottom = left + cols * scale, top + 7 * scale
  fill(b.x, b.y, b.w, top - b.y)
  fill(b.x, bottom, b.w, b.y + b.h - bottom)
  fill(b.x, top, left - b.x, bottom - top)
  fill(right, top, b.x + b.w - right, bottom - top)
  local function unlit(c, r)
    local i = c // 6 + 1
    return BANNER_FONT[s:sub(i, i)]:sub(r * 6 + c % 6 + 1, r * 6 + c % 6 + 1) ~= '#'
  end
  cover(cols, 7, unlit, function(c, r, w, h) fill(left + c * scale, top + r * scale, w * scale, h * scale) end)
end

-- An X: two thick diagonals, steeper than 45 degrees so that lines side by side leave no gaps.
local function draw_x(cx, cy, half, opt)
  local t = half // 7
  for d = -t, t do
    g:line(cx - half + t + d, cy - half, cx + half - t + d, cy + half, opt)
    g:line(cx + half - t + d, cy - half, cx - half + t + d, cy + half, opt)
  end
end

-- An O: two rings. Each circle is drawn twice, 1 px apart, to close the pinholes between radii.
local function draw_o(cx, cy, half, opt)
  local stroke = math.max(2, half // 10)
  for ring = 0, 1 do
    for i = 0, stroke - 1 do
      local r = half - ring * 2 * stroke - i
      g:circle(cx, cy, r, opt)
      g:circle(cx + 1, cy, r, opt)
    end
  end
end

------------------------------------------------------------------ drawing

-- The 480 x 800 layout, scaled to the screen and centred across it.
local function layout(w, h)
  local num, den = w, 480
  if w * 800 > h * 480 then num, den = h, 800 end
  local function px(v) return v * num // den end
  local left = (w - px(480)) // 2
  local function box(x, y, bw, bh) return { x = left + px(x), y = px(y), w = px(bw), h = px(bh) } end
  local cell = px(152)
  return {
    w = w, px = px, cell = cell, cx = w // 2,
    header = { x = 0, y = 0, w = w, h = px(110) }, big = math.max(1, px(5)),
    bx = (w - 3 * cell) // 2, by = px(136), line = math.max(2, px(4)), border = math.max(2, px(6)),
    -- the top of two lines of text at the bottom left, whose digits end ~12 px from the bottom
    info_x = left + px(12), game_y = h - px(6) - 28 - 2 * HALF_LINE, tally_y = h - px(6) - 2 * HALF_LINE,
    restart = box(360, 746, 108, 42),
    modal = box(40, 220, 400, 260), cancel = box(62, 370, 170, 80), yes = box(248, 370, 170, 80),
    over = box(12, 616, 456, 88), over_yes = box(214, 632, 116, 56), over_no = box(342, 632, 116, 56),
  }
end

local function screen_size()
  local ok, w, h = pcall(function() return g:size() end)
  if ok and type(w) == 'number' and type(h) == 'number' then return w // 1, h // 1 end
  return ctx.screen.width, ctx.screen.height
end

local function text_w(s)
  local ok, w = pcall(function() return g:measure_text(s) end)
  if ok and type(w) == 'number' and w > 0 then return w end
  return 13 * utf8.len(s)
end

-- Text in the system font centred on (cx, cy); g:text takes the top of the line.
local function ctext(cx, cy, s, opt)
  g:text(math.max(0, math.floor(cx - text_w(s) / 2)), cy - HALF_LINE, s, opt)
end

-- The turn line, centred on (cx, cy); in the system font on a screen too narrow for it.
local function turn_text(cx, cy, s)
  local w = 0
  for c in s:gmatch('.') do w = w + TURN_FONT[c][1] end
  if w > 2 * cx then ctext(cx, cy, s); return end
  local x, y = cx - w // 2, cy - TURN_MIDDLE
  for c in s:gmatch('.') do
    local adv, dir, runs = table.unpack(TURN_FONT[c])
    for i = 1, #runs, 3 do
      local p, a, b = runs:byte(i, i + 2)
      p, a, b = p - GLYPH_BASE, a - GLYPH_BASE, b - GLYPH_BASE
      if dir == 'v' then g:line(x + p, y + a, x + p, y + b) else g:line(x + a, y + p, x + b, y + p) end
    end
    x = x + adv
  end
end

-- A mark in the middle of a cell, about 60% of it; inverted, white on a black cell. Should a call
-- fail on the device, the letter in the system font stands in.
local function draw_mark(x, y, size, mark, inverted)
  if inverted then fill(x, y, size, size) end
  local cx, cy, opt = x + size // 2, y + size // 2, inverted and WHITE or nil
  if not pcall(mark == 'X' and draw_x or draw_o, cx, cy, size * 3 // 10, opt) then ctext(cx, cy, mark, opt) end
end

local function draw_button(b, label, focused)
  if focused then round_fill(b, BUTTON_RADIUS) else round_frame(b, 2, BUTTON_RADIUS) end
  ctext(b.x + b.w // 2, b.y + b.h // 2, label, focused and WHITE or nil)
end

local function draw_board(L, m)
  local c, half = L.cell, L.line // 2
  for i = 1, 2 do
    fill(L.bx + i * c - half, L.by, L.line, 3 * c)
    fill(L.bx, L.by + i * c - half, 3 * c, L.line)
  end
  local gap = half + 2                                -- from a cell's edge to the focus border
  local won = {}
  for _, i in ipairs(m.line or {}) do won[i] = true end
  for i = 1, 9 do
    local x, y = L.bx + (i - 1) % 3 * c, L.by + (i - 1) // 3 * c
    if m.board[i] then draw_mark(x, y, c, m.board[i], won[i])
    elseif m.focus == i then frame({ x = x + gap, y = y + gap, w = c - 2 * gap, h = c - 2 * gap }, L.border) end
  end
end

-- Drawn in place of the board: there is no white box to lay over it.
local function draw_confirm(L, m)
  round_frame(L.modal, 4, BOX_RADIUS)
  ctext(L.cx, L.modal.y + L.px(70), 'Quit this round?')
  draw_button(L.cancel, 'Cancel', m.confirm.choice == 'cancel')
  draw_button(L.yes, 'Yes', m.confirm.choice == 'yes')
end

-- After a game, below the board, so that the winning cells stay in sight.
local function draw_over(L, m)
  local b = L.over
  round_frame(b, 3, BOX_RADIUS)
  local cx, cy = (b.x + L.over_yes.x) // 2, b.y + b.h // 2
  ctext(cx, cy, 'New game?')
  draw_button(L.over_yes, 'Yes', m.focus == YES)
  draw_button(L.over_no, 'No', m.focus == NO)
end

------------------------------------------------------------------ input and lifecycle

local M                                              -- the game, see new_game

local function draw_impl()
  local L = layout(screen_size())
  g:clear(0)                                         -- own the whole frame, white
  local over, h = M.state == 'GAME_OVER', L.header
  if over then big_text_inverted(h, headline(M), L.big)
  else turn_text(L.cx, h.y + h.h // 2, headline(M)) end
  if M.confirm then draw_confirm(L, M) else draw_board(L, M) end
  if over then draw_over(L, M)
  elseif M.moves > 0 then draw_button(L.restart, 'Restart', M.focus == RESTART and not M.confirm) end
  g:text(L.info_x, L.game_y, 'Game ' .. M.number)
  g:text(L.info_x, L.tally_y, tally(M))
end

-- Only the fast refresh is asked for. Full ones are left to the reader, which does one by itself every so
-- many refreshes (a setting).
local function apply(effect)
  if not effect then return end
  if effect == 'quit' then ctx:quit(); return end
  ctx:invalidate()
end

local function event_ms(ev)
  if type(ev.time_ms) == 'number' then return ev.time_ms end
  return ctx.clock:millis()
end

-- Back acts when let go: it closes the question, asks it in the middle of a game, or leaves the app.
local function back_impl(ev)
  local st = ev.phase or ev.state
  if st and not RELEASED[st] then return true end
  if not accept(ev.key, event_ms(ev)) then return true end
  local effect
  M, effect = press(M, 'back')
  if effect == 'quit' then return false end          -- the host closes the app
  apply(effect)
  return true
end

local function input_impl(ev)
  if type(ev) ~= 'table' or ev.type ~= 'key' then return false end   -- touch and pointer: not ours
  local key = KEYMAP[ev.key]
  if not key then return false end
  if key == 'back' then return back_impl(ev) end
  if not is_press(ev) then return true end
  if not accept(ev.key, event_ms(ev)) then return true end
  local effect
  M, effect = press(M, key)
  apply(effect)
  return true
end

-- Always a fresh first game: ctx.state is not read or written.
local function load_impl()
  M = new_game(1, 'X')
  reset_input()
end

-- The host closes an app on any Lua error and only says "App error, closed". These wrappers catch
-- the error and paint it, so a failure on the device can actually be read.
local ERR = nil

local function draw_error()
  g:clear(0)
  g:text(15, 20, 'Tic-Tac-Toe: Lua error')
  g:line(15, 52, 465, 52)
  local y, s = 70, ERR
  while #s > 0 and y < 740 do
    g:text(15, y, s:sub(1, 36)); s = s:sub(37); y = y + 26
  end
end

function on_load()
  ERR = nil
  local ok, err = pcall(load_impl)
  if not ok then ERR = 'on_load: ' .. tostring(err) end
end

function on_draw(_, canvas)
  g = canvas
  if ERR then draw_error(); return end
  local ok, err = pcall(draw_impl)
  if not ok then ERR = 'on_draw: ' .. tostring(err); pcall(draw_error) end
end

function on_input(_, ev)
  if ERR then return false end                       -- keys go to the host, so the app can be left
  local ok, res = pcall(input_impl, ev)
  if ok then return res end
  ERR = 'on_input: ' .. tostring(res)
  pcall(function() ctx:invalidate() end)
  return true
end

function on_leave()
  -- nothing is kept between runs
end

-- Test hook: never set on the device.
if rawget(_G, '__TEST') then
  __TEST.api = { new_game = new_game, focus_ring = focus_ring, row_step = row_step, place = place, headline = headline,
                 tally = tally, layout = layout, LINES = LINES, TURN_FONT = TURN_FONT, RESTART = RESTART, YES = YES, NO = NO,
                 game = function() return M end, err = function() return ERR end }
end
