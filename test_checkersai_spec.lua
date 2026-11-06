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

    it("always returns a legal move, at every preset depth", function()
        CheckersAI.time_scale = 0.01   -- keep the spec quick
        for _, g in ipairs(random_positions(25, 7)) do
            for _, depth in ipairs({ 3, 5, 7, 9 }) do
                local m = CheckersAI.best_move(g, depth)
                assert.is_truthy(m)
                assert.is_true(is_legal(g, m))
            end
        end
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

    it("takes a free capture-and-win over anything else", function()
        -- Black man on 22, white's last man on 26: black must jump 22->31.
        local g = CheckersGame.new()
        for _, p in ipairs(g.board.pieces) do p.captured = true; p.position = nil end
        local b, w = g.board.pieces[1], g.board.pieces[24]
        b.captured, b.position = false, 22
        w.captured, w.position = false, 26
        g.board.searcher:build(g.board)
        local m = CheckersAI.best_move(g, 5)
        assert.is_true(is_legal(g, m))
    end)

    describe("difficulty levels", function()
        local function aiMove(g, id)
            local L = CheckersAI.LEVELS[id]
            return CheckersAI.best_move(g, L.depth, L.budget, L)
        end

        -- A whole game (capped), every move from `id`, the rng seeded.
        local function playGame(id, seed)
            math.randomseed(seed)
            local g = CheckersGame.new()
            local out = {}
            for _ = 1, 80 do
                if g:is_over() then break end
                local m = aiMove(g, id)
                assert.is_true(is_legal(g, m))
                out[#out + 1] = m[1] .. "-" .. m[2]
                g:move(m[1], m[2])
            end
            return table.concat(out, ",")
        end

        it("gets weaker from Expert to Easy", function()
            local L = CheckersAI.LEVELS
            local ids = { "easy", "medium", "hard", "expert" }
            for i = 2, #ids do
                assert.is_true(L[ids[i - 1]].depth < L[ids[i]].depth)
                assert.is_true(L[ids[i - 1]].noise >= L[ids[i]].noise)
            end
            assert.is_true(L.easy.noise > L.medium.noise and L.medium.noise > 0)
            assert.are.equal(0, L.hard.noise)
            assert.are.equal(0, L.expert.noise)
            for _, id in ipairs(ids) do assert.is_true(L[id].budget <= 2.3) end
        end)

        it("Easy and Medium play legal moves in random positions", function()
            CheckersAI.time_scale = 0.05
            for _, g in ipairs(random_positions(20, 23)) do
                for _, id in ipairs({ "easy", "medium" }) do
                    local m = aiMove(g, id)
                    assert.is_truthy(m)
                    assert.is_true(is_legal(g, m))
                end
            end
        end)

        it("Easy varies between games and is the same under one seed", function()
            local seen, distinct = {}, 0
            for seed = 1, 4 do
                local s = playGame("easy", seed)
                if not seen[s] then seen[s] = true; distinct = distinct + 1 end
            end
            assert.is_true(distinct >= 2, "Easy played the same game every time")
            assert.are.equal(playGame("easy", 42), playGame("easy", 42))
        end)

        it("noise uses the given rng", function()
            for _, g in ipairs(random_positions(10, 29)) do
                local plain = CheckersAI.best_move(g, 3, 100)
                local zero = CheckersAI.best_move(g, 3, 100,
                    { noise = 1000, rng = function() return 0 end })
                assert.are.same(plain, zero)
            end
        end)
    end)

    it("stays within the Expert time budget (generous bound)", function()
        -- 2.5 s on the device; scaled down here, plus slack for one node batch.
        CheckersAI.time_scale = 0.04
        local limit = CheckersAI.BUDGET[9] * 0.04 + 0.05
        local worst = 0
        for _, g in ipairs(random_positions(15, 17)) do
            local t0 = os.clock()
            CheckersAI.best_move(g, 9)
            local dt = os.clock() - t0
            if dt > worst then worst = dt end
        end
        assert.is_true(worst <= limit, string.format("worst %.3f s > %.3f s", worst, limit))
    end)
end)
