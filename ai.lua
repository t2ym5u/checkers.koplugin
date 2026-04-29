-- Checkers AI — alpha-beta search with positional evaluator.
-- Ported / adapted from njmarko/alpha-beta-pruning-minmax-checkers (GPL-3.0).
--
-- Public API:
--   AI.best_move(game, depth)  →  {from_pos, to_pos} or nil

local AI = {}
AI.__index = AI

local INF = math.huge

-- ── Piece values ─────────────────────────────────────────────────────────────

local MAN_VAL      = 100
local KING_VAL     = 160
local ADV_PER_ROW  =   3   -- per row of advancement toward promotion
local CENTER_BONUS =  10   -- inner two columns of dark squares (≈ board center)

-- ── Evaluator ────────────────────────────────────────────────────────────────
-- Positions 1-32 number dark squares row-by-row, 4 per row.
--   row      = ceil(pos/4) - 1   (0 = top, 7 = bottom)
--   col_idx  = (pos-1) % 4       (0..3 within the dark-square columns per row)
--
-- Player 1 (black) advances down (row 0 → 7); player 2 (white) advances up.
-- Score is always from ai_player's perspective (+good for AI).

local function evaluate(game, ai_player)
    if game:is_over() then
        local w = game:get_winner()
        if     w == ai_player then return  10000
        elseif w == nil        then return      0  -- draw
        else                        return -10000
        end
    end

    local score = 0
    for pos = 1, 32 do
        local piece = game:get_piece_at(pos)
        if piece then
            local row     = math.ceil(pos / 4) - 1
            local col_idx = (pos - 1) % 4
            local val = piece.king and KING_VAL or MAN_VAL
            if not piece.king then
                if piece.player == 1 then
                    val = val + row * ADV_PER_ROW           -- black advances down
                else
                    val = val + (7 - row) * ADV_PER_ROW     -- white advances up
                end
            end
            if col_idx == 1 or col_idx == 2 then
                val = val + CENTER_BONUS
            end
            if piece.player == ai_player then
                score = score + val
            else
                score = score - val
            end
        end
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
        -- Don't consume a depth level for mid-jump continuations (same player).
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
