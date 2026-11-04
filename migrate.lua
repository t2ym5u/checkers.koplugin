-- ---------------------------------------------------------------------------
-- Settings left by checkers 1.2.0 and earlier (kbarni's original UI).
--
-- They live in the same settings/checkers.lua that PluginBase now uses, as
--   human_black, human_white  (booleans: is that side a human?)
--   ai_depth                  (3, 5, 7 or 9: Easy, Medium, Hard, Expert)
-- That version never saved a game in progress, so only these preferences
-- carry over.
-- ---------------------------------------------------------------------------

local Migrate = {}

Migrate.LEGACY_KEYS = { "human_black", "human_white", "ai_depth" }

local function difficulty_for(depth)
    if type(depth) ~= "number" then return "medium" end
    if depth <= 3 then return "easy" end
    if depth <= 5 then return "medium" end
    if depth <= 7 then return "hard" end
    return "expert"
end

-- old: the legacy values (any may be nil). Returns the new settings
-- { players, player_color, difficulty }, or nil when there is nothing to
-- migrate.
function Migrate.fromLegacy(old)
    if old.human_black == nil and old.human_white == nil and old.ai_depth == nil then
        return nil
    end
    local hb = old.human_black
    local hw = old.human_white
    if hb == nil then hb = true end
    if hw == nil then hw = false end
    local new = { difficulty = difficulty_for(old.ai_depth) }
    if hb and hw then
        new.players, new.player_color = 2, "black"
    elseif hw then
        new.players, new.player_color = 1, "white"
    else
        -- Human Black, or the old computer-vs-computer mode, which is gone.
        new.players, new.player_color = 1, "black"
    end
    return new
end

-- settings: a LuaSettings object. Migrates once, then drops the old keys.
-- Settings already written by this version are never overwritten.
function Migrate.apply(settings)
    local old = {}
    for _, k in ipairs(Migrate.LEGACY_KEYS) do old[k] = settings:readSetting(k) end
    local new = Migrate.fromLegacy(old)
    if not new then return false end
    for k, v in pairs(new) do
        if settings:readSetting(k) == nil then settings:saveSetting(k, v) end
    end
    for _, k in ipairs(Migrate.LEGACY_KEYS) do settings:delSetting(k) end
    settings:flush()
    return true
end

return Migrate
