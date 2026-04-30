-- Checkers AI — alpha-beta search with Arthur Samuel-inspired evaluator.
-- Features ported from almostimplemented/checkers (Apache 2.0):
--   piece_score_diff, advancement (adv), center control (cent/kcent),
--   back-row bridge (back).  Search structure unchanged.
--
-- Public API:
--   AI.best_move(game, depth)  →  {from_pos, to_pos} or nil

local AI = {}
AI.__index = AI

local INF = math.huge

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

-- ── Evaluator ────────────────────────────────────────────────────────────────

local function evaluate(game, ai_player)
    if game:is_over() then
        local w = game:get_winner()
        if     w == ai_player then return  10000
        elseif w == nil        then return      0   -- draw
        else                        return -10000
        end
    end

    local score = 0
    -- Piece-type counts needed for the bridge feature.
    local kings = {0, 0}
    local bridge = {0, 0}  -- count of each player's bridge squares occupied

    for pos = 1, 32 do
        local p = game:get_piece_at(pos)
        if p then
            local val = p.king and KING_VAL or MAN_VAL

            -- Samuel cent / kcent: pieces on center squares
            if IS_CENTER[pos] then
                val = val + (p.king and CENTER_KING_BONUS or CENTER_MAN_BONUS)
            end

            -- Samuel adv: men in the advanced zone (past the midfield)
            if not p.king then
                if (p.player == 1 and pos >= 17 and pos <= 24)
                or (p.player == 2 and pos >=  9 and pos <= 16) then
                    val = val + ADV_BONUS
                end
            end

            -- Accumulate piece type counts for bridge check
            if p.king then kings[p.player] = kings[p.player] + 1 end

            -- Track bridge-square occupancy: {1,3} for P1, {29,32} for P2
            if p.player == 1 and (pos == 1 or pos == 3) then
                bridge[1] = bridge[1] + 1
            elseif p.player == 2 and (pos == 29 or pos == 32) then
                bridge[2] = bridge[2] + 1
            end

            if p.player == ai_player then
                score = score + val
            else
                score = score - val
            end
        end
    end

    -- Samuel back: back-row bridge bonus when opponent has no kings.
    -- bridge[p] == 2 means both bridge squares for player p are occupied.
    if bridge[1] == 2 and kings[2] == 0 then
        score = score + (ai_player == 1 and BRIDGE_BONUS or -BRIDGE_BONUS)
    end
    if bridge[2] == 2 and kings[1] == 0 then
        score = score + (ai_player == 2 and BRIDGE_BONUS or -BRIDGE_BONUS)
    end

    return score
end

-- ── Alpha-beta search ────────────────────────────────────────────────────────
-- Works on cloned game states so the live game is never mutated.
-- Multi-jump: when a capture leaves the same player to move, depth is not
-- decremented (the continuation is part of the same ply).

local function alpha_beta(game, depth, alpha, beta, ai_player)
    local current = game:whose_turn()
    local is_max  = (current == ai_player)

    if depth == 0 or game:is_over() then
        return evaluate(game, ai_player)
    end

    local moves = game:get_possible_moves()
    if #moves == 0 then
        return evaluate(game, ai_player)
    end

    local best = is_max and -INF or INF

    for _, m in ipairs(moves) do
        local child = game:clone()
        child:move(m[1], m[2])
        local next_depth = child:whose_turn() ~= current and depth - 1 or depth
        local val = alpha_beta(child, next_depth, alpha, beta, ai_player)
        if is_max then
            if val > best  then best  = val end
            if val > alpha then alpha = val end
        else
            if val < best then best = val end
            if val < beta then beta = val end
        end
        if beta <= alpha then break end
    end
    return best
end

-- ── Public API ───────────────────────────────────────────────────────────────

-- Returns the best {from_pos, to_pos} for the current player, or nil.
-- depth defaults to 5 (good balance of speed vs strength on e-readers).
function AI.best_move(game, depth)
    depth = depth or 5
    local ai_player = game:whose_turn()
    local moves = game:get_possible_moves()
    if #moves == 0 then return nil  end
    if #moves == 1 then return moves[1] end

    local current   = ai_player
    local best_move = nil
    local best_val  = -INF

    for _, m in ipairs(moves) do
        local child = game:clone()
        child:move(m[1], m[2])
        local next_depth = child:whose_turn() ~= current and depth - 1 or depth
        local val = alpha_beta(child, next_depth, -INF, INF, ai_player)
        if val > best_val then
            best_val  = val
            best_move = m
        end
    end
    return best_move
end

return AI
