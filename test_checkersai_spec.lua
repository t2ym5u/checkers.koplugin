local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.path = DIR .. "?.lua;" .. package.path

describe("CheckersAI", function()
    local CheckersGame, CheckersAI

    setup(function()
        CheckersGame = require("checkersgame")
        CheckersAI   = require("checkersai")
    end)

    after_each(function()
        CheckersAI.time_scale = 1
    end)

    local function is_legal(game, m)
        for _, l in ipairs(game:get_possible_moves()) do
            if l[1] == m[1] and l[2] == m[2] then return true end
        end
        return false
    end

    -- Random mid-game positions (including mid-jump states).
    local function random_positions(n, seed)
        local out = {}
        math.randomseed(seed)
        for _ = 1, n do
            local g = CheckersGame.new()
            for _ = 1, math.random(0, 50) do
                if g:is_over() then break end
                local ms = g:get_possible_moves()
                local m = ms[math.random(#ms)]
                g:move(m[1], m[2])
            end
            if not g:is_over() then out[#out + 1] = g end
        end
        return out
    end

    it("returns nil when there is no legal move", function()
        local g = CheckersGame.new()
        g.board.searcher.player_pieces[1] = {}
        assert.is_nil(CheckersAI.best_move(g, 5))
    end)

    it("still returns a legal move when the budget runs out immediately", function()
        CheckersAI.time_scale = 0
        for _, g in ipairs(random_positions(40, 11)) do
            local m = CheckersAI.best_move(g, 9)
            assert.is_truthy(m)
            assert.is_true(is_legal(g, m))
        end
    end)

    it("does not mutate the game", function()
        for _, g in ipairs(random_positions(20, 13)) do
            local before = {}
            for pos = 1, 32 do
                local p = g:get_piece_at(pos)
                before[pos] = p and (p.player + (p.king and 2 or 0)) or 0
            end
            local turn, mid = g:whose_turn(), g:get_mid_jump_piece_pos()
            CheckersAI.time_scale = 0.04
            CheckersAI.best_move(g, 7)
            for pos = 1, 32 do
                local p = g:get_piece_at(pos)
                assert.are.equal(before[pos], p and (p.player + (p.king and 2 or 0)) or 0)
            end
            assert.are.equal(turn, g:whose_turn())
            assert.are.equal(mid, g:get_mid_jump_piece_pos())
        end
    end)
end)
