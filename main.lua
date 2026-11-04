local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = _dir .. "?.lua;" .. _dir .. "common/?.lua;" .. package.path

local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local PluginBase = require("plugin_base")
local _          = require("i18n")

require("i18n").extend(lrequire("i18n_fr"))
local CheckersScreen = lrequire("screen")
local Migrate        = lrequire("migrate")

-- ---------------------------------------------------------------------------
-- CheckersPlugin
-- ---------------------------------------------------------------------------

local CheckersPlugin = PluginBase:extend{
    name      = "checkers",
    menu_text = _("Checkers"),
    menu_hint = "tools",
}

function CheckersPlugin:init()
    PluginBase.init(self)
    -- Preferences from 1.2.0 and earlier, kept in this same settings file.
    pcall(Migrate.apply, self.settings)
end

function CheckersPlugin:createScreen()
    return CheckersScreen:new{ plugin = self }
end

return CheckersPlugin
