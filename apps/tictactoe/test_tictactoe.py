"""Offline test of tictactoe/index.lua under Lua 5.4 (lupa).  python -I apps/tictactoe/test_tictactoe.py

Runs everything a second time under Lua 5.5 (the device's) when lupa has it."""
import os, sys
from lupa import lua54
try:
    from lupa import lua55
except ImportError:
    lua55 = None
src = open(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), 'index.lua'), encoding='utf-8').read()

HOST = r'''
W, H = 480, 800
cmds, texts, now, quits, invals = 0, {}, 100000, 0, 0
low, high = 0, 0                                     -- the smallest and largest coordinate drawn
local function seen(v) if v < low then low = v end; if v > high then high = v end end
-- only these calls: rect outlines, not under 3 px, and no fill or polyline
ALLOWED = { clear = true, line = true, rect = true, circle = true, text = true }
canvas = setmetatable({}, {__index = function(_, k)
  return function(self, ...)
    if k == 'size' then return W, H end
    if k == 'measure_text' then local s = ...; return 13 * utf8.len(s), 24 end
    assert(ALLOWED[k], 'not on the device: g:' .. k)
    cmds = cmds + 1
    local a = table.pack(...)
    if k == 'text' then texts[#texts+1] = a[3]; seen(a[1]); seen(a[2]) end
    if k == 'line' then for i = 1, 4 do seen(a[i]) end end
    if k == 'rect' then assert(a.n == 4 and a[3] >= 3 and a[4] >= 3); seen(a[1]); seen(a[2]); seen(a[1] + a[3]); seen(a[2] + a[4]) end
    if k == 'circle' then assert(a[3] > 0); seen(a[1] - a[3]); seen(a[2] + a[3]) end
    for i = 1, a.n do assert(math.type(a[i]) ~= 'float', 'a float in g:' .. k) end
  end end})
ctx = { state = {}, screen = { width = W, height = H },
        clock = { millis = function(self) assert(self == ctx.clock, 'a method'); return now end },
        invalidate = function(self) assert(self == ctx, 'a method'); invals = invals + 1 end,
        quit = function(self) assert(self == ctx, 'a method'); quits = quits + 1 end }
__TEST = {}
'''


class App:
    def __init__(self, lua):
        self.rt = lua.LuaRuntime(unpack_returned_tuples=True)
        self.rt.execute(HOST)
        before = set(self.rt.globals().keys())
        self.rt.execute(src)
        self.new_globals = set(self.rt.globals().keys()) - before
        self.api = self.rt.eval('__TEST.api')
        self.load()

    def load(self):
        self.rt.eval('on_load')(self.rt.eval('ctx'))
        assert self.api.err() is None, self.api.err()

    def event(self, **ev):
        r = self.rt.eval('on_input')(self.rt.eval('ctx'), self.rt.table_from(ev))
        assert self.api.err() is None, self.api.err()
        return r

    # one clean press: the clock is moved on first, so the debounce does not apply
    def key(self, *names):
        for n in names:
            self.rt.execute('now = now + 1000')
            self.event(type='key', key=n, phase='down')
            r = self.event(type='key', key=n, phase='up')
        return r                                       # the answer to the last release

    def draw(self):
        self.rt.execute('cmds = 0; texts = {}; low = 0; high = 0')
        self.rt.eval('on_draw')(self.rt.eval('ctx'), self.rt.eval('canvas'))
        assert self.api.err() is None, self.api.err()
        texts = list(self.rt.eval('texts').values())
        return texts                                   # the turn line and the banner are painted, not text

    def n(self, name): return self.rt.eval(name)
    @property
    def m(self): return self.api.game()
    def board(self): return ''.join(self.m.board[i] or '.' for i in range(1, 10))

    def goto(self, target):
        for _ in range(12):
            if self.m.focus == target: return
            self.key('right')
        raise AssertionError(f'focus {target} not reachable')

    def play(self, cells):
        for c in cells:
            self.goto(c); self.key('ok')


def model(api, cells, starter='X'):
    """A game with the cells played through the rules only (no input)."""
    m = api.new_game(1, starter)
    for c in cells: assert api.place(m, c), c
    return m


def run(lua, name):
    print(f'--- {name}')
    a = App(lua); api = a.api; R, YES, NO = api.RESTART, api.YES, api.NO
    assert a.new_globals == {'on_load', 'on_draw', 'on_input', 'on_leave'}, a.new_globals

    # --- wins: the 8 lines, for X and for O, as the first and as the second player
    lines = [list(l.values()) for l in api.LINES.values()]
    assert sorted(lines) == sorted([[1,2,3],[4,5,6],[7,8,9],[1,4,7],[2,5,8],[3,6,9],[1,5,9],[3,5,7]])
    n = 0
    for line in lines:
        for winner in 'XO':
            for starter in 'XO':
                # the other side plays cells off the line that are not a line themselves
                rest = [c for c in range(1, 10) if c not in line]
                others = next([p, q, r] for p in rest for q in rest for r in rest
                              if len({p, q, r}) == 3 and sorted([p, q, r]) not in lines)
                seq = [c for pair in zip(line, others) for c in pair][:5] if starter == winner \
                    else [c for pair in zip(others, line) for c in pair]
                m = model(api, seq[:-1], starter); assert m.state == 'PLAYING' and m.winner is None
                assert api.place(m, seq[-1])
                assert m.winner == winner and m.state == 'GAME_OVER' and list(m.line.values()) == line and m.focus == YES
                assert api.headline(m) == ('P1' if winner == 'X' else 'P2') + ' wins!'
                n += 1
    assert n == 32
    # a win on the ninth move is a win, not a draw
    m = model(api, [1, 2, 3, 4, 5, 6, 8, 7, 9]); assert m.winner == 'X' and m.moves == 9 and api.headline(m) == 'P1 wins!'
    print(f'wins: {n} games (8 lines x X/O x starter) and a ninth-move win OK')

    # --- draw
    DRAW = [1, 2, 3, 5, 4, 6, 8, 7, 9]
    m = model(api, DRAW[:-1]); assert m.state == 'PLAYING'
    api.place(m, DRAW[-1]); assert m.state == 'GAME_OVER' and m.winner is None and api.headline(m) == 'Draw' and m.focus == YES
    # --- no moves after game over, and none on a filled cell
    m = model(api, [1, 4, 2, 5, 3])
    assert not any(api.place(m, c) for c in range(1, 10)) and m.moves == 5
    m = model(api, [1]); assert not api.place(m, 1) and m.turn == 'O' and m.moves == 1
    print('draw, no moves after game over or on a filled cell OK')

    # --- a fresh launch: game 1, P1, empty board, whatever ctx.state holds
    a.rt.execute("ctx.state = { board = { 'X', 'X', 'O' }, number = 7 }"); a.load()
    assert a.board() == '.........' and a.m.number == 1 and a.m.starter == 'X' and a.m.turn == 'X' and a.m.focus == 1
    texts = a.draw(); assert texts == ['Game 1', 'P1 0 - 0 P2'], texts
    a.play([5]); a.load(); assert a.board() == '.........' and a.m.number == 1

    # --- the focus ring: order, skipped cells, wrapping both ways
    def ring(m): return list(api.focus_ring(m).values())
    assert ring(a.m) == [1, 2, 3, 4, 5, 6, 7, 8, 9]          # no Restart before the first move
    seen = []
    for _ in range(9): seen.append(a.m.focus); a.key('right')
    assert seen == ring(a.m) and a.m.focus == 1
    a.key('left'); assert a.m.focus == 9
    a.key('next'); assert a.m.focus == 9                       # nothing below it yet
    a.play([2, 5]); assert 'Restart' in a.draw()
    assert a.board() == '.X..O....' and ring(a.m) == [1, 3, 4, 6, 7, 8, 9, R]
    a.goto(1); a.key('right'); assert a.m.focus == 3
    a.key('right', 'right'); assert a.m.focus == 6
    a.key('left'); assert a.m.focus == 4
    print('focus ring: order, skipped cells, wrap-around OK')
    # --- after a mark: the next empty cell, wrapping
    a.load(); a.play([1]); assert a.m.focus == 2
    a.play([9]); assert a.m.focus == 2
    a.play([8]); assert a.m.focus == 2
    a.play([2, 4]); assert a.m.focus == 5
    # --- side keys: the X4 Classic's prev / next, then the same as up / down
    a.load(); a.key('next'); assert a.m.focus == 4
    a.key('next', 'next'); assert a.m.focus == 7               # Restart is not there yet
    a.load(); a.play([2]); a.goto(4); a.key('next', 'next'); assert a.m.focus == R
    a.key('next'); assert a.m.focus == R
    a.key('prev'); assert a.m.focus == 9                       # Restart is at the bottom right
    a.key('prev'); assert a.m.focus == 6
    a.load(); a.play([4]); a.goto(1); a.key('next'); assert a.m.focus == 5       # 4 is filled: the nearest in that row
    a.load(); a.key('down'); assert a.m.focus == 4
    a.key('down'); assert a.m.focus == 7
    a.key('up'); assert a.m.focus == 4
    a.goto(9); a.key('up', 'up'); assert a.m.focus == 3
    a.key('up'); assert a.m.focus == 3
    def rs(cells, focus, d):
        m = model(api, cells); m.focus = focus; return api.row_step(m, d)
    assert rs([5], 2, 1) == 4                                  # below is filled: nearest, left on a tie
    assert rs([4, 5], 1, 1) == 6
    assert rs([4, 5, 6], 2, 1) == 8                            # a full row is passed over
    assert rs([7, 8, 4, 9], 5, 1) == R                         # nothing empty below
    assert rs([7, 5, 8, 9], R, -1) == 6                        # bottom row full: the next one up
    assert rs([1, 2, 4, 3], 5, -1) == 5                        # nothing empty above
    print('next empty cell, side keys OK')

    # --- game over through the buttons: the New game? box with the winner, only Yes and No
    a.load(); a.play([1, 4, 2, 5, 3])
    assert a.m.state == 'GAME_OVER' and a.m.focus == YES and ring(a.m) == [YES, NO]
    before = a.board()
    a.key('right'); assert a.m.focus == NO
    a.key('right'); assert a.m.focus == YES
    a.key('up', 'down', 'prev', 'next', 'left'); assert a.m.focus == NO and a.board() == before
    for cells, who, score in (([1, 4, 2, 5, 3], 'P1 wins!', '1 - 0'), ([1, 4, 2, 5, 9, 6], 'P2 wins!', '0 - 1'), (DRAW, 'Draw', '0 - 0')):
        a.load(); a.play(cells)
        assert api.headline(a.m) == who                                     # the banner's; the box only asks
        assert a.draw() == ['New game?', 'Yes', 'No', 'Game 1', f'P1 {score} P2'], a.draw()
        q = a.n('quits'); a.key('right', 'ok')                              # No: leaves, without asking
        assert a.n('quits') == q + 1 and a.m.confirm is None and a.m.number == 1
    a.load(); a.play([1, 4, 2, 5, 3])
    # --- alternation of the starter across restarts, no question after game over
    for game in range(2, 7):
        q = a.n('quits'); a.key('ok')                 # Yes has the focus
        assert a.n('quits') == q
        starter = 'X' if game % 2 else 'O'
        assert a.m.confirm is None and a.m.number == game and a.m.starter == starter == a.m.turn and a.board() == '.........'
        assert a.m.focus == 1
        p = 'P1' if starter == 'X' else 'P2'
        assert a.draw() == [f'Game {game}', f'P1 {game // 2} - {(game - 1) // 2} P2'] and api.headline(a.m) == f"{p}'s turn ({starter})"
        a.play([1, 4, 2, 5, 3]); assert a.m.winner == starter and a.m.state == 'GAME_OVER'
    assert api.tally(a.m) == 'P1 3 - 3 P2'
    # the tally: kept by a draw and by Restart in the middle of a game, back to 0 - 0 on a new launch
    a.load(); a.play([1, 4, 2, 5, 3]); a.key('ok'); a.play([1, 4, 2, 5, 3]); a.key('ok'); a.play([1, 4, 2, 5, 3]); a.key('ok')
    assert api.tally(a.m) == 'P1 2 - 1 P2'
    a.play(DRAW); assert a.m.state == 'GAME_OVER' and api.tally(a.m) == 'P1 2 - 1 P2'
    a.key('ok'); a.play([5]); a.goto(R); a.key('ok', 'right', 'ok')
    assert a.m.number == 6 and a.m.moves == 0 and api.tally(a.m) == 'P1 2 - 1 P2' and a.draw()[-1] == 'P1 2 - 1 P2'
    a.load(); assert api.tally(a.m) == 'P1 0 - 0 P2'
    # with two digits it stays clear of Restart on the same line (13 px a letter, as measured above)
    L = api.layout(480, 800); assert L.info_x + 13 * len('P1 12 - 10 P2') < L.restart.x and L.tally_y + 24 <= 800
    assert L.by + 3 * L.cell < L.over.y and L.over.y + L.over.h < L.game_y
    print('game over, starter alternation OK')

    # --- the turn line: every letter is there
    for m in (model(api, []), model(api, [1])):
        assert all(api.TURN_FONT[c] for c in api.headline(m)), api.headline(m)

    # --- confirm: only in the middle of a game
    ASK = 'Quit this round?'
    for how in ('restart', 'back'):
        def ask():
            if how == 'back': assert a.key('back') is True
            else: a.goto(R); a.key('ok')
        action = 'restart' if how == 'restart' else 'exit'
        # mid-game: asks, Cancel first
        a.load(); a.play([5, 1]); q = a.n('quits'); ask()
        assert a.draw() == [ASK, 'Cancel', 'Yes', 'Restart', 'Game 1', 'P1 0 - 0 P2'], a.draw()
        assert a.m.confirm.action == action and a.m.confirm.choice == 'cancel' and a.n('quits') == q
        focus = a.m.focus
        a.key('up', 'down', 'next', 'prev'); assert a.m.confirm.choice == 'cancel'
        a.key('ok'); assert a.m.confirm is None and a.board() == 'O...X....' and a.m.focus == focus and a.n('quits') == q
        # Back cancels, from either choice, and the app stays
        ask(); assert a.key('back') is True and a.m.confirm is None
        ask(); a.key('right'); assert a.m.confirm.choice == 'yes'
        assert a.key('back') is True and a.m.confirm is None and a.board() == 'O...X....' and a.n('quits') == q
        # Left / Right switch and wrap; then Yes
        ask(); a.key('left'); assert a.m.confirm.choice == 'yes'
        a.key('right'); assert a.m.confirm.choice == 'cancel'
        a.key('right', 'ok'); assert a.m.confirm is None
        if action == 'restart': assert a.m.number == 2 and a.m.starter == 'O' and a.board() == '.........' and a.n('quits') == q
        else: assert a.n('quits') == q + 1
    # with no round in progress Back is left to the host, which closes the app
    a.load(); inv = a.n('invals'); assert a.key('back') is False and a.m.confirm is None and a.n('invals') == inv
    a.load(); a.play([1, 4, 2, 5, 3]); assert a.key('back') is False and a.m.state == 'GAME_OVER' and a.m.number == 1
    # it acts on the release only, and a bounce of it does not close the question again
    def back(dt, phase): a.rt.execute(f'now = now + {dt}'); return a.event(type='key', key='back', phase=phase)
    a.load(); a.play([5]); assert back(1000, 'down') is True and a.m.confirm is None
    assert back(300, 'repeat') is True and a.m.confirm is None
    assert back(300, 'up') is True and a.m.confirm is not None
    assert back(5, 'down') is True and back(5, 'up') is True and a.m.confirm is not None
    assert back(400, 'down') is True and back(90, 'up') is True and a.m.confirm is None
    print('confirm: only mid-game; Cancel, Back, Yes for Restart / Back OK')

    # --- debounce: the same key within 250 ms once, another key at once, releases ignored
    a.load(); a.rt.execute('now = now + 1000')
    t = 500000
    def at(dt, key, **kw): return a.event(type='key', key=key, time_ms=t + dt, **kw)
    at(0, 'right', state='down'); assert a.m.focus == 2
    at(10, 'right', state='down'); at(249, 'right', state='down'); assert a.m.focus == 2
    at(250, 'right', state='down'); assert a.m.focus == 3
    at(260, 'left', state='down'); assert a.m.focus == 2
    for f in ('state', 'phase'):
        for v in ('up', 'release', 'released'):
            t += 1000; assert at(0, 'right', **{f: v}) is True and a.m.focus == 2, (f, v)
    t += 1000; at(0, 'right', phase='down'); assert a.m.focus == 3           # API 2.x spelling
    t += 1000; at(0, 'right'); assert a.m.focus == 4                         # no phase at all
    t += 1000; at(0, 'right', state='up'); at(20, 'right', state='down'); assert a.m.focus == 5   # a release does not debounce
    a.load(); a.event(type='key', key='right', state='down'); a.event(type='key', key='right', state='down')
    assert a.m.focus == 2                                                    # without time_ms: ctx.clock
    a.rt.execute('now = now + 300'); a.event(type='key', key='right', state='down'); assert a.m.focus == 3
    a.load(); t += 1000; at(0, 'right', state='down'); at(10, 'down', state='down'); at(20, 'next', state='down')
    assert a.m.focus == 8                                                    # other buttons, even with the same action
    # --- a held button acts once, however the host repeats it; a host without releases still works
    for f in ('state', 'phase'):
        for rep in ('repeat', 'hold', 'long', 'down'):
            a.load(); a.key('right'); t += 5000; at(0, 'ok', **{f: 'down'})          # a release was seen before
            for i in range(1, 11): assert at(300 * i, 'ok', **{f: rep}) is True
            at(3300, 'ok', **{f: 'up'}); assert a.m.moves == 1, (f, rep, a.m.moves)
            at(3700, 'ok', **{f: 'down'}); assert a.m.moves == 2                     # let go: a press again
    a.load(); a.play([1, 4, 2, 5]); a.goto(3); t += 5000; at(0, 'ok', state='down')  # the winning move, held
    for i in range(1, 11): at(300 * i, 'ok', state='down')
    assert a.m.state == 'GAME_OVER' and a.m.number == 1 and a.m.focus == YES         # the result stays on the screen
    a.load(); t += 5000; at(0, 'ok', phase='down'); at(300, 'ok', phase='down'); assert a.m.moves == 1   # API 2.x: at once
    a.load(); t += 5000
    for i in range(3): at(400 * i, 'ok', state='down')
    assert a.m.moves == 3                                                            # no releases at all
    a.load(); a.key('right'); t += 5000; at(0, 'ok', state='down'); at(400, 'ok', state='down'); at(500, 'ok', state='up')
    at(900, 'ok', state='down'); assert a.m.moves == 2                               # a lost release costs one press
    a.load(); t += 5000; at(0, 'ok', state='repeat'); assert a.m.moves == 0          # a repeat alone is no press
    print('held buttons OK')
    # --- touch, pointer, unknown keys and junk do nothing and are not claimed
    a.load(); inv = a.n('invals')
    for ev in ({'type': 'touch', 'gesture': 'tap', 'x': 240, 'y': 300}, {'type': 'pointer', 'phase': 'up', 'gesture': 'tap', 'x': 120, 'y': 690},
               {'type': 'key', 'key': 'power', 'state': 'down'}, {'type': 'key', 'state': 'down'}, {}):
        assert a.event(**ev) is False
    assert a.rt.eval('on_input')(None, 'junk') is False and a.board() == '.........' and a.n('invals') == inv
    print('debounce, releases, ignored events OK')

    # --- refreshes: one fast per change, never a full one (the reader does those by itself)
    a.load(); inv = a.n('invals'); a.key('ok'); assert a.n('invals') == inv + 1
    a.load(); a.play([1, 2, 3, 5, 4, 6, 8, 7, 9]); assert a.m.state == 'GAME_OVER'
    inv = a.n('invals'); a.key('up'); assert a.n('invals') == inv            # nothing changed, nothing redrawn
    a.key('ok'); assert a.m.number == 2 and a.n('invals') == inv + 1
    print('refreshes OK')

    # --- every state draws, within the frame's 1024 commands and the screen, on several screens
    worst = 0
    for w, h in ((480, 800), (528, 792), (800, 480), (240, 400)):
        a.rt.execute(f'W, H = {w}, {h}')
        for cells, keys in (([], []), ([5, 1], ['left', 'back']), ([1, 4, 2, 5, 3], []), ([4, 1, 5, 2, 8, 3], []), (DRAW, ['right']), (DRAW, []),
                            ([1, 2, 3, 4, 5, 6, 8, 7, 9], []), (DRAW[:-1], ['right']), ([2, 1, 3, 5, 9], []), ([1, 4, 2, 5, 9, 6], [])):
            a.load()
            for c in cells: api.place(a.m, c)
            if keys: a.key(*keys)
            a.draw(); worst = max(worst, a.n('cmds'))
            assert a.n('low') >= 0 and a.n('high') <= max(w, h), (w, h, cells, a.n('low'), a.n('high'))
    print('draw commands, worst case:', worst); assert worst < 1000
    a.rt.execute('W, H = 480, 800')

    # --- a circle call that fails leaves letters, not an error
    a.load()
    for c in [1, 4, 2, 5, 9, 6]: api.place(a.m, c)
    a.rt.execute("ALLOWED.circle = nil"); texts = a.draw(); assert texts.count('O') == 3, texts
    a.rt.execute("ALLOWED.circle = true")

    # --- an error is painted, not thrown; keys then go to the host
    a.rt.execute("ctx.clock.millis = function() error('boom') end")
    assert a.rt.eval('on_input')(None, a.rt.table_from({'type': 'key', 'key': 'right', 'state': 'down'})) is True
    assert 'boom' in api.err()
    a.rt.execute('texts = {}'); a.rt.eval('on_draw')(None, a.rt.eval('canvas')); assert 'boom' in ''.join(a.rt.eval('texts').values())
    assert a.rt.eval('on_input')(None, a.rt.table_from({'type': 'key', 'key': 'back', 'state': 'down'})) is False
    print('error screen OK')


run(lua54, 'Lua 5.4')
if lua55: run(lua55, 'Lua 5.5')
else: print('Lua 5.5: not checked (pip install -U lupa)')
print('ALL TESTS PASSED')
