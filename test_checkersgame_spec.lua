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
end)
