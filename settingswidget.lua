-- Checkers game settings dialog.
-- Modelled on casualkochess settingswidget.lua.

local Screen      = require("device").screen
local UIManager   = require("ui/uimanager")
local Blitbuffer  = require("ffi/blitbuffer")
local Font        = require("ui/font")
local Geometry    = require("ui/geometry")
local Size        = require("ui/size")

local CenterContainer      = require("ui/widget/container/centercontainer")
local FrameContainer       = require("ui/widget/container/framecontainer")
local MovableContainer     = require("ui/widget/container/movablecontainer")
local InputDialog          = require("ui/widget/inputdialog")
local RadioButtonTable     = require("ui/widget/radiobuttontable")
local ButtonProgressWidget = require("ui/widget/buttonprogresswidget")
local TextWidget           = require("ui/widget/textwidget")
local VerticalGroup        = require("ui/widget/verticalgroup")
local VerticalSpan         = require("ui/widget/verticalspan")

local _ = require("gettext")

-- ── Difficulty presets ────────────────────────────────────────────────────────

local PRESETS = {
    { label = _("Easy"),   depth = 3 },
    { label = _("Medium"), depth = 5 },
    { label = _("Hard"),   depth = 7 },
    { label = _("Expert"), depth = 9 },
}

local function depth_to_pos(depth)
    for i, p in ipairs(PRESETS) do
        if p.depth >= depth then return i end
    end
    return #PRESETS
end

-- ── Widget ────────────────────────────────────────────────────────────────────

local SettingsWidget = {}
SettingsWidget.__index = SettingsWidget

function SettingsWidget:new(opts)
    assert(opts.parent,   "parent is required")
    assert(opts.onApply,  "onApply callback is required")
    return setmetatable({
        parent  = opts.parent,
        onApply = opts.onApply,
        dialog  = nil,
        changes = {
            human    = { [1] = opts.parent.human[1], [2] = opts.parent.human[2] },
            ai_depth = opts.parent.ai_depth,
        },
    }, SettingsWidget)
end

-- ── Section builders ──────────────────────────────────────────────────────────

function SettingsWidget:buildPlayerSection()
    local w = self.dialog.element_width

    local function makeRow(player, label_text)
        local radios = RadioButtonTable:new{
            width = w,
            radio_buttons = {{
                { text = _("Human"), checked =     self.changes.human[player],
                  player = player, is_human = true  },
                { text = _("AI"),    checked = not self.changes.human[player],
                  player = player, is_human = false },
            }},
            button_select_callback = function(entry)
                self.changes.human[entry.player] = entry.is_human
            end,
            parent = self.dialog,
        }
        return VerticalGroup:new{
            width = w,
            TextWidget:new{ text = label_text, face = Font:getFace("cfont", 22) },
            VerticalSpan:new{ width = Size.padding.small },
            radios,
        }
    end

    self.playerSection = VerticalGroup:new{
        width = w,
        makeRow(1, _("Black:")),
        VerticalSpan:new{ width = Size.padding.large },
        makeRow(2, _("White:")),
    }
end

function SettingsWidget:buildDifficultySection()
    local w   = self.dialog.element_width
    local pos = depth_to_pos(self.changes.ai_depth)

    self.difficultyLabel = TextWidget:new{
        text = _("Difficulty: ") .. PRESETS[pos].label,
        face = Font:getFace("cfont", 22),
    }

    self.difficultyProgress = ButtonProgressWidget:new{
        width       = w,
        num_buttons = #PRESETS,
        position    = pos,
        fine_tune   = false,
        callback    = function(new_pos)
            if type(new_pos) ~= "number" then return end
            self.changes.ai_depth = PRESETS[new_pos].depth
            self.difficultyProgress.position = new_pos
            self.difficultyLabel:setText(_("Difficulty: ") .. PRESETS[new_pos].label)
            UIManager:setDirty(self.dialog, "ui")
        end,
    }

    self.difficultySection = VerticalGroup:new{
        width = w,
        self.difficultyLabel,
        VerticalSpan:new{ width = Size.padding.small },
        self.difficultyProgress,
    }
end

function SettingsWidget:assembleContent()
    local D = self.dialog
    local content = FrameContainer:new{
        radius     = Size.radius.window,
        bordersize = Size.border.window,
        background = Blitbuffer.COLOR_WHITE,
        padding    = 0,
        margin     = 0,
        VerticalGroup:new{
            align = "left",
            D.title_bar,

            VerticalSpan:new{ width = Size.padding.large },

            CenterContainer:new{
                dimen = Geometry:new{ w = D.width, h = self.playerSection:getSize().h },
                self.playerSection,
            },

            VerticalSpan:new{ width = Size.padding.large },

            CenterContainer:new{
                dimen = Geometry:new{ w = D.width, h = self.difficultySection:getSize().h },
                self.difficultySection,
            },

            VerticalSpan:new{ width = Size.padding.large },

            CenterContainer:new{
                dimen = Geometry:new{
                    w = D.title_bar:getSize().w,
                    h = D.button_table:getSize().h,
                },
                D.button_table,
            },

            VerticalSpan:new{ width = Size.padding.small },
        },
    }
    D.movable = MovableContainer:new{ content }
    D[1] = CenterContainer:new{ dimen = Screen:getSize(), D.movable }
end

-- ── Public ────────────────────────────────────────────────────────────────────

function SettingsWidget:show()
    local dlg = InputDialog:new{
        title            = _("New Game"),
        dismiss_callback = function() UIManager:close(self.dialog) end,
        buttons          = {{
            { text = _("Cancel"), callback = function() UIManager:close(self.dialog) end },
            { text = _("Start"),  callback = function() self:applyAndClose() end },
        }},
    }
    dlg.element_width = math.floor(dlg.width * 0.8)
    self.dialog = dlg

    self:buildPlayerSection()
    self:buildDifficultySection()
    self:assembleContent()

    UIManager:show(dlg)
end

function SettingsWidget:applyAndClose()
    self.onApply(self.changes)
    UIManager:close(self.dialog)
end

return SettingsWidget
