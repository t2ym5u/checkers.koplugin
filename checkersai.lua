-- Checkers AI — alpha-beta search with Arthur Samuel-inspired evaluator.
-- Features ported from almostimplemented/checkers (Apache 2.0):
--   piece_score_diff, advancement (adv), center control (cent/kcent),
--   back-row bridge (back).
--
-- Search: iterative deepening negamax alpha-beta on a compact 32-square
-- array (make/unmake, no game cloning), with a transposition table,
-- killer/history move ordering and a CPU-time budget per difficulty level,
-- so a move never takes much longer than the budget on a slow e-reader.
-- The preset depth is kept as the maximum depth.
--
-- Public API:
--   CheckersAI.best_move(game, depth[, budget[, opts]])  →  {from_pos, to_pos} or nil
--   CheckersAI.LEVELS[id]  →  { depth, budget, noise } per difficulty

local CheckersAI = {}
CheckersAI.__index = CheckersAI

-- ── Time budget ──────────────────────────────────────────────────────────────
-- Seconds of thinking per move, keyed by the preset depth (see
-- DIFF_DEPTH in screen.lua). Tuned for a Kobo-class 1 GHz single-core device.
-- (Used when best_move gets no explicit budget.)
CheckersAI.BUDGET = {
    [3] = 0.5,   -- Easy   (always reaches its depth well within this)
    [5] = 1.0,   -- Medium
    [7] = 2.0,   -- Hard
    [9] = 2.3,   -- Expert (the clock is read every 1024 nodes: stays < 2.5 s)
}
CheckersAI.DEFAULT_BUDGET = 2.3

-- Difficulty levels.
-- depth:  deepest iteration of the search.
-- budget: thinking time in seconds on the e-reader.
-- noise:  a random bonus in [0, noise) added to each move's score before
--         choosing (a man is worth 100), so a level does not answer a line
--         the same way every game and Easy makes human-sized mistakes.
--         Forced wins and losses (10000) are far beyond it.
-- Measured (Kobo-scaled budgets, randomised openings): Easy scores about
-- 40% against a 1-ply greedy player (many draws), each level 68-98% against
-- the one below. Hard is depth 6, not 7: at 7 it came too close to Expert,
-- whose 2.3 s rarely reach depth 9.
CheckersAI.LEVELS = {
    easy   = { depth = 1, budget = 0.5, noise = 20 },
    medium = { depth = 4, budget = 1.0, noise = 10 },
    hard   = { depth = 6, budget = 2.0, noise = 0 },
    expert = { depth = 9, budget = 2.3, noise = 0 },
}
-- Multiplier applied to every budget (test harnesses lower it to simulate a
-- slower device on a fast machine).
CheckersAI.time_scale = 1

local function budget_for(depth)
    local best
    for d, b in pairs(CheckersAI.BUDGET) do
        if d >= depth and (not best or d < best) then best = d end
    end
    return best and CheckersAI.BUDGET[best] or CheckersAI.DEFAULT_BUDGET
end

local floor = math.floor
local clock = os.clock

local INF = 1000000
local WIN = 10000

-- ── Piece values ─────────────────────────────────────────────────────────────
-- Samuel uses 2:3 (men:kings) for piece_score_diff; we scale to our unit space.

local MAN_VAL  = 100
local KING_VAL = 150   -- 3/2 × man, matching Samuel's 2:3 ratio

-- ── Samuel positional constants ───────────────────────────────────────────────

-- Samuel's center squares: 11,12,15,16,20,21,24,25.
-- Positions use our 1–32 row-major dark-square numbering, which is identical to
-- Samuel's IBM 704 board numbering (bit gaps at 8,17,26,35 are transparent here).
local IS_CENTER = {
    [11]=true, [12]=true, [15]=true, [16]=true,
    [20]=true, [21]=true, [24]=true, [25]=true,
}

-- Advancement zones (Samuel's "rows 5-6" from each player's direction):
--   Player 1 (black, moves down): positions 17–24 = Samuel rows 5-6
--   Player 2 (white, moves up):   positions  9–16 = Samuel rows 5-6 from white's view
-- Being in this zone is credited for men only (kings don't benefit directionally).
local ADV_BONUS = 10

-- Center bonus per piece type (Samuel cent/kcent features).
local CENTER_MAN_BONUS  = 15
local CENTER_KING_BONUS = 25

-- Back-row bridge (Samuel's "back" feature):
--   Credit when the passive player's two bridge squares are both occupied and
--   the active player has no kings (cannot attack the back row diagonally).
--   Bridge squares: {1,3} for player 1 (black home), {29,32} for player 2 (white home).
local BRIDGE_BONUS = 30

-- ── Board encoding ───────────────────────────────────────────────────────────
-- B[pos] = 0 empty, 1 black man, 2 white man, 3 black king, 4 white king.
local OWNER = { 1, 2, 1, 2 }
local IS_KING = { false, false, true, true }

-- PVAL[v][pos]: evaluator value of piece v on pos, from its owner's view.
local PVAL = {}
for v = 1, 4 do
    PVAL[v] = {}
    for pos = 1, 32 do
        local king = IS_KING[v]
        local val = king and KING_VAL or MAN_VAL
        if IS_CENTER[pos] then
            val = val + (king and CENTER_KING_BONUS or CENTER_MAN_BONUS)
        end
        if not king then
            local p = OWNER[v]
            if (p == 1 and pos >= 17 and pos <= 24)
            or (p == 2 and pos >=  9 and pos <= 16) then
                val = val + ADV_BONUS
            end
        end
        PVAL[v][pos] = val
    end
end

-- Geometry: dark squares numbered 1..32, 4 per row; row r, x on the 8x8 board.
-- Directions 1,2 go down (player 1 forward), 3,4 go up (player 2 forward).
local DR = { 1, 1, -1, -1 }
local DX = { -1, 1, -1, 1 }
local STEP, JUMP = {}, {}
local JMID = {}          -- JMID[from*64 + to] = jumped square
local LAST_ROW = {}      -- LAST_ROW[player][pos]: man promotes on reaching pos
do
    local function pos_of(r, x)
        if r < 0 or r > 7 or x < 0 or x > 7 then return 0 end
        if (r + x) % 2 == 0 then return 0 end
        return r * 4 + floor(x / 2) + 1
    end
    for d = 1, 4 do STEP[d], JUMP[d] = {}, {} end
    for pos = 1, 32 do
        local r = floor((pos - 1) / 4)
        local c = (pos - 1) % 4
        local x = 2 * c + (r % 2 == 0 and 1 or 0)
        for d = 1, 4 do
            STEP[d][pos] = pos_of(r + DR[d], x + DX[d])
            local j = STEP[d][pos] ~= 0 and pos_of(r + 2 * DR[d], x + 2 * DX[d]) or 0
            JUMP[d][pos] = j
            if j ~= 0 then JMID[pos * 64 + j] = STEP[d][pos] end
        end
    end
    LAST_ROW[1], LAST_ROW[2] = {}, {}
    for pos = 1, 32 do
        LAST_ROW[1][pos] = pos >= 29
        LAST_ROW[2][pos] = pos <= 4
    end
end
-- DIRS[v]: directions piece v may move in.
local DIRS = { { 1, 2 }, { 3, 4 }, { 1, 2, 3, 4 }, { 1, 2, 3, 4 } }

-- Additive Zobrist-style hashing: random integers < 2^46 so that the sum of
-- 32 squares plus extras stays exactly representable in a double.
local ZP = {}
local Z_SIDE, Z_MID = 0, {}
do
    -- A private deterministic generator, so the caller's math.random
    -- sequence is never disturbed.
    local seed = 12345
    local function rnd()
        local function n()
            seed = (seed * 16807) % 2147483647   -- Park-Miller, exact in doubles
            return seed
        end
        return (n() % 8388608) * 8388608 + n() % 8388608
    end
    for v = 1, 4 do
        ZP[v] = {}
        for pos = 1, 32 do ZP[v][pos] = rnd() end
    end
    Z_SIDE = rnd()
    for pos = 1, 32 do Z_MID[pos] = rnd() end
end

-- ── Search state (module-level, reused between calls) ───────────────────────

local B = {}
local stm, mid, msc, LIMIT = 1, 0, 0, 40
local H = 0
local nodes, deadline, aborted = 0, 0, false

local MOVES = {}         -- MOVES[ply] = array of encoded moves (from*64+to)
local SCORES = {}
for i = 1, 128 do MOVES[i], SCORES[i] = {}, {} end
local KILLER1, KILLER2 = {}, {}
local HIST = {}

local TT_SIZE = 65536
local TT_KEY, TT_DEPTH, TT_VAL, TT_FLAG, TT_MOVE = {}, {}, {}, {}, {}
local EXACT, LOWER, UPPER = 0, 1, 2

local function clear_tables()
    for i = 0, TT_SIZE - 1 do TT_KEY[i] = -1 end
    for i = 1, 128 do KILLER1[i], KILLER2[i] = 0, 0 end
    for i = 0, 64 * 33 do HIST[i] = 0 end
end

local function has_capture_from(pos)
    local v = B[pos]
    local me = OWNER[v]
    for _, d in ipairs(DIRS[v]) do
        local s, j = STEP[d][pos], JUMP[d][pos]
        if j ~= 0 then
            local e = B[s]
            if e ~= 0 and OWNER[e] ~= me and B[j] == 0 then return true end
        end
    end
    return false
end

-- Fills MOVES[ply] with the legal moves (forced captures, multi-jump
-- continuation restricted to the jumping piece); returns the count.
local function gen(ply)
    local list = MOVES[ply]
    local n = 0
    if mid ~= 0 then
        local v = B[mid]
        for _, d in ipairs(DIRS[v]) do
            local s, j = STEP[d][mid], JUMP[d][mid]
            if j ~= 0 then
                local e = B[s]
                if e ~= 0 and OWNER[e] ~= stm and B[j] == 0 then
                    n = n + 1; list[n] = mid * 64 + j
                end
            end
        end
        return n
    end
    for pos = 1, 32 do
        local v = B[pos]
        if v ~= 0 and OWNER[v] == stm then
            for _, d in ipairs(DIRS[v]) do
                local s, j = STEP[d][pos], JUMP[d][pos]
                if j ~= 0 then
                    local e = B[s]
                    if e ~= 0 and OWNER[e] ~= stm and B[j] == 0 then
                        n = n + 1; list[n] = pos * 64 + j
                    end
                end
            end
        end
    end
    if n > 0 then return n end
    for pos = 1, 32 do
        local v = B[pos]
        if v ~= 0 and OWNER[v] == stm then
            for _, d in ipairs(DIRS[v]) do
                local s = STEP[d][pos]
                if s ~= 0 and B[s] == 0 then
                    n = n + 1; list[n] = pos * 64 + s
                end
            end
        end
    end
    return n
end

-- Evaluation from the side to move's point of view (the Samuel evaluator is
-- symmetric, so this equals the original ai-player score up to sign).
local function evaluate()
    local score = 0
    local k1, k2 = 0, 0
    for pos = 1, 32 do
        local v = B[pos]
        if v ~= 0 then
            if OWNER[v] == 1 then
                score = score + PVAL[v][pos]
                if v == 3 then k1 = k1 + 1 end
            else
                score = score - PVAL[v][pos]
                if v == 4 then k2 = k2 + 1 end
            end
        end
    end
    if B[1] == 1 or B[1] == 3 then
        if (B[3] == 1 or B[3] == 3) and k2 == 0 then score = score + BRIDGE_BONUS end
    end
    if B[29] == 2 or B[29] == 4 then
        if (B[32] == 2 or B[32] == 4) and k1 == 0 then score = score - BRIDGE_BONUS end
    end
    return stm == 1 and score or -score
end

-- Board hash including side to move and mid-jump piece.
local function key()
    local k = H
    if stm == 2 then k = k + Z_SIDE end
    if mid ~= 0 then k = k + Z_MID[mid] end
    return k
end

local negamax

-- Plays move m, searches the child, undoes it. Returns the score from the
-- mover's point of view.
local function search_child(m, depth, alpha, beta, ply)
    local f = floor(m / 64)
    local t = m - f * 64
    local v = B[f]
    local p_stm, p_mid, p_msc, p_H = stm, mid, msc, H
    B[f] = 0; B[t] = v
    H = H - ZP[v][f] + ZP[v][t]
    local capsq, capv = JMID[f * 64 + t], 0
    local jump = (t - f > 5 or f - t > 5)
    local promoted = false
    if not IS_KING[v] and LAST_ROW[OWNER[v]][t] then
        B[t] = v + 2
        H = H - ZP[v][t] + ZP[v + 2][t]
        promoted = true
    end
    if jump then
        capv = B[capsq]
        B[capsq] = 0
        H = H - ZP[capv][capsq]
        msc = 0
        if not promoted and has_capture_from(t) then
            mid = t
        else
            mid = 0; stm = 3 - stm
        end
    else
        msc = msc + 1
        mid = 0; stm = 3 - stm
    end

    local val
    if stm == p_stm then
        val = negamax(depth, alpha, beta, ply + 1)
    else
        val = -negamax(depth - 1, -beta, -alpha, ply + 1)
    end

    B[t] = 0; B[f] = v
    if jump then B[capsq] = capv end
    stm, mid, msc, H = p_stm, p_mid, p_msc, p_H
    return val
end

-- Orders MOVES[ply][1..n] in place: hash move, then killers, then history.
local function order(ply, n, hash_move)
    local list, sc = MOVES[ply], SCORES[ply]
    local k1, k2 = KILLER1[ply], KILLER2[ply]
    for i = 1, n do
        local m = list[i]
        local s
        if m == hash_move then s = 1e9
        elseif m == k1 then s = 1e8
        elseif m == k2 then s = 1e8 - 1
        else s = HIST[(floor(m / 64)) * 33 + m % 64] or 0 end
        sc[i] = s
    end
    for i = 2, n do
        local m, s = list[i], sc[i]
        local j = i - 1
        while j >= 1 and sc[j] < s do
            list[j + 1], sc[j + 1] = list[j], sc[j]
            j = j - 1
        end
        list[j + 1], sc[j + 1] = m, s
    end
end

negamax = function(depth, alpha, beta, ply)
    nodes = nodes + 1
    if nodes % 1024 == 0 and clock() > deadline then aborted = true end
    if aborted then return 0 end

    local n = gen(ply)
    if n == 0 then return -(WIN - ply) end
    if msc >= LIMIT then return 0 end
    if depth <= 0 or ply >= 120 then return evaluate() end

    -- Transposition table. The draw counter is not hashed, so entries are
    -- only used where the 40-move rule cannot be reached within the subtree.
    local use_tt = msc + depth < LIMIT
    local k = key()
    local idx = k % TT_SIZE
    local hash_move = 0
    if TT_KEY[idx] == k then
        hash_move = TT_MOVE[idx]
        if use_tt and TT_DEPTH[idx] >= depth then
            local tv, tf = TT_VAL[idx], TT_FLAG[idx]
            if tf == EXACT then return tv end
            if tf == LOWER and tv >= beta then return tv end
            if tf == UPPER and tv <= alpha then return tv end
        end
    end

    order(ply, n, hash_move)
    local list = MOVES[ply]
    local alpha0 = alpha
    local best, best_move = -INF, list[1]
    for i = 1, n do
        local m = list[i]
        local val = search_child(m, depth, alpha, beta, ply)
        if aborted then return 0 end
        if val > best then
            best = val; best_move = m
            if val > alpha then alpha = val end
            if alpha >= beta then
                if KILLER1[ply] ~= m then KILLER2[ply] = KILLER1[ply]; KILLER1[ply] = m end
                local hi = floor(m / 64) * 33 + m % 64
                HIST[hi] = (HIST[hi] or 0) + depth * depth
                break
            end
        end
    end

    if use_tt then
        TT_KEY[idx] = k
        TT_DEPTH[idx] = depth
        TT_VAL[idx] = best
        TT_MOVE[idx] = best_move
        TT_FLAG[idx] = best <= alpha0 and UPPER or (best >= beta and LOWER or EXACT)
    end
    return best
end

local function load(game)
    H = 0
    for pos = 1, 32 do
        local p = game:get_piece_at(pos)
        local v = 0
        if p then v = p.player + (p.king and 2 or 0) end
        B[pos] = v
        if v ~= 0 then H = H + ZP[v][pos] end
    end
    stm = game:whose_turn()
    mid = game:get_mid_jump_piece_pos() or 0
    msc = game.moves_since_last_capture or 0
    LIMIT = game.consecutive_noncapture_limit or 40
end

-- Last search statistics (for tests and tuning).
CheckersAI.last_depth = 0
CheckersAI.last_nodes = 0

-- ── Public API ───────────────────────────────────────────────────────────────

-- Returns the best {from_pos, to_pos} for the current player, or nil.
-- depth is the maximum search depth (defaults to 5); the search deepens
-- iteratively until that depth or the level's time budget is reached.
-- The returned move is always one of game:get_possible_moves().
-- opts: optional { noise, rng } (see LEVELS; rng defaults to math.random).
function CheckersAI.best_move(game, depth, budget, opts)
    depth = depth or 5
    local noise = opts and opts.noise or 0
    local rng = opts and opts.rng or math.random
    local exact = noise > 0
    local legal = game:get_possible_moves()
    CheckersAI.last_depth, CheckersAI.last_nodes = 0, 0
    if #legal == 0 then return nil  end
    if #legal == 1 then return legal[1] end

    budget = (budget or budget_for(depth)) * CheckersAI.time_scale
    deadline = clock() + budget
    nodes, aborted = 0, false
    load(game)
    clear_tables()

    local n = gen(1)
    local root = {}
    for i = 1, n do root[i] = MOVES[1][i] end
    local best_move = root[1]
    local final_scores   -- root scores of the last full iteration

    for d = 1, depth do
        local alpha, beta = -INF, INF
        local iter_best, iter_val = nil, -INF
        local scores = {}
        for i = 1, #root do
            local m = root[i]
            -- With noise, every move that could still be picked once a bonus
            -- below `noise` is added needs its true score, not a bound.
            local val = search_child(m, d, exact and iter_val - noise or alpha, beta, 1)
            if aborted then break end
            scores[m] = val
            if val > iter_val then
                iter_val, iter_best = val, m
                if val > alpha then alpha = val end
            end
        end
        if aborted then
            -- A partial iteration still searched the previous best move
            -- first; any move that beat it is a genuine improvement.
            if not exact and iter_best and iter_best ~= root[1] then best_move = iter_best end
            break
        end
        best_move = iter_best
        final_scores = scores
        CheckersAI.last_depth = d
        CheckersAI.last_value = iter_val
        -- Previous best move first in the next iteration.
        for i = 1, #root do
            if root[i] == best_move then
                table.remove(root, i); table.insert(root, 1, best_move)
                break
            end
        end
        if iter_val >= WIN - 200 or iter_val <= -(WIN - 200) then break end  -- forced result found
    end
    CheckersAI.last_nodes = nodes

    -- Noise: the move with the best score plus a random bonus.
    if exact and final_scores then
        local best_v = -INF
        for i = 1, #root do
            local m = root[i]
            local v = final_scores[m] + rng() * noise
            if v > best_v then best_v, best_move = v, m end
        end
    end

    local f = floor(best_move / 64)
    local t = best_move - f * 64
    for _, m in ipairs(legal) do
        if m[1] == f and m[2] == t then return m end
    end
    return legal[1]
end

return CheckersAI
