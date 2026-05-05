-- Checkers KOReader plugin — main entry point.

local Device      = require("device")
local Screen      = Device.screen
local Blitbuffer  = require("ffi/blitbuffer")
local Dispatcher  = require("dispatcher")
local UIManager   = require("ui/uimanager")
local lfs         = require("libs/libkoreader-lfs")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local util        = require("util")

local FrameContainer  = require("ui/widget/container/framecontainer")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local TitleBarWidget  = require("ui/widget/titlebar")
local ButtonWidget    = require("ui/widget/button")
local ConfirmBox      = require("ui/widget/confirmbox")

local CheckersGame           = require("checkersgame")
local CheckersBoard          = require("checkersboard")
local CheckersAI             = require("checkersai")
local CheckersSettingsWidget = require("checkerssettings")
local _              = require("gettext")

-- ── Icon installation ─────────────────────────────────────────────────────────

local function get_plugin_path()
    local src = debug.getinfo(1, "S").source or ""
    src = src:gsub("^@", "")
    return src:match("^(.*[/\\])main%.lua$") or "."
end

local PLUGIN_PATH = get_plugin_path():gsub("/+$", "")

local function install_icons()
    local data_dir = DataStorage:getDataDir()
    local src_dir  = PLUGIN_PATH .. "/icons"
    local dst_dir  = data_dir .. "/icons/checkers"
    if lfs.attributes(src_dir, "mode") ~= "directory" then return end
    util.makePath(dst_dir)
    for entry in lfs.dir(src_dir) do
        if entry:match("%.svg$") then
            local dst = dst_dir .. "/" .. entry
            if lfs.attributes(dst, "mode") ~= "file" then
                os.execute('cp "' .. src_dir .. "/" .. entry .. '" "' .. dst .. '"')
            end
        end
    end
end

-- ── Plugin widget ─────────────────────────────────────────────────────────────

local Checkers = FrameContainer:extend{
    name        = "checkers",
    background  = Blitbuffer.COLOR_WHITE,
    bordersize  = 0,
    padding     = 0,
    full_width  = Screen:getWidth(),
    full_height = Screen:getHeight(),
    game        = nil,
    board       = nil,
    status_bar  = nil,
    -- human[1]=true means player 1 (black) is human; false = AI.
    human       = { [1] = true, [2] = false },
    ai_depth    = 5,
    settings    = nil,
}

-- ── Settings persistence ──────────────────────────────────────────────────────

function Checkers:loadSettings()
    local path = DataStorage:getSettingsDir() .. "/checkers.lua"
    self.settings = LuaSettings:open(path)
    self.human[1] = self.settings:readSetting("human_black", true)
    self.human[2] = self.settings:readSetting("human_white", false)
    self.ai_depth = self.settings:readSetting("ai_depth",    5)
end

function Checkers:saveSettings()
    if not self.settings then return end
    self.settings:saveSetting("human_black", self.human[1])
    self.settings:saveSetting("human_white", self.human[2])
    self.settings:saveSetting("ai_depth",    self.ai_depth)
    self.settings:flush()
end

-- ── Plugin lifecycle ──────────────────────────────────────────────────────────

function Checkers:onCheckersStart()
    self:startGame()
    return true
end

function Checkers:handleEvent(event)
    if event.handler == "onCheckersStart" then
        return self:onCheckersStart()
    end
    local on_stack = false
    for i = #UIManager._window_stack, 1, -1 do
        if UIManager._window_stack[i].widget == self then
            on_stack = true; break
        end
    end
    if not on_stack then return false end
    return FrameContainer.handleEvent(self, event)
end

function Checkers:init()
    self.covers_fullscreen = true
    Dispatcher:registerAction("checkers_start", {
        category = "none", event = "CheckersStart", title = _("Checkers"), general = true,
    })
    self.ui.menu:registerToMainMenu(self)
    self:loadSettings()
    install_icons()
end

function Checkers:addToMainMenu(menu_items)
    menu_items.checkers = {
        text         = _("Checkers"),
        sorting_hint = "tools",
        callback     = function() self:openSettings() end,
        keep_menu_open = false,
    }
end

-- ── Settings dialog ───────────────────────────────────────────────────────────

function Checkers:openSettings()
    CheckersSettingsWidget:new{
        parent  = self,
        onApply = function(changes)
            self.human[1] = changes.human[1]
            self.human[2] = changes.human[2]
            self.ai_depth = changes.ai_depth
            self:saveSettings()
            self:startGame()
        end,
    }:show()
end

-- ── Game start / reset ────────────────────────────────────────────────────────

function Checkers:startGame()
    if UIManager.isWidgetShown and UIManager:isWidgetShown(self) then
        UIManager:close(self)
    end
    self.game = CheckersGame.new()
    self:buildLayout()
    self.board:updateBoard()
    self:updateStatus()
    UIManager:show(self)
    -- Fire AI immediately if the first player is AI.
    if not self.human[self.game:whose_turn()] then
        self:scheduleAIMove()
    end
end

function Checkers:resetGame()
    self.game               = CheckersGame.new()
    self.board.game         = self.game
    self.board.selected_pos = nil
    self.board.hint_positions = {}
    self.board:updateBoard()
    self:updateStatus()
    UIManager:setDirty(self, "ui")
    if not self.human[self.game:whose_turn()] then
        self:scheduleAIMove()
    end
end

-- ── UI layout ─────────────────────────────────────────────────────────────────

function Checkers:buildLayout()
    local status_bar = self:createStatusBar()
    local status_h   = status_bar:getSize().h

    local toolbar_h   = Screen:scaleBySize(44)
    local pad         = Screen:scaleBySize(8)
    local available_h = self.full_height - status_h - toolbar_h
    local cell        = math.min(
        math.floor((self.full_width - 2*pad) / 8),
        math.floor((available_h    -   pad)  / 8)
    )
    local board_size  = cell * 8 + pad

    self.board = CheckersBoard:new{
        game         = self.game,
        width        = self.full_width,
        height       = board_size,
        moveCallback = function(from, to) self:onMoveExecuted(from, to) end,
    }

    local btn_w  = math.floor(self.full_width / 2)
    local toolbar = HorizontalGroup:new{
        self:_toolbar_btn("chevron.left", btn_w, toolbar_h,
            function() self:doUndo() end),
        self:_toolbar_btn("plus",         btn_w, toolbar_h,
            function() self:openSettings() end),
    }

    local content_h = status_h + board_size + toolbar_h
    local gap       = self.full_height - content_h

    self[1] = VerticalGroup:new{
        align  = "center",
        width  = self.full_width,
        status_bar,
        self.board,
        toolbar,
        gap > 0 and VerticalSpan:new{ width = self.full_width, height = gap } or nil,
    }
    self.status_bar = status_bar
end

function Checkers:_toolbar_btn(icon, w, h, cb)
    return ButtonWidget:new{
        icon        = icon,
        width       = w,
        icon_width  = h,
        icon_height = h,
        padding     = 0,
        margin      = 0,
        bordersize  = 0,
        callback    = cb,
    }
end

-- ── Status bar ────────────────────────────────────────────────────────────────

function Checkers:createStatusBar()
    return TitleBarWidget:new{
        fullscreen              = true,
        title                   = _("Checkers"),
        subtitle                = self:_turn_text(),
        right_icon              = "exit",
        right_icon_size_ratio   = 1.0,
        title_top_padding       = Screen:scaleBySize(2),
        bottom_v_padding        = Screen:scaleBySize(8),
        right_icon_tap_callback = function()
            UIManager:show(ConfirmBox:new{
                text        = _("Exit Checkers?"),
                ok_text     = _("Exit"),
                ok_callback = function()
                    UIManager:close(self, "full")
                end,
            })
        end,
    }
end

function Checkers:_mode_label()
    local b = self.human[1] and "H" or "C"
    local w = self.human[2] and "H" or "C"
    return b .. "v" .. w
end

function Checkers:_turn_text()
    if self.game and self.game:is_over() then
        local winner = self.game:get_winner()
        if     winner == 1 then return _("Black wins!")
        elseif winner == 2 then return _("White wins!")
        else                     return _("Draw!")
        end
    end
    if self.game then
        local turn = self.game:whose_turn()
        local mid  = self.game:is_mid_jump()
        local is_ai = not self.human[turn]
        if turn == 1 then
            if mid     then return _("Black — must continue jump") end
            return is_ai and _("AI thinking…") or _("Black's turn")
        else
            if mid     then return _("White — must continue jump") end
            return is_ai and _("AI thinking…") or _("White's turn")
        end
    end
    return ""
end

function Checkers:updateStatus()
    if self.status_bar then
        self.status_bar:setTitle(
            _("Checkers") .. "  " .. self:_mode_label(),
            true  -- no refresh (we'll batch with setSubTitle)
        )
        self.status_bar:setSubTitle(self:_turn_text())
        UIManager:setDirty(self.status_bar, "ui")
    end
end

-- ── Move handling ─────────────────────────────────────────────────────────────

function Checkers:onMoveExecuted(from, to)
    if self.game:is_over() then
        self:updateStatus()
        self:showGameOver()
        UIManager:setDirty(self, "ui")
        return
    end
    -- Schedule AI response if the current player is AI and the move is complete.
    if not self.human[self.game:whose_turn()] and not self.game:is_mid_jump() then
        self:updateStatus()   -- show "AI thinking…" before the CPU work starts
        UIManager:setDirty(self, "ui")
        self:scheduleAIMove()
    else
        self:updateStatus()
        UIManager:setDirty(self, "ui")
    end
end

-- Yield to the paint loop briefly so "AI thinking…" appears before computation.
function Checkers:scheduleAIMove()
    UIManager:scheduleIn(0.05, function() self:doAIMove() end)
end

-- Apply the full AI move chain (handles multi-jump internally).
function Checkers:doAIMove()
    if self.game:is_over() then return end
    if self.human[self.game:whose_turn()] then return end

    repeat
        local m = CheckersAI.best_move(self.game, self.ai_depth)
        if not m then break end
        self.game:move(m[1], m[2])
    until not self.game:is_mid_jump()

    -- Sync board widget (we bypassed board._execute_move).
    self.board.selected_pos   = nil
    self.board.hint_positions = {}
    self.board:updateBoard()
    self:updateStatus()
    UIManager:setDirty(self, "ui")

    if self.game:is_over() then
        self:showGameOver()
        return
    end

    -- Chain to the next AI if the other player is also AI.
    if not self.human[self.game:whose_turn()] then
        self:scheduleAIMove()
    end
end

-- ── Undo ─────────────────────────────────────────────────────────────────────

function Checkers:doUndo()
    if not self.game:can_undo() then return end
    -- Undo the last move, then keep undoing while an AI player is to move
    -- (so the human is always returned to their own turn).
    self.game:undo()
    while self.game:can_undo() and not self.human[self.game:whose_turn()] do
        self.game:undo()
    end
    self.board:_clear_selection()
    self.board:updateBoard()
    self:updateStatus()
    UIManager:setDirty(self, "ui")
end

function Checkers:askNewGame()
    UIManager:show(ConfirmBox:new{
        text        = _("Start a new game?"),
        ok_text     = _("New Game"),
        ok_callback = function() self:resetGame() end,
    })
end

function Checkers:showGameOver()
    local winner = self.game:get_winner()
    local text
    if     winner == 1 then text = _("Black wins!")
    elseif winner == 2 then text = _("White wins!")
    else                     text = _("Draw — move limit reached.")
    end
    UIManager:show(ConfirmBox:new{
        text        = text,
        ok_text     = _("New Game"),
        cancel_text = _("Close"),
        ok_callback = function() self:resetGame() end,
    })
end

return Checkers
