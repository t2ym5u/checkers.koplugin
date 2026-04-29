-- Checkers board widget — adapted from casualkochess board.lua
-- Renders an 8×8 grid; only the 32 dark squares are interactive.

local Geom        = require("ui/geometry")
local Blitbuffer  = require("ffi/blitbuffer")
local ButtonTable = require("buttontable")
local Device      = require("device")
local Screen      = Device.screen
local UIManager   = require("ui/uimanager")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local IconWidget   = require("ui/widget/iconwidget")

local BOARD_SIZE = 8
local BOARD_W    = 4   -- dark squares per row
local SEL_BORDER = 5   -- selection border thickness (pixels, before scaling)

-- ── Pre-compute position ↔ visual (rank, file) mapping ──────────────────────
-- Position 1-32 numbers the dark squares row-by-row, 4 per row.
-- Dark squares: (rank + file) % 2 == 1
--   even rank → dark files 1,3,5,7  → lib_col = (file-1)/2
--   odd  rank → dark files 0,2,4,6  → lib_col = file/2

local _pos_layout = {}   -- _pos_layout[row][col] = position 1-32
local pos_to_visual = {} -- pos_to_visual[pos]  = {rank=r, file=f}
local visual_to_pos = {} -- visual_to_pos[rank][file] = pos (nil for light)
do
    local p = 1
    for row = 0, BOARD_SIZE - 1 do
        _pos_layout[row] = {}
        visual_to_pos[row] = {}
        for col = 0, BOARD_W - 1 do
            _pos_layout[row][col] = p
            local f = (row % 2 == 0) and (col * 2 + 1) or (col * 2)
            pos_to_visual[p]        = {rank = row, file = f}
            visual_to_pos[row][f]   = p
            p = p + 1
        end
    end
end

local function sq_id(rank, file) return rank * BOARD_SIZE + file + 1 end

-- ── Icon names ───────────────────────────────────────────────────────────────
local ICON_EMPTY  = "checkers/empty"
local ICONS = {
    [1] = { man = "checkers/black",       king = "checkers/black_king" },
    [2] = { man = "checkers/white",       king = "checkers/white_king" },
}

-- ── Overlay helpers (identical pattern to chess board) ───────────────────────
local OVERLAY_ORDER = {"previous", "selected", "hint"}

local function new_overlay_icon(name, w, h)
    return IconWidget:new{ icon = name, alpha = true, width = w, height = h }
end

local function rebuild_overlay(og)
    for i = #og, 2, -1 do og[i] = nil end
    for _, purpose in ipairs(OVERLAY_ORDER) do
        local name = og._icons[purpose]
        if name then og[#og+1] = new_overlay_icon(name, og._w, og._h) end
    end
end

local function overlay_icon(button, purpose, icon_name, w, h)
    local lc = button.frame[1]; if not lc then return end
    local orig = lc[1];          if not orig then return end
    local og = orig
    if not og._is_overlay then
        og = OverlapGroup:new{ dimen = Geom:new{w=w, h=h}, orig }
        og._is_overlay = true
        og._orig       = orig
        og._icons      = {}
        og._w, og._h   = w, h
        lc[1] = og
    end
    og._icons[purpose] = icon_name
    rebuild_overlay(og)
end

local function clear_overlay(button, purpose)
    local lc = button.frame[1]; if not lc then return end
    local og = lc[1]
    if not (og and og._is_overlay) then return end
    if purpose then
        og._icons[purpose] = nil
    else
        og._icons = {}
    end
    for _, p in ipairs(OVERLAY_ORDER) do
        if og._icons[p] then
            rebuild_overlay(og)
            return
        end
    end
    lc[1] = og._orig
end

-- ── Board widget ─────────────────────────────────────────────────────────────

local Board = FrameContainer:extend{
    game         = nil,
    width        = 300,
    height       = 300,
    moveCallback = nil,
    bordersize   = 0,
    padding      = 0,
    background   = Blitbuffer.COLOR_WHITE,
    selected_pos  = nil,
    hint_positions = nil,
    _cell        = 0,
    _icon_h      = 0,
}

function Board:getSize()
    -- Set the padding fields that FrameContainer:paintTo() reads after calling getSize().
    -- Our override skips FrameContainer:getSize() so we must set them manually.
    self._padding_top    = self.padding_top    or self.padding
    self._padding_right  = self.padding_right  or self.padding
    self._padding_bottom = self.padding_bottom or self.padding
    self._padding_left   = self.padding_left   or self.padding
    return Geom:new{ x=0, y=0, w=self.width, h=self.height }
end

function Board:init()
    if not self.game then error("CheckersBoard: must be initialised with a game") end

    local pad    = Screen:scaleBySize(8)
    local cell   = math.min(
        math.floor((self.width  - 2*pad) / BOARD_SIZE),
        math.floor((self.height -   pad) / BOARD_SIZE)
    )
    self._cell   = cell
    self._icon_h = cell - Screen:scaleBySize(4) * 2  -- match chess's bt_pad_v=4 convention

    self.selected_pos   = nil
    self.hint_positions = {}

    -- Build 8×8 grid of button specs
    local grid = {}
    for rank = 0, BOARD_SIZE - 1 do
        local row = {}
        for file = 0, BOARD_SIZE - 1 do
            row[#row+1] = self:_make_button_spec(rank, file)
        end
        grid[#grid+1] = row
    end

    local table_size = cell * BOARD_SIZE
    self.btable = ButtonTable:new{
        width                 = table_size,
        buttons               = grid,
        shrink_unneeded_width = false,
        zero_sep              = true,
        sep_width             = 0,
        addVerticalSpan       = function() end,
    }

    self:_apply_square_colors()

    self[1] = FrameContainer:new{
        bordersize     = 0,
        background     = self.background,
        padding        = 0,
        padding_top    = pad,
        CenterContainer:new{
            dimen = Geom:new{ w = self.width, h = cell * BOARD_SIZE + pad },
            self.btable,
        },
    }
end

function Board:_make_button_spec(rank, file)
    local is_dark = (rank + file) % 2 == 1
    local spec = {
        id          = sq_id(rank, file),
        icon        = ICON_EMPTY,
        alpha       = true,
        width       = self._cell,
        icon_width  = self._cell,
        icon_height = self._icon_h,
        bordersize  = Screen:scaleBySize(SEL_BORDER),
        margin      = 0,
        padding     = 0,
    }
    if is_dark then
        spec.callback = function() self:handleClick(rank, file) end
    end
    return spec
end

function Board:_apply_square_colors()
    for rank = 0, BOARD_SIZE - 1 do
        for file = 0, BOARD_SIZE - 1 do
            local btn   = self.btable:getButtonById(sq_id(rank, file))
            local color = (rank + file) % 2 == 1
                and Blitbuffer.COLOR_DARK_GRAY
                or  Blitbuffer.COLOR_LIGHT_GRAY
            btn.frame.background  = color
            btn.frame.border_color = color
        end
    end
end

-- ── Click handling ────────────────────────────────────────────────────────────

function Board:handleClick(rank, file)
    local pos = visual_to_pos[rank] and visual_to_pos[rank][file]
    if not pos then return end

    local game = self.game
    if game:is_over() then return end

    if game:is_mid_jump() then
        -- Forced continuation: only accept the valid jump target.
        local from_pos = game:get_mid_jump_piece_pos()
        local valid = game:get_moves_for_piece(from_pos)
        for _, m in ipairs(valid) do
            if m[2] == pos then self:_execute_move(from_pos, pos); return end
        end
        return
    end

    local piece     = game:get_piece_at(pos)
    local friendly  = piece and piece.player == game:whose_turn()

    if self.selected_pos then
        if pos == self.selected_pos then
            self:_clear_selection()
        elseif friendly then
            self:_clear_selection()
            self:_select(pos)
        else
            -- Try executing the move.
            local valid = game:get_moves_for_piece(self.selected_pos)
            local ok = false
            for _, m in ipairs(valid) do
                if m[2] == pos then ok = true; break end
            end
            if ok then
                self:_execute_move(self.selected_pos, pos)
            else
                self:_clear_selection()
            end
        end
    else
        if friendly then self:_select(pos) end
    end
end

function Board:_select(pos)
    self.selected_pos = pos
    self:_mark_selected(pos)
    self:_mark_hints(pos)
end

function Board:_clear_selection()
    if self.selected_pos then
        self:_unmark_selected(self.selected_pos)
        self.selected_pos = nil
    end
    self:clearValidMoves()
end

function Board:_execute_move(from_pos, to_pos)
    self:_clear_selection()
    local ok = self.game:move(from_pos, to_pos)
    if not ok then return end
    self:updateBoard()
    -- Auto-select the piece if still mid-jump.
    if self.game:is_mid_jump() then
        local jp = self.game:get_mid_jump_piece_pos()
        self:_select(jp)
    end
    if self.moveCallback then self.moveCallback(from_pos, to_pos) end
end

-- ── Visual updates ────────────────────────────────────────────────────────────

function Board:updateBoard()
    for pos = 1, 32 do self:updateSquare(pos) end
    UIManager:setDirty(self, "ui")
end

function Board:updateSquare(pos)
    local v = pos_to_visual[pos]; if not v then return end
    local piece = self.game:get_piece_at(pos)
    local btn   = self.btable:getButtonById(sq_id(v.rank, v.file))
    local icon
    if piece then
        local icons = ICONS[piece.player]
        icon = piece.king and icons.king or icons.man
    else
        icon = ICON_EMPTY
    end
    btn:setIcon(icon, self._cell)
    -- Restore square background (setIcon re-inits the button frame).
    local color = (v.rank + v.file) % 2 == 1
        and Blitbuffer.COLOR_DARK_GRAY
        or  Blitbuffer.COLOR_LIGHT_GRAY
    btn.frame.background   = color
    btn.frame.border_color = color
end

function Board:_mark_selected(pos)
    local v = pos_to_visual[pos]; if not v then return end
    local btn = self.btable:getButtonById(sq_id(v.rank, v.file))
    overlay_icon(btn, "selected", "checkers/select", self._cell, self._icon_h)
    UIManager:setDirty("all", "ui")
end

function Board:_unmark_selected(pos)
    local v = pos_to_visual[pos]; if not v then return end
    local btn = self.btable:getButtonById(sq_id(v.rank, v.file))
    clear_overlay(btn, "selected")
    UIManager:setDirty("all", "ui")
end

function Board:_mark_hints(pos)
    self.hint_positions = {}
    local moves = self.game:get_moves_for_piece(pos)
    for _, m in ipairs(moves) do
        local tp  = m[2]
        local v   = pos_to_visual[tp]; if not v then goto continue end
        local btn = self.btable:getButtonById(sq_id(v.rank, v.file))
        overlay_icon(btn, "hint", "checkers/hint", self._cell, self._icon_h)
        self.hint_positions[#self.hint_positions+1] = tp
        ::continue::
    end
    UIManager:setDirty("all", "ui")
end

function Board:clearValidMoves()
    if not self.hint_positions then return end
    for _, tp in ipairs(self.hint_positions) do
        local v = pos_to_visual[tp]; if not v then goto continue end
        local btn = self.btable:getButtonById(sq_id(v.rank, v.file))
        clear_overlay(btn, "hint")
        ::continue::
    end
    self.hint_positions = {}
    UIManager:setDirty("all", "ui")
end

return Board
