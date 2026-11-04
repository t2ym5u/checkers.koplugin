-- ---------------------------------------------------------------------------
-- CheckersBoardWidget — draws the 8x8 board and the pieces
--
-- Greyscale and high contrast for e-ink: light and dark squares in the same
-- greys as Chess, flat round pieces (white with a black rim, or black), a
-- crown on kings. The selected piece is ringed and the squares it can reach
-- carry a dot; the squares the last move went through are shaded lighter.
-- `flipped` turns the board so White sits at the bottom.
-- ---------------------------------------------------------------------------

local Blitbuffer = require("ffi/blitbuffer")
local Geom       = require("ui/geometry")

local gwb            = require("grid_widget_base")
local GridWidgetBase = gwb.GridWidgetBase
local drawLine       = gwb.drawLine

local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end
local CheckersGame = lrequire("checkersgame")

local C_LIGHT   = Blitbuffer.COLOR_GRAY_E   -- light squares (not played on)
local C_DARK    = Blitbuffer.COLOR_GRAY_9   -- dark squares (the playing ones)
local C_LAST    = Blitbuffer.COLOR_GRAY_B   -- squares of the last move
local C_BORDER  = Blitbuffer.COLOR_BLACK
local C_INK     = Blitbuffer.COLOR_BLACK
local C_PAPER   = Blitbuffer.COLOR_WHITE

local CheckersBoardWidget = GridWidgetBase:extend{
    board        = nil,    -- CheckersGame
    size_ratio   = 0.82,
    flipped      = false,  -- true: White at the bottom
    highlight    = nil,    -- function() -> { selected = pos, targets = set }
    onCellAction = nil,    -- function(pos)
}

function CheckersBoardWidget:init()
    self.cols = 8
    self.rows = 8
    GridWidgetBase.init(self)
end

-- Visual cell <-> square, taking the flip into account.
function CheckersBoardWidget:_toBoard(r, c)
    if self.flipped then return 9 - r, 9 - c end
    return r, c
end

function CheckersBoardWidget:onCellTap(row, col)
    local pos = CheckersGame.rc_to_pos(self:_toBoard(row, col))
    if self.onCellAction then self.onCellAction(pos) end
end

-- Even-odd scanline fill of a polygon given as {x1, y1, x2, y2, ...}.
local function fillPolygon(bb, pts, color)
    local n = #pts / 2
    local ymin, ymax = math.huge, -math.huge
    for i = 1, n do
        local y = pts[2 * i]
        if y < ymin then ymin = y end
        if y > ymax then ymax = y end
    end
    for y = math.floor(ymin), math.ceil(ymax) - 1 do
        local yc = y + 0.5
        local xs = {}
        for i = 1, n do
            local x1, y1 = pts[2 * i - 1], pts[2 * i]
            local j = (i % n) + 1
            local x2, y2 = pts[2 * j - 1], pts[2 * j]
            if (y1 <= yc and y2 > yc) or (y2 <= yc and y1 > yc) then
                xs[#xs + 1] = x1 + (yc - y1) * (x2 - x1) / (y2 - y1)
            end
        end
        table.sort(xs)
        for k = 1, #xs - 1, 2 do
            local xa = math.floor(xs[k] + 0.5)
            local xb = math.floor(xs[k + 1] + 0.5)
            if xb > xa then bb:paintRect(xa, y, xb - xa, 1, color) end
        end
    end
end

-- Crown outline, in units of the piece radius around its centre.
local CROWN = {
    -0.52,  0.34,   0.52,  0.34,   0.52, -0.30,   0.26,  0.02,
     0.00, -0.40,  -0.26,  0.02,  -0.52, -0.30,
}

local function drawPiece(bb, cx, cy, r, player, king, ring)
    local body, mark = C_INK, C_PAPER
    if player == 2 then body, mark = C_PAPER, C_INK end
    bb:paintCircle(cx, cy, r, body)
    if player == 2 then bb:paintCircle(cx, cy, r, C_INK, ring) end
    if king then
        local pts = {}
        for i = 1, #CROWN, 2 do
            pts[i]     = cx + CROWN[i] * r
            pts[i + 1] = cy + CROWN[i + 1] * r
        end
        fillPolygon(bb, pts, mark)
    else
        -- An inner rim, as on a real draughts piece.
        bb:paintCircle(cx, cy, math.floor(r * 0.62), mark, math.max(1, math.floor(ring * 0.6)))
    end
end

function CheckersBoardWidget:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.dimen.w, h = self.dimen.h }
    local game = self.board
    local cw, ch = self.cell_w, self.cell_h
    local cell = math.min(cw, ch)
    local hl = self.highlight and self.highlight() or {}
    local targets = hl.targets or {}

    local last = {}
    for _, pos in ipairs(game.last_path or {}) do last[pos] = true end

    local piece_r = math.floor(cell * 0.37)
    local ring    = math.max(2, math.floor(cell * 0.05))

    for vr = 1, 8 do
        for vc = 1, 8 do
            local cx0 = x + math.floor((vc - 1) * cw)
            local cy0 = y + math.floor((vr - 1) * ch)
            local cew = math.floor(vc * cw) - math.floor((vc - 1) * cw)
            local ceh = math.floor(vr * ch) - math.floor((vr - 1) * ch)
            local pos = CheckersGame.rc_to_pos(self:_toBoard(vr, vc))
            local bg = C_LIGHT
            if pos then bg = last[pos] and C_LAST or C_DARK end
            bb:paintRect(cx0, cy0, cew, ceh, bg)

            if pos then
                local cx = cx0 + math.floor(cew / 2)
                local cy = cy0 + math.floor(ceh / 2)
                local piece = game:get_piece_at(pos)
                if piece then
                    if hl.selected == pos then
                        -- A black ring with a white gap: visible on any square.
                        bb:paintCircle(cx, cy, piece_r + 2 * ring, C_INK, ring)
                        bb:paintCircle(cx, cy, piece_r + ring, C_PAPER, ring)
                    end
                    drawPiece(bb, cx, cy, piece_r, piece.player, piece.king, ring)
                elseif targets[pos] then
                    local dr = math.max(4, math.floor(cell * 0.15))
                    bb:paintCircle(cx, cy, dr, C_PAPER)
                    bb:paintCircle(cx, cy, dr, C_INK, ring)
                end
            end
        end
    end

    -- Thick outer border, drawn inside the widget.
    local thick = math.max(2, math.floor(cell * 0.06))
    drawLine(bb, x, y, thick, self.dimen.h, C_BORDER)
    drawLine(bb, x + self.dimen.w - thick, y, thick, self.dimen.h, C_BORDER)
    drawLine(bb, x, y, self.dimen.w, thick, C_BORDER)
    drawLine(bb, x, y + self.dimen.h - thick, self.dimen.w, thick, C_BORDER)
end

return CheckersBoardWidget
