-- RoleMarks.lua - roles as letters: T, H and D in the mono face, with no
-- icon art behind them.
--
-- Two modes. Display draws one mark per slot, accent for a slot that is
-- taken and dim for one that is open, as a group's composition reads
-- (T H D D D) or a member's roles (T H D with the ones the member fills
-- lit). Toggle draws three tiles on the tab role, the letter over the role's
-- word, lit while chosen, which is the sign-up dialog's role choice.
--
-- opts:
--   mode        "display" (default) or "toggle"
--   glyphs      { TANK, HEALER, DAMAGER } letters; default T, H, D
--   words       the toggle tiles' captions; default the client's TANK,
--               HEALER and DAMAGER strings
--   size        the display mark's font size; default the label role's
--   markWidth   the room a display mark takes; default size + 2
--   gap         between marks or tiles; default 2 for marks, 6 for tiles
--   tileWidth, tileHeight
--               default 56 and 48
--   onChange(tank, healer, damage)
--               a toggle tile clicked
--
-- Display: SetSlots({ { role, filled, color }, ... }) in order, where color,
-- an { r, g, b }, paints a filled slot in place of the accent (a class
-- color); SetRoles(tank, healer, damage) draws T H D with the given ones
-- lit. Toggle: SetRoles,
-- GetRoles() -> tank, healer, damage, SetRoleEnabled(role, enabled). Both
-- size the frame to their content.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls

local ORDER = { "TANK", "HEALER", "DAMAGER" }
local DEFAULT_GLYPHS = { TANK = "T", HEALER = "H", DAMAGER = "D" }

-- Every control, repainted together on an accent change
local live = setmetatable({}, { __mode = "k" })
local subscribed = false

local function EnsureSubscription()
    if subscribed then return end
    local Theme = addon.UI.Theme
    if not Theme then return end
    subscribed = true
    Theme:Subscribe("ControlsRoleMarks", function()
        for control in pairs(live) do
            if control.Repaint then control:Repaint() end
        end
    end)
end

-- The client's own role words, read off the global table because luacheck
-- does not list them
local function Words()
    return { TANK = _G.TANK or "Tank", HEALER = _G.HEALER or "Healer", DAMAGER = _G.DAMAGER or "Damage" }
end

local function BuildDisplay(frame, opts)
    local Theme = addon.UI.Theme
    local glyphs = opts.glyphs or DEFAULT_GLYPHS
    local size = opts.size
    local markWidth = opts.markWidth or ((size or 13) + 2)
    local gap = opts.gap or 2
    frame._slots = {}

    local pool = addon.Pool.NewIndexed(function()
        local fs = frame:CreateFontString(nil, "OVERLAY")
        Theme:ApplyFont(fs, "label", size)
        fs:SetJustifyH("CENTER")
        return fs
    end)

    function frame:Repaint()
        local ar, ag, ab = Theme:GetAccentColor()
        local dr, dg, db = Theme:GetDimTextColor()
        for i, slot in ipairs(self._slots) do
            local fs = pool:Get(i)
            if slot.filled and type(slot.color) == "table" then
                fs:SetTextColor(slot.color[1] or ar, slot.color[2] or ag, slot.color[3] or ab, 1)
            elseif slot.filled then
                fs:SetTextColor(ar, ag, ab, 1)
            else
                fs:SetTextColor(dr, dg, db, 0.5)
            end
        end
    end

    function frame:SetSlots(slots)
        self._slots = slots or {}
        local n = #self._slots
        for i, slot in ipairs(self._slots) do
            local fs = pool:Get(i)
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", self, "LEFT", (i - 1) * (markWidth + gap), 0)
            fs:SetWidth(markWidth)
            fs:Show()
            fs:SetText(glyphs[slot.role] or "?")
        end
        pool:HideFrom(n + 1)
        self:SetSize(math.max(1, n * (markWidth + gap) - gap), math.max(1, (pool:Get(1):GetStringHeight() or 0) + 2))
        self:Repaint()
    end

    function frame:SetRoles(tank, healer, damage)
        self:SetSlots({
            { role = "TANK", filled = tank and true or false },
            { role = "HEALER", filled = healer and true or false },
            { role = "DAMAGER", filled = damage and true or false },
        })
    end
end

local function BuildToggle(frame, opts)
    local Theme = addon.UI.Theme
    local Chrome = addon.UI.Chrome
    local glyphs = opts.glyphs or DEFAULT_GLYPHS
    local words = opts.words or Words()
    local gap = opts.gap or 6
    local tileWidth = opts.tileWidth or 56
    local tileHeight = opts.tileHeight or 48
    frame._tiles = {}
    frame._chosen = { TANK = false, HEALER = false, DAMAGER = false }
    frame._enabled = { TANK = true, HEALER = true, DAMAGER = true }

    local function PaintTile(tile)
        local r, g, b, a = tile._backdrop:LabelColor()
        tile._word:SetTextColor(r, g, b, a or 1)
    end

    function frame:Repaint()
        for _, tile in ipairs(self._tiles) do
            tile._backdrop:Refresh()
            PaintTile(tile)
        end
    end

    for i, role in ipairs(ORDER) do
        local tile = CreateFrame("Button", nil, frame)
        tile:SetSize(tileWidth, tileHeight)
        tile:SetPoint("LEFT", frame, "LEFT", (i - 1) * (tileWidth + gap), 0)
        tile:RegisterForClicks("LeftButtonUp")
        tile._role = role

        local letter = tile:CreateFontString(nil, "OVERLAY")
        Theme:ApplyFont(letter, "header")
        letter:SetPoint("TOP", tile, "TOP", 0, -6)
        letter:SetText(glyphs[role] or "?")
        tile._letter = letter

        local word = tile:CreateFontString(nil, "OVERLAY")
        Theme:ApplyFont(word, "miniLabel")
        word:SetPoint("BOTTOM", tile, "BOTTOM", 0, 5)
        word:SetText(words[role] or role)
        tile._word = word

        tile._backdrop = Chrome.Backdrop("tab", tile, { label = letter })
        PaintTile(tile)

        tile:SetScript("OnEnter", function(t)
            if frame._enabled[t._role] then t._backdrop:SetHover(true); PaintTile(t) end
        end)
        tile:SetScript("OnLeave", function(t)
            t._backdrop:SetHover(false)
            PaintTile(t)
        end)
        tile:SetScript("OnClick", function(t)
            if not frame._enabled[t._role] then return end
            frame._chosen[t._role] = not frame._chosen[t._role]
            t._backdrop:SetSelected(frame._chosen[t._role])
            PaintTile(t)
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            if opts.onChange then opts.onChange(frame:GetRoles()) end
        end)

        frame._tiles[i] = tile
    end
    frame:SetSize(#ORDER * (tileWidth + gap) - gap, tileHeight)

    function frame:SetRoles(tank, healer, damage)
        self._chosen.TANK = tank and true or false
        self._chosen.HEALER = healer and true or false
        self._chosen.DAMAGER = damage and true or false
        for _, tile in ipairs(self._tiles) do
            tile._backdrop:SetSelected(self._chosen[tile._role])
            PaintTile(tile)
        end
    end

    function frame:GetRoles()
        return self._chosen.TANK, self._chosen.HEALER, self._chosen.DAMAGER
    end

    function frame:SetRoleEnabled(role, enabled)
        self._enabled[role] = enabled and true or false
        for _, tile in ipairs(self._tiles) do
            if tile._role == role then
                tile._backdrop:SetDisabled(not enabled)
                PaintTile(tile)
            end
        end
    end
end

function Controls.CreateRoleMarks(parent, opts)
    opts = opts or {}
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(1, 1)
    if opts.mode == "toggle" then
        BuildToggle(frame, opts)
    else
        BuildDisplay(frame, opts)
    end
    live[frame] = true
    EnsureSubscription()
    return frame
end
