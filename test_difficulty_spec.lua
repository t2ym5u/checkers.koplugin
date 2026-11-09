-- Difficulty guarantees of the Checkers computer opponent: the level table
-- is ordered, every level plays legal moves, takes a move that wins at once
-- and (from Medium up) does not hand the opponent one, Easy varies with the
-- seed and replays under the same one, and each level stays within its
-- think time at Kobo speed. No full matches.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.path = DIR .. "?.lua;" .. package.path

describe("Checkers difficulty", function()
    local CheckersGame, CheckersAI

    setup(function()
        CheckersGame = require("checkersgame")
        CheckersAI   = require("checkersai")
    end)

    after_each(function()
        CheckersAI.time_scale = 1
    end)

    local IDS = { "easy", "medium", "hard", "expert" }

    local function is_legal(game, m)
        for _, l in ipairs(game:get_possible_moves()) do
            if l[1] == m[1] and l[2] == m[2] then return true end
        end
        return false
    end

    local function aiMove(g, id)
        local L = CheckersAI.LEVELS[id]
        return CheckersAI.best_move(g, L.depth, L.budget, L)
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

    -- Moves of the side to move that end the game at once in its favour.
    local function winning_moves(g)
        local p, out = g:whose_turn(), {}
        for _, m in ipairs(g:get_possible_moves()) do
            g:move(m[1], m[2])
            if not g:is_mid_jump() and g:get_winner() == p then out[#out + 1] = m end
            g:undo()
        end
        return out
    end

    -- Seeded random games, scanned for positions (not mid-jump, every move
    -- ends the turn) where some moves let the opponent win at once and at
    -- least one does not. Returns { game, safe = {"f-t" = true} }.
    local function threat_positions(want, seed)
        math.randomseed(seed)
        local out = {}
        for _ = 1, 400 do
            local g = CheckersGame.new()
            for _ = 1, 150 do
                if g:is_over() or #out >= want then break end
                if not g:is_mid_jump() and #winning_moves(g) == 0 then
                    local safe, unsafe, clean = {}, 0, true
                    for _, m in ipairs(g:get_possible_moves()) do
                        g:move(m[1], m[2])
                        if g:is_mid_jump() then clean = false
                        elseif #winning_moves(g) > 0 then unsafe = unsafe + 1
                        else safe[m[1] .. "-" .. m[2]] = true end
                        g:undo()
                    end
                    if clean and unsafe > 0 and next(safe) then
                        out[#out + 1] = { game = g:clone(), safe = safe }
                    end
                end
                local ms = g:get_possible_moves()
                local m = ms[math.random(#ms)]
                g:move(m[1], m[2])
            end
            if #out >= want then break end
        end
        return out
    end

    -- The first moves of a game, every move from `id`, the rng seeded (a
    -- short line, not a whole match).
    local function playLine(id, seed)
        math.randomseed(seed)
        local g = CheckersGame.new()
        local out = {}
        for _ = 1, 30 do
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
        for i = 2, #IDS do
            assert.is_true(L[IDS[i - 1]].depth < L[IDS[i]].depth)
            assert.is_true(L[IDS[i - 1]].noise >= L[IDS[i]].noise)
            assert.is_true(L[IDS[i - 1]].budget <= L[IDS[i]].budget)
        end
        assert.is_true(L.easy.noise > L.medium.noise and L.medium.noise > 0)
        assert.are.equal(0, L.hard.noise)
        assert.are.equal(0, L.expert.noise)
        for _, id in ipairs(IDS) do assert.is_true(L[id].budget <= 2.3) end
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

    it("every level takes a move that wins at once, in random positions", function()
        CheckersAI.time_scale = 0.04
        math.randomseed(19)
        local checked = 0
        for _ = 1, 400 do
            if checked >= 8 then break end
            local g = CheckersGame.new()
            for _ = 1, 150 do
                if g:is_over() then break end
                if not g:is_mid_jump() and #g:get_possible_moves() > 1
                        and #winning_moves(g) > 0 then
                    local p = g:whose_turn()
                    for _, id in ipairs(IDS) do
                        local m = aiMove(g, id)
                        g:move(m[1], m[2])
                        assert.are.equal(p, g:get_winner(), id .. " missed a win")
                        g:undo()
                    end
                    checked = checked + 1
                    break
                end
                local ms = g:get_possible_moves()
                local m = ms[math.random(#ms)]
                g:move(m[1], m[2])
            end
        end
        assert.is_true(checked >= 4, "only " .. checked .. " positions found")
    end)

    it("Medium and up never hand the opponent a win in one", function()
        CheckersAI.time_scale = 0.04
        local positions = threat_positions(8, 41)
        assert.is_true(#positions >= 4, "only " .. #positions .. " positions found")
        for _, pos in ipairs(positions) do
            for seed, id in ipairs({ "medium", "hard", "expert" }) do
                math.randomseed(seed)
                local m = aiMove(pos.game, id)
                assert.is_true(pos.safe[m[1] .. "-" .. m[2]] ~= nil,
                    id .. " handed over a win with " .. m[1] .. "-" .. m[2])
            end
        end
    end)

    it("Easy varies between games and is the same under one seed", function()
        local seen, distinct = {}, 0
        for seed = 1, 4 do
            local s = playLine("easy", seed)
            if not seen[s] then seen[s] = true; distinct = distinct + 1 end
        end
        assert.is_true(distinct >= 2, "Easy played the same game every time")
        assert.are.equal(playLine("easy", 42), playLine("easy", 42))
    end)

    it("noise uses the given rng", function()
        for _, g in ipairs(random_positions(10, 29)) do
            local plain = CheckersAI.best_move(g, 3, 100)
            local zero = CheckersAI.best_move(g, 3, 100,
                { noise = 1000, rng = function() return 0 end })
            assert.are.same(plain, zero)
        end
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

    it("keeps every level within its budget at Kobo speed", function()
        CheckersAI.time_scale = 0.04
        local worst = 0
        for _, g in ipairs(random_positions(6, 31)) do
            for _, id in ipairs(IDS) do
                local t0 = os.clock()
                aiMove(g, id)
                local dt = (os.clock() - t0) * 25
                if dt > worst then worst = dt end
            end
        end
        assert.is_true(worst <= 2.5, string.format("slowest Kobo move %.2f s", worst))
    end)
end)
