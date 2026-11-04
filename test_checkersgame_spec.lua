local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.path = DIR .. "?.lua;" .. package.path

describe("CheckersGame", function()
    local CheckersGame

    setup(function()
        CheckersGame = require("checkersgame")
    end)

    describe("new", function()
        it("sets up 12 pieces per player at the start", function()
            local g = CheckersGame.new()
            local counts = { [1] = 0, [2] = 0 }
            for _, p in ipairs(g.board.pieces) do
                counts[p.player] = counts[p.player] + 1
                assert.is_false(p.king)
                assert.is_false(p.captured)
            end
            assert.are.equal(12, counts[1])
            assert.are.equal(12, counts[2])
        end)

        it("player 1 moves first", function()
            local g = CheckersGame.new()
            assert.are.equal(1, g:whose_turn())
        end)
    end)

    describe("get_possible_moves", function()
        it("offers only forward diagonal moves onto open squares at the start", function()
            local g = CheckersGame.new()
            local moves = g:get_possible_moves()
            assert.is_true(#moves > 0)
            for _, m in ipairs(moves) do
                assert.is_nil(g:get_piece_at(m[2]))
            end
        end)
    end)

    describe("move", function()
        it("applies a legal move and switches turn", function()
            local g = CheckersGame.new()
            local moves = g:get_possible_moves()
            local m = moves[1]
            assert.is_true(g:move(m[1], m[2]))
            assert.is_nil(g:get_piece_at(m[1]))
            assert.is_not_nil(g:get_piece_at(m[2]))
            assert.are.equal(2, g:whose_turn())
        end)

        it("rejects a move that isn't in the legal list", function()
            local g = CheckersGame.new()
            -- Position 1 (player 1's own piece) can't legally jump to itself.
            assert.is_false(g:move(1, 1))
        end)
    end)

    describe("undo", function()
        it("restores the previous position and turn", function()
            local g = CheckersGame.new()
            local m = g:get_possible_moves()[1]
            g:move(m[1], m[2])
            assert.is_true(g:undo())
            assert.is_not_nil(g:get_piece_at(m[1]))
            assert.is_nil(g:get_piece_at(m[2]))
            assert.are.equal(1, g:whose_turn())
        end)

        it("returns false when there is no history", function()
            local g = CheckersGame.new()
            assert.is_false(g:undo())
        end)
    end)

    describe("is_over / get_winner", function()
        it("is not over at the start and has no winner yet", function()
            local g = CheckersGame.new()
            assert.is_false(g:is_over())
            assert.is_nil(g:get_winner())
        end)
    end)

    describe("clone", function()
        it("produces an independent copy with the same position", function()
            local g = CheckersGame.new()
            local c = g:clone()
            local m = g:get_possible_moves()[1]
            g:move(m[1], m[2])
            -- The clone must not have been affected by the original's move.
            assert.is_not_nil(c:get_piece_at(m[1]))
            assert.is_nil(c:get_piece_at(m[2]))
        end)
    end)

    -- Builds a position from a 32-char string ('.', 'b', 'B', 'w', 'W').
    local function position(cells, turn)
        return CheckersGame.load{ version = 1, position = cells .. ":" .. (turn or 1) .. ":0:0:0" }
    end

    describe("undo during a multi-jump", function()
        it("goes back to the start of the turn", function()
            -- Black man on 1 jumps the white man on 6, then the one on 14.
            local cells = string.rep(".", 32)
            local function put(s, pos, ch) return s:sub(1, pos - 1) .. ch .. s:sub(pos + 1) end
            cells = put(cells, 1, "b"); cells = put(cells, 6, "w"); cells = put(cells, 14, "w")
            cells = put(cells, 32, "w")
            local g = position(cells)
            local m = g:get_possible_moves()
            assert.are.same({ { 1, 10 } }, m)
            assert.is_true(g:move(1, 10))
            assert.is_true(g:is_mid_jump())
            assert.is_true(g:can_undo())
            assert.is_true(g:undo())
            assert.is_false(g:is_mid_jump())
            assert.are.equal(1, g:whose_turn())
            assert.are.same({ player = 1, king = false }, g:get_piece_at(1))
            assert.are.same({ player = 2, king = false }, g:get_piece_at(6))
        end)
    end)

    describe("serialize / load", function()
        it("round-trips the position, the undo history and the last move", function()
            local g = CheckersGame.new()
            math.randomseed(3)
            for _ = 1, 30 do
                if g:is_over() then break end
                local ms = g:get_possible_moves()
                local m = ms[math.random(#ms)]
                g:move(m[1], m[2])
            end
            local h = CheckersGame.load(g:serialize())
            assert.is_truthy(h)
            for pos = 1, 32 do
                assert.are.same(g:get_piece_at(pos), h:get_piece_at(pos))
            end
            assert.are.equal(g:whose_turn(), h:whose_turn())
            assert.are.equal(g:get_mid_jump_piece_pos(), h:get_mid_jump_piece_pos())
            assert.are.equal(g.moves_since_last_capture, h.moves_since_last_capture)
            assert.are.same(g.last_path, h.last_path)
            assert.are.same(g:get_possible_moves(), h:get_possible_moves())
            -- Undoing both games all the way gives the same positions.
            while g:can_undo() do
                assert.is_true(h:undo())
                g:undo()
                for pos = 1, 32 do
                    assert.are.same(g:get_piece_at(pos), h:get_piece_at(pos))
                end
            end
            assert.is_false(h:can_undo())
        end)

        it("rejects anything that is not a saved game", function()
            assert.is_nil(CheckersGame.load(nil))
            assert.is_nil(CheckersGame.load("x"))
            assert.is_nil(CheckersGame.load{ version = 1, position = "bad" })
            assert.is_nil(CheckersGame.load{ version = 2, position = CheckersGame.new():serialize().position })
        end)

        it("drops a corrupt history but keeps the game", function()
            local data = CheckersGame.new():serialize()
            data.history = { "garbage" }
            local g = CheckersGame.load(data)
            assert.is_truthy(g)
            assert.is_false(g:can_undo())
        end)
    end)

    describe("last_path", function()
        it("records every square of a multi-jump", function()
            local cells = string.rep(".", 32)
            local function put(s, pos, ch) return s:sub(1, pos - 1) .. ch .. s:sub(pos + 1) end
            cells = put(cells, 1, "b"); cells = put(cells, 6, "w"); cells = put(cells, 14, "w")
            cells = put(cells, 32, "w")
            local g = position(cells)
            g:move(1, 10)
            local nxt = g:get_moves_for_piece(10)
            assert.are.equal(1, #nxt)
            g:move(10, nxt[1][2])
            assert.are.same({ 1, 10, nxt[1][2] }, g.last_path)
            assert.are.equal(2, g:whose_turn())
        end)
    end)

    describe("result / must_capture / count", function()
        it("reports a win when the loser has no pieces", function()
            local cells = string.rep(".", 31) .. "b"
            local g = position(cells, 2)
            assert.is_true(g:is_over())
            assert.are.same({ winner = 1, reason = "no_pieces" }, g:result())
            assert.are.equal(1, g:count(1))
            assert.are.equal(0, g:count(2))
        end)

        it("reports a win when the loser is blocked", function()
            -- White's only man, on 29: its one forward square (25) is held by
            -- Black and the jump over it is blocked by a black man on 22.
            local cells = string.rep(".", 32)
            local function put(s, pos, ch) return s:sub(1, pos - 1) .. ch .. s:sub(pos + 1) end
            cells = put(cells, 29, "w"); cells = put(cells, 25, "b"); cells = put(cells, 22, "b")
            local g = position(cells, 2)
            assert.are.equal(0, #g:get_possible_moves())
            assert.are.same({ winner = 1, reason = "blocked" }, g:result())
        end)

        it("reports a draw after 40 moves without a capture", function()
            local g = CheckersGame.new()
            g.moves_since_last_capture = 40
            assert.is_true(g:is_over())
            assert.are.same({ winner = nil, reason = "quiet" }, g:result())
            assert.is_nil(g:get_winner())
        end)

        it("is nil while the game goes on", function()
            assert.is_nil(CheckersGame.new():result())
        end)

        it("knows when a capture is compulsory", function()
            assert.is_false(CheckersGame.new():must_capture())
            local cells = string.rep(".", 32)
            local function put(s, pos, ch) return s:sub(1, pos - 1) .. ch .. s:sub(pos + 1) end
            cells = put(cells, 1, "b"); cells = put(cells, 6, "w"); cells = put(cells, 3, "b")
            local g = position(cells)
            assert.is_true(g:must_capture())
            assert.are.equal(0, #g:get_moves_for_piece(3))
        end)
    end)

    describe("pos_to_rc / rc_to_pos", function()
        it("is a bijection between the 32 squares and the dark cells", function()
            local seen = {}
            for pos = 1, 32 do
                local r, c = CheckersGame.pos_to_rc(pos)
                assert.are.equal(1, (r + c) % 2)
                assert.is_nil(seen[r * 10 + c])
                seen[r * 10 + c] = true
                assert.are.equal(pos, CheckersGame.rc_to_pos(r, c))
            end
            assert.is_nil(CheckersGame.rc_to_pos(1, 1))
            assert.is_nil(CheckersGame.rc_to_pos(0, 1))
        end)

        it("puts Black's pieces at the bottom, dark square bottom-left", function()
            local g = CheckersGame.new()
            for pos = 1, 32 do
                local p = g:get_piece_at(pos)
                local r = CheckersGame.pos_to_rc(pos)
                if p then assert.are.equal(p.player == 1, r >= 6) end
            end
            assert.is_truthy(CheckersGame.rc_to_pos(8, 1))
        end)
    end)
end)
