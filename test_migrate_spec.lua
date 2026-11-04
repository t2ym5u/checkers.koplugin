local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.path = DIR .. "?.lua;" .. package.path

describe("Migrate", function()
    local Migrate

    setup(function()
        Migrate = require("migrate")
    end)

    -- Minimal LuaSettings stand-in.
    local function fake_settings(data)
        local s = { data = data, flushed = false }
        function s:readSetting(k) return self.data[k] end
        function s:saveSetting(k, v) self.data[k] = v end
        function s:delSetting(k) self.data[k] = nil end
        function s:flush() self.flushed = true end
        return s
    end

    it("has nothing to do without legacy settings", function()
        assert.is_nil(Migrate.fromLegacy{})
        local s = fake_settings{ players = 2 }
        assert.is_false(Migrate.apply(s))
        assert.are.same({ players = 2 }, s.data)
    end)

    it("maps the old sides to players and colour", function()
        assert.are.same({ players = 1, player_color = "black", difficulty = "medium" },
            Migrate.fromLegacy{ human_black = true, human_white = false, ai_depth = 5 })
        assert.are.same({ players = 1, player_color = "white", difficulty = "medium" },
            Migrate.fromLegacy{ human_black = false, human_white = true, ai_depth = 5 })
        assert.are.same({ players = 2, player_color = "black", difficulty = "medium" },
            Migrate.fromLegacy{ human_black = true, human_white = true, ai_depth = 5 })
        -- Computer vs computer is gone: the player gets Black against the AI.
        assert.are.same({ players = 1, player_color = "black", difficulty = "medium" },
            Migrate.fromLegacy{ human_black = false, human_white = false, ai_depth = 5 })
    end)

    it("maps the four old depths to the four levels", function()
        local function diff(d) return Migrate.fromLegacy{ ai_depth = d }.difficulty end
        assert.are.equal("easy", diff(3))
        assert.are.equal("medium", diff(5))
        assert.are.equal("hard", diff(7))
        assert.are.equal("expert", diff(9))
    end)

    it("writes the new keys, drops the old ones, and runs once", function()
        local s = fake_settings{ human_black = false, human_white = true, ai_depth = 9 }
        assert.is_true(Migrate.apply(s))
        assert.is_true(s.flushed)
        assert.are.same({ players = 1, player_color = "white", difficulty = "expert" }, s.data)
        assert.is_false(Migrate.apply(s))
    end)

    it("never overwrites a setting already chosen in this version", function()
        local s = fake_settings{ ai_depth = 9, difficulty = "easy" }
        Migrate.apply(s)
        assert.are.equal("easy", s.data.difficulty)
        assert.is_nil(s.data.ai_depth)
    end)
end)
