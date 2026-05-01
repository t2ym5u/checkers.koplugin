-- Checkers game logic — ported from ImparaAI/checkers (MIT License)
-- https://github.com/ImparaAI/checkers
-- Player 1 (black) starts at positions 1-12 (top), moves down (increasing row).
-- Player 2 (white) starts at positions 21-32 (bottom), moves up.
-- Positions 1-32 number the 32 dark squares row-by-row, 4 per row.

local Game = {}
Game.__index = Game

-- ── Piece helpers ────────────────────────────────────────────────────────────

local function new_piece(id, player, position)
    return {
        id           = id,
        player       = player,
        other_player = player == 1 and 2 or 1,
        king         = false,
        captured     = false,
        position     = position,
        possible_capture_moves    = nil,
        possible_positional_moves = nil,
        capture_move_enemies      = {},
    }
end

local function piece_reset(p)
    p.possible_capture_moves    = nil
    p.possible_positional_moves = nil
    p.capture_move_enemies      = {}
end

local function piece_row(p, board)
    return math.ceil(p.position / board.width) - 1
end

local function piece_col(p, board)
    return (p.position - 1) % board.width
end

local function row_from_pos(board, pos)
    return math.ceil(pos / board.width) - 1
end

local function piece_on_enemy_home(p, board)
    local target = (p.other_player == 1) and 1 or board.position_count
    return piece_row(p, board) == row_from_pos(board, target)
end

local function next_col_indexes(board, cur_row, cur_col)
    local candidates = (cur_row % 2 == 0)
        and {cur_col, cur_col + 1}
        or  {cur_col - 1, cur_col}
    local out = {}
    for _, c in ipairs(candidates) do
        if c >= 0 and c < board.width then out[#out+1] = c end
    end
    return out
end

local function directional_adjacent(p, board, forward)
    local cur_row = piece_row(p, board)
    local dir     = (p.player == 1 and 1 or -1) * (forward and 1 or -1)
    local nxt_row = cur_row + dir
    if not board.position_layout[nxt_row] then return {} end
    local cols = next_col_indexes(board, cur_row, piece_col(p, board))
    local out  = {}
    for _, c in ipairs(cols) do
        local pos = board.position_layout[nxt_row][c]
        if pos then out[#out+1] = pos end
    end
    return out
end

local function adjacent_positions(p, board)
    local fwd = directional_adjacent(p, board, true)
    if p.king then
        for _, pos in ipairs(directional_adjacent(p, board, false)) do
            fwd[#fwd+1] = pos
        end
    end
    return fwd
end

local function pos_behind_enemy(p, board, enemy)
    local cr = piece_row(p, board);    local cc = piece_col(p, board)
    local er = piece_row(enemy, board); local ec = piece_col(enemy, board)
    local col_adj  = (cr % 2 == 0) and -1 or 1
    local col_behind = (cc == ec) and (cc + col_adj) or ec
    local row_behind = er + (er - cr)
    local rl = board.position_layout[row_behind]
    return rl and rl[col_behind]
end

-- ── BoardSearcher ────────────────────────────────────────────────────────────

local function searcher_build(s, board)
    s.board = board
    local uncap = {}
    for _, p in ipairs(board.pieces) do
        if not p.captured then uncap[#uncap+1] = p end
    end
    s.uncaptured_pieces = uncap

    local pp = {[1]={}, [2]={}}
    local ppos = {[1]={}, [2]={}}
    local bypos = {}
    for _, p in ipairs(uncap) do
        local t  = pp[p.player];   t[#t+1]  = p
        local tp = ppos[p.player]; tp[#tp+1] = p.position
        bypos[p.position] = p
    end
    s.player_pieces    = pp
    s.player_positions = ppos
    s.position_pieces  = bypos
end

local function new_searcher()
    local s = {
        build             = searcher_build,
        uncaptured_pieces = {},
        player_pieces     = {[1]={}, [2]={}},
        player_positions  = {[1]={}, [2]={}},
        position_pieces   = {},
    }
    return s
end

local function pieces_in_play(board)
    if board.piece_requiring_further_capture_moves then
        return {board.piece_requiring_further_capture_moves}
    end
    return board.searcher.player_pieces[board.player_turn]
end

local function pos_is_open(board, pos)
    return board.searcher.position_pieces[pos] == nil
end

-- ── Move generation ──────────────────────────────────────────────────────────

local function build_capture_moves(p, board)
    local adj  = adjacent_positions(p, board)
    local eset = {}
    for _, ep in ipairs(board.searcher.player_positions[p.other_player]) do
        eset[ep] = true
    end
    local dest = {}
    for _, adj_pos in ipairs(adj) do
        if eset[adj_pos] then
            local enemy = board.searcher.position_pieces[adj_pos]
            local behind = pos_behind_enemy(p, board, enemy)
            if behind and pos_is_open(board, behind) then
                dest[#dest+1] = behind
                p.capture_move_enemies[behind] = enemy
            end
        end
    end
    local moves = {}
    for _, d in ipairs(dest) do moves[#moves+1] = {p.position, d} end
    return moves
end

local function build_positional_moves(p, board)
    local moves = {}
    for _, pos in ipairs(adjacent_positions(p, board)) do
        if pos_is_open(board, pos) then
            moves[#moves+1] = {p.position, pos}
        end
    end
    return moves
end

local function get_capture_moves_for_piece(p, board)
    if p.possible_capture_moves == nil then
        p.possible_capture_moves = build_capture_moves(p, board)
    end
    return p.possible_capture_moves
end

local function get_positional_moves_for_piece(p, board)
    if p.possible_positional_moves == nil then
        p.possible_positional_moves = build_positional_moves(p, board)
    end
    return p.possible_positional_moves
end

local function all_capture_moves(board)
    local out = {}
    for _, p in ipairs(pieces_in_play(board)) do
        for _, m in ipairs(get_capture_moves_for_piece(p, board)) do
            out[#out+1] = m
        end
    end
    return out
end

local function all_positional_moves(board)
    local out = {}
    for _, p in ipairs(pieces_in_play(board)) do
        for _, m in ipairs(get_positional_moves_for_piece(p, board)) do
            out[#out+1] = m
        end
    end
    return out
end

local function possible_moves(board)
    local caps = all_capture_moves(board)
    return #caps > 0 and caps or all_positional_moves(board)
end

local function move_in_list(move, list)
    local f, t = move[1], move[2]
    for _, m in ipairs(list) do
        if m[1] == f and m[2] == t then return true end
    end
    return false
end

-- ── Board mutation ───────────────────────────────────────────────────────────

local function rebuild(board)
    for _, p in ipairs(board.pieces) do piece_reset(p) end
    searcher_build(board.searcher, board)
end

local function move_piece(board, move)
    local p = board.searcher.position_pieces[move[1]]
    p.position = move[2]
    if piece_on_enemy_home(p, board) then p.king = true end
    rebuild(board)
end

local function perform_capture(board, move)
    board.previous_move_was_capture = true
    local p = board.searcher.position_pieces[move[1]]
    local was_king = p.king
    get_capture_moves_for_piece(p, board)          -- populate capture_move_enemies
    local enemy = p.capture_move_enemies[move[2]]
    enemy.captured = true
    enemy.position = nil
    move_piece(board, move)                         -- rebuilds searcher
    -- Check for further captures from the new position
    local further = {}
    for _, m in ipairs(all_capture_moves(board)) do
        if m[1] == move[2] then further[#further+1] = m end
    end
    local p_after = board.searcher.position_pieces[move[2]]
    if p_after and #further > 0 and (was_king == p_after.king) then
        board.piece_requiring_further_capture_moves = p_after
    else
        board.piece_requiring_further_capture_moves = nil
        board.player_turn = board.player_turn == 1 and 2 or 1
    end
end

local function perform_positional(board, move)
    board.previous_move_was_capture = false
    move_piece(board, move)
    board.player_turn = board.player_turn == 1 and 2 or 1
end

-- ── Snapshot (undo) ──────────────────────────────────────────────────────────

local function take_snapshot(board, moves_since)
    local pdata = {}
    for _, p in ipairs(board.pieces) do
        pdata[p.id] = {
            player   = p.player,
            king     = p.king,
            captured = p.captured,
            position = p.position,
        }
    end
    return {
        piece_data              = pdata,
        player_turn             = board.player_turn,
        previous_move_capture   = board.previous_move_was_capture,
        piece_requiring_pos     = board.piece_requiring_further_capture_moves
                                  and board.piece_requiring_further_capture_moves.position or nil,
        moves_since_last_capture = moves_since,
    }
end

local function restore_snapshot(board, snap)
    for _, p in ipairs(board.pieces) do
        local d = snap.piece_data[p.id]
        p.player       = d.player
        p.other_player = d.player == 1 and 2 or 1
        p.king         = d.king
        p.captured     = d.captured
        p.position     = d.position
    end
    board.player_turn               = snap.player_turn
    board.previous_move_was_capture = snap.previous_move_capture
    rebuild(board)
    if snap.piece_requiring_pos then
        board.piece_requiring_further_capture_moves =
            board.searcher.position_pieces[snap.piece_requiring_pos]
    else
        board.piece_requiring_further_capture_moves = nil
    end
end

-- ── Board initializer ────────────────────────────────────────────────────────

local function init_board(board)
    local layout = {}
    local pos = 1
    for row = 0, board.height - 1 do
        layout[row] = {}
        for col = 0, board.width - 1 do
            layout[row][col] = pos
            pos = pos + 1
        end
    end
    board.position_layout = layout

    local start_count = board.width * board.rows_per_user_with_pieces  -- 12
    local p1_set, p2_set = {}, {}
    for i = 1, start_count do p1_set[i] = true end
    for i = board.position_count - start_count + 1, board.position_count do p2_set[i] = true end

    local pieces, id = {}, 1
    for row = 0, board.height - 1 do
        for col = 0, board.width - 1 do
            local p = layout[row][col]
            local player = p1_set[p] and 1 or (p2_set[p] and 2 or nil)
            if player then
                pieces[#pieces+1] = new_piece(id, player, p)
                id = id + 1
            end
        end
    end
    board.pieces = pieces
end

local function new_board()
    local board = {
        player_turn       = 1,
        width             = 4,
        height            = 8,
        position_count    = 32,
        rows_per_user_with_pieces = 3,
        position_layout   = {},
        piece_requiring_further_capture_moves = nil,
        previous_move_was_capture = false,
        pieces            = {},
        searcher          = new_searcher(),
    }
    init_board(board)
    searcher_build(board.searcher, board)
    return board
end

-- ── Public Game API ──────────────────────────────────────────────────────────

function Game.new()
    local self = setmetatable({}, Game)
    self.board                         = new_board()
    self.history                       = {}
    self.consecutive_noncapture_limit  = 40
    self.moves_since_last_capture      = 0
    return self
end

function Game:get_possible_moves()
    return possible_moves(self.board)
end

-- Valid moves for one specific piece (respects forced-capture rule).
function Game:get_moves_for_piece(position)
    local all   = possible_moves(self.board)
    local out   = {}
    for _, m in ipairs(all) do
        if m[1] == position then out[#out+1] = m end
    end
    return out
end

-- Apply move {from_pos, to_pos}. Returns true on success.
function Game:move(from_pos, to_pos)
    local move = {from_pos, to_pos}
    if not move_in_list(move, possible_moves(self.board)) then return false end
    self.history[#self.history+1] = take_snapshot(self.board, self.moves_since_last_capture)
    local is_cap = move_in_list(move, all_capture_moves(self.board))
    if is_cap then
        perform_capture(self.board, move)
        self.moves_since_last_capture = 0
    else
        perform_positional(self.board, move)
        self.moves_since_last_capture = self.moves_since_last_capture + 1
    end
    return true
end

-- Undo one full turn (collapses multi-jump sub-moves into one undo step).
function Game:undo()
    if #self.history == 0 or self:is_mid_jump() then return false end
    repeat
        local snap = table.remove(self.history)
        self.moves_since_last_capture = snap.moves_since_last_capture
        restore_snapshot(self.board, snap)
    until (not self:is_mid_jump()) or (#self.history == 0)
    return true
end

function Game:is_over()
    return self.moves_since_last_capture >= self.consecutive_noncapture_limit
        or #possible_moves(self.board) == 0
end

-- Returns 1 or 2 if that player wins, nil if game is ongoing.
function Game:get_winner()
    if #possible_moves(self.board) == 0 then
        return self.board.player_turn == 1 and 2 or 1
    end
    return nil
end

function Game:whose_turn()
    return self.board.player_turn
end

function Game:get_piece_at(position)
    local p = self.board.searcher.position_pieces[position]
    if p then return {player = p.player, king = p.king} end
    return nil
end

function Game:is_mid_jump()
    return self.board.piece_requiring_further_capture_moves ~= nil
end

function Game:get_mid_jump_piece_pos()
    local p = self.board.piece_requiring_further_capture_moves
    return p and p.position or nil
end

function Game:can_undo()
    return #self.history > 0 and not self:is_mid_jump()
end

-- Clone the game state for AI search (no history needed in the clone).
function Game:clone()
    local c = setmetatable({}, Game)

    local sb = self.board
    local prcfcm_pos = sb.piece_requiring_further_capture_moves
        and sb.piece_requiring_further_capture_moves.position or nil

    local new_pieces = {}
    for i, p in ipairs(sb.pieces) do
        new_pieces[i] = {
            id           = p.id,
            player       = p.player,
            other_player = p.other_player,
            king         = p.king,
            captured     = p.captured,
            position     = p.position,
            possible_capture_moves    = nil,
            possible_positional_moves = nil,
            capture_move_enemies      = {},
        }
    end

    local new_board = {
        player_turn                           = sb.player_turn,
        width                                 = sb.width,
        height                                = sb.height,
        position_count                        = sb.position_count,
        rows_per_user_with_pieces             = sb.rows_per_user_with_pieces,
        position_layout                       = sb.position_layout,  -- immutable, safe to share
        piece_requiring_further_capture_moves = nil,
        previous_move_was_capture             = sb.previous_move_was_capture,
        pieces                                = new_pieces,
        searcher                              = new_searcher(),
    }
    searcher_build(new_board.searcher, new_board)

    if prcfcm_pos then
        new_board.piece_requiring_further_capture_moves =
            new_board.searcher.position_pieces[prcfcm_pos]
    end

    c.board                        = new_board
    c.history                      = {}
    c.consecutive_noncapture_limit = self.consecutive_noncapture_limit
    c.moves_since_last_capture     = self.moves_since_last_capture
    return c
end

return Game
