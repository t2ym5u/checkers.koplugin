-- ---------------------------------------------------------------------------
-- CheckersScreen — English draughts, against the AI or two players
-- ---------------------------------------------------------------------------

local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local MenuHelper  = require("menu_helper")
local ScreenBase  = require("screen_base")

local CheckersGame        = lrequire("checkersgame")
local CheckersAI          = lrequire("checkersai")
local CheckersBoardWidget = lrequire("board_widget")

local GAME_RULES_EN = _([[
Checkers (English draughts) — Rules

Each player has 12 pieces on the dark squares. Black plays first.

• A piece moves one square diagonally forward, onto an empty dark square. Tap it, then where it goes.
• Capture by jumping over an opponent piece next to yours onto the empty square just beyond it. The jumped piece is removed.
• Capturing is compulsory: when you can capture, you must, but you may choose which capture.
• After a jump, if the same piece can jump again, it must keep jumping in the same turn.
• A piece that reaches the far row becomes a king (shown with a crown). If that happens during a capture, the turn ends there.
• A king moves and captures one square diagonally, forwards or backwards.

You win when your opponent has no pieces left or cannot move. After 40 moves in a row without a capture (20 each), the game is drawn.
]])

local GAME_RULES_FR = [[
Dames anglaises — Règles

Chaque joueur a 12 pions sur les cases foncées. Les Noirs commencent.

• Un pion avance d'une case en diagonale, vers une case foncée libre. Touchez-le, puis sa destination.
• On prend en sautant par-dessus un pion adverse voisin, vers la case libre juste derrière. Le pion sauté est retiré.
• La prise est obligatoire : quand vous pouvez prendre, vous devez le faire, mais vous choisissez quelle prise.
• Après un saut, si le même pion peut encore sauter, il doit continuer dans le même tour.
• Un pion qui atteint la dernière rangée devient une dame (marquée d'une couronne). Si cela arrive pendant une prise, le tour s'arrête là.
• Une dame se déplace et prend d'une case en diagonale, en avant comme en arrière.

Vous gagnez quand l'adversaire n'a plus de pions ou ne peut plus bouger. Après 40 coups d'affilée sans prise (20 chacun), la partie est nulle.
]]

-- Difficulty -> maximum search depth. The thinking time per level is
-- CheckersAI.BUDGET (Easy 0.5 s ... Expert 2.5 s on a Kobo-class reader).
local DIFF_ORDER = { "easy", "medium", "hard", "expert" }
local DIFF_DEPTH = { easy = 3, medium = 5, hard = 7, expert = 9 }
local DIFF_LABELS = {
    easy   = MenuHelper.DIFFICULTY_LABELS.easy,
    medium = MenuHelper.DIFFICULTY_LABELS.medium,
    hard   = MenuHelper.DIFFICULTY_LABELS.hard,
    expert = _("Expert"),
}

local CheckersScreen = ScreenBase:extend{}

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function CheckersScreen:init()
    self.game = CheckersGame.load(self.plugin:loadState()) or CheckersGame.new()
    self.selected = nil
    ScreenBase.init(self)  -- calls buildLayout()
    if self:_isAITurn() then
        UIManager:scheduleIn(0.1, function() self:triggerAI() end)
    end
end

function CheckersScreen:isRoundOver()
    return self.game:is_over()
end

function CheckersScreen:serializeState()
    return self.game:serialize()
end

function CheckersScreen:closeScreen()
    self.closed = true
    ScreenBase.closeScreen(self)
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function CheckersScreen:buildLayout()
    local is_landscape = self:isLandscape()

    local title_bar = self:buildTitleBar(_("Checkers"), function()
        local items = {
            { text = _("New game"),          callback = function() self:onNewGame() end },
            { text = self:_diffLabel(),      callback = function() self:openDifficultyMenu() end },
            { text = self:_playersLabel(),   callback = function() self:openPlayersMenu() end },
        }
        if self:_players() == 1 then
            items[#items + 1] = { text = self:_colorLabel(),
                                  callback = function() self:openColorMenu() end }
        end
        items[#items + 1] = self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR)
        return items
    end)

    local controls_w = self:getControlsWidth()
    self.status_text:setMaxWidth(controls_w)
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        self:buildActionBar({
            { text = _("Undo"), callback = function() self:onUndo() end },
        }),
    }

    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    self.board_widget = CheckersBoardWidget:new{
        board        = self.game,
        max_size     = math.min(budget_w, budget_h),
        flipped      = self:_flipped(),
        highlight    = function() return self:_highlight() end,
        onCellAction = function(pos) self:onSquareTap(pos) end,
    }
    local board_frame = FrameContainer:new{
        padding    = 0,
        margin     = 0,
        bordersize = 0,
        self.board_widget,
    }

    if is_landscape then
        local content = HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        }
        self:buildLandscapeLayout(title_bar, content)
    else
        self:buildPortraitLayout(title_bar, board_frame,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

-- ---------------------------------------------------------------------------
-- Turn helpers
-- ---------------------------------------------------------------------------

function CheckersScreen:_players()
    return self.plugin:getSetting("players", 1)
end

-- Side the human plays against the AI: 1 = Black (first), 2 = White.
function CheckersScreen:_humanSide()
    return self.plugin:getSetting("player_color", "black") == "white" and 2 or 1
end

function CheckersScreen:_difficulty()
    local d = self.plugin:getSetting("difficulty", "medium")
    return DIFF_DEPTH[d] and d or "medium"
end

-- Against the AI the human's pieces are at the bottom.
function CheckersScreen:_flipped()
    return self:_players() == 1 and self:_humanSide() == 2
end

function CheckersScreen:_isAITurn()
    return self:_players() == 1 and not self.game:is_over()
        and self.game:whose_turn() ~= self:_humanSide()
end

function CheckersScreen:_sideName(p)
    return (p == 1) and _("Black") or _("White")
end

local function toSet(moves)
    local s = {}
    for _, m in ipairs(moves) do s[m[2]] = true end
    return s
end

function CheckersScreen:_highlight()
    if self.ai_pending or self:_isAITurn() or not self.selected then return {} end
    return {
        selected = self.selected,
        targets  = toSet(self.game:get_moves_for_piece(self.selected)),
    }
end

-- ---------------------------------------------------------------------------
-- Taps
-- ---------------------------------------------------------------------------

function CheckersScreen:onSquareTap(pos)
    local game = self.game
    if game:is_over() or self.ai_pending or self:_isAITurn() then return end
    if not pos then
        -- A light square: just drop the selection (not during a multi-jump).
        if self.selected and not game:is_mid_jump() then
            self.selected = nil
            self.board_widget:refresh()
            self:updateStatus()
        end
        return
    end

    -- Destination of the selected piece?
    if self.selected then
        for _, m in ipairs(game:get_moves_for_piece(self.selected)) do
            if m[2] == pos then
                return self:_play(self.selected, pos)
            end
        end
    end

    -- During a multi-jump only the jumping piece may move.
    if game:is_mid_jump() then
        self:updateStatus(_("Keep jumping with the same piece."))
        return
    end

    local piece = game:get_piece_at(pos)
    if piece and piece.player == game:whose_turn() then
        if self.selected == pos then
            self.selected = nil
            self:updateStatus()
        elseif #game:get_moves_for_piece(pos) == 0 then
            self.selected = nil
            self:updateStatus(game:must_capture()
                and _("You must capture: tap a piece that can jump.")
                or  _("That piece cannot move."))
        else
            self.selected = pos
            self:updateStatus()
        end
        self.board_widget:refresh()
        return
    end

    if self.selected then
        self.selected = nil
        self.board_widget:refresh()
        self:updateStatus()
    end
end

function CheckersScreen:_play(from, to)
    local game = self.game
    if not game:move(from, to) then return end
    if game:is_mid_jump() then
        -- Same turn: the piece stays selected for its next jump.
        self.selected = game:get_mid_jump_piece_pos()
        self.board_widget:refresh()
        self.plugin:saveState(self:serializeState())
        self:updateStatus()
        return
    end
    self.selected = nil
    self:_afterTurn()
end

function CheckersScreen:_afterTurn()
    self.board_widget:refresh()
    self.plugin:saveState(self:serializeState())
    self:updateStatus()
    if self.game:is_over() then
        self:showMessage(self:_resultText(), 4)
    elseif self:_isAITurn() then
        self:triggerAI()
    end
end

-- ---------------------------------------------------------------------------
-- AI
-- ---------------------------------------------------------------------------

function CheckersScreen:triggerAI()
    if not self:_isAITurn() or self.ai_pending then return end
    self.ai_pending = true
    self.selected = nil
    self.board_widget:refresh()
    self:updateStatus(_("AI is thinking..."))
    local depth = DIFF_DEPTH[self:_difficulty()]
    UIManager:scheduleIn(0.05, function()
        self.ai_pending = false
        if self.closed or not self:_isAITurn() then return end
        local game = self.game
        local side = game:whose_turn()
        -- A multi-jump is several moves of the same turn.
        repeat
            local m = CheckersAI.best_move(game, depth)
            if not m then break end
            game:move(m[1], m[2])
        until not game:is_mid_jump() or game:whose_turn() ~= side
        self:_afterTurn()
    end)
end

-- ---------------------------------------------------------------------------
-- Undo / new game
-- ---------------------------------------------------------------------------

-- Against the AI, undo also takes back the AI's reply, so it is the player's
-- turn again. A multi-jump is undone as a whole.
function CheckersScreen:onUndo()
    if self.ai_pending then return end
    local game = self.game
    if not game:can_undo() then
        self:updateStatus(_("Nothing to undo."))
        return
    end
    game:undo()
    if self:_players() == 1 then
        while game:whose_turn() ~= self:_humanSide() and game:can_undo() do
            game:undo()
        end
    end
    self.selected = nil
    self.board_widget:refresh()
    self.plugin:saveState(self:serializeState())
    self:updateStatus()
    if self:_isAITurn() then self:triggerAI() end
end

function CheckersScreen:onNewGame()
    self.game = CheckersGame.new()
    self.selected = nil
    self.plugin:saveState(self:serializeState())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
    if self:_isAITurn() then
        UIManager:scheduleIn(0.1, function() self:triggerAI() end)
    end
end

-- ---------------------------------------------------------------------------
-- Status
-- ---------------------------------------------------------------------------

function CheckersScreen:_resultText()
    local res = self.game:result()
    if not res then return "" end
    if not res.winner then
        return _("Draw: 40 moves without a capture.")
    end
    local head
    if self:_players() == 1 then
        head = (res.winner == self:_humanSide()) and _("You win!") or _("The AI wins.")
    else
        head = T(_("%1 wins the game!"), self:_sideName(res.winner))
    end
    local loser = self:_sideName(3 - res.winner)
    local why = (res.reason == "blocked")
        and T(_("%1 cannot move."), loser)
        or  T(_("%1 has no pieces left."), loser)
    return head .. " " .. why
end

function CheckersScreen:_actionText()
    local game = self.game
    if self:_isAITurn() then return _("AI is thinking...") end
    local who = self:_sideName(game:whose_turn())
    if game:is_mid_jump() then return T(_("%1 keeps jumping"), who) end
    return T(_("%1 to move"), who)
end

function CheckersScreen:updateStatus(msg)
    local status
    if msg then
        status = msg
    elseif self.game:is_over() then
        status = self:_resultText()
    else
        local dlabel
        if self:_players() == 1 then dlabel = DIFF_LABELS[self:_difficulty()] end
        status = self:joinStatus(dlabel, self:_actionText(),
            T(_("Black: %1"), self.game:count(1)),
            T(_("White: %1"), self.game:count(2)))
    end
    ScreenBase.updateStatus(self, status)
    self:refreshActionBar()
end

-- ---------------------------------------------------------------------------
-- Menus
-- ---------------------------------------------------------------------------

function CheckersScreen:_playersLabel()
    return T(_("Players: %1"), self:_players())
end

function CheckersScreen:_diffLabel()
    return T(_("Difficulty: %1"), DIFF_LABELS[self:_difficulty()])
end

function CheckersScreen:_colorLabel()
    return T(_("Play as: %1"), self:_sideName(self:_humanSide()))
end

-- The board turns when the human's side changes; the game goes on.
function CheckersScreen:_settingsChanged()
    self.selected = nil
    self.board_widget.flipped = self:_flipped()
    self.board_widget:refresh()
    self:updateStatus()
    if self:_isAITurn() then self:triggerAI() end
end

function CheckersScreen:openPlayersMenu()
    MenuHelper.openPickerMenu{
        title      = _("Players"),
        items      = {
            { id = 1, text = _("1 player (vs AI)") },
            { id = 2, text = _("2 players") },
        },
        current_id = self:_players(),
        on_select  = function(id)
            self.plugin:saveSetting("players", id)
            self:_settingsChanged()
        end,
        parent = self,
    }
end

function CheckersScreen:openColorMenu()
    MenuHelper.openPickerMenu{
        title      = _("Play as"),
        items      = {
            { id = "black", text = _("Black (plays first)") },
            { id = "white", text = _("White (plays second)") },
        },
        current_id = self.plugin:getSetting("player_color", "black"),
        on_select  = function(id)
            self.plugin:saveSetting("player_color", id)
            self:onNewGame()
        end,
        parent = self,
    }
end

function CheckersScreen:openDifficultyMenu()
    local items = {}
    for _, id in ipairs(DIFF_ORDER) do
        items[#items + 1] = { id = id, text = DIFF_LABELS[id] }
    end
    MenuHelper.openPickerMenu{
        title      = _("Select difficulty"),
        items      = items,
        current_id = self:_difficulty(),
        on_select  = function(id)
            self.plugin:saveSetting("difficulty", id)
            self:updateStatus()
        end,
        parent = self,
    }
end

return CheckersScreen
