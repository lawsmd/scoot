-- WindowShell.lua - a window with its furniture: the surface from
-- Window:Create on the window or dialog role, a title bar that drags it, the
-- close button, Escape, and a position saved under a key the caller names.
--
-- Window:Create draws the surface and nothing else, and every window in the
-- framework then built the same title bar, close button, Escape wiring and
-- position save by hand (the settings panel, the high score window, the game
-- menu, the ScootAuras editor). This is that furniture once. The settings
-- panel keeps its own title, the block-letter logo with the click home, and
-- draws it into the bar the shell builds; a window with a plain name passes
-- opts.title.
--
-- opts:
--   name          global frame name; needed for the UISpecialFrames Escape
--   parent        default UIParent
--   width, height the frame's size
--   role          "window" (default) or "dialog": the chrome role the surface
--                 is drawn from
--   template      true takes the role's template kind where the skin has one;
--                 the default declines it, as Window:Create does
--   strata, level override the DIALOG and 100 that Window:Create sets
--   title         the name in the bar, accent colored, in the titleBar role's
--                 font role when that role is text and the header role
--                 otherwise; on a template frame with a title plate, the
--                 plate's text. titleFontRole and titleSize override the font
--   titleHeight   the bar's height; default metrics.titleBarHeight
--   closeButton   false omits the X; closeName names its frame
--   onClose       runs on the X and on a capture Escape; default Hide
--   escape        "special" (default when name is given): the frame goes on
--                 UISpecialFrames and the game's own Escape hides it;
--                 "capture": addon.EscapeKey.Attach runs onEscape, or
--                 CloseShell when none is given; false: none
--   onEscape      the capture handler
--   positionKey   a key under addon.db.global the position is saved to on
--                 every drag and read back at creation; nil centres the frame
--                 and saves nothing
--   movable       false leaves the bar as a title only
--
-- The frame carries _titleBar, _title (the FontString when title was given),
-- _closeBtn, and the methods SetShellTitle, SaveShellPosition,
-- RestoreShellPosition, CloseShell and CleanupShell. The names are prefixed
-- because a template frame brings Blizzard's own SetTitle with it, and a
-- method added here must share a name with none of that mixin's.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.WindowShell = {}
local WindowShell = addon.UI.WindowShell

local function M()
    return addon.UI.Controls.Metrics()
end

local function SavePosition(frame, key)
    if not key or not (addon.db and addon.db.global) then return end
    local point, _, relPoint, x, y = frame:GetPoint()
    if not point then return end
    addon.db.global[key] = { point = point, relPoint = relPoint, x = x, y = y }
end

local function RestorePosition(frame, key)
    local pos = key and addon.db and addon.db.global and addon.db.global[key]
    frame:ClearAllPoints()
    if type(pos) == "table" and pos.point and pos.x and pos.y then
        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

-- A region that moves the frame: the bar itself, or the button a title
-- draws over a template's plate.
local function WireDrag(region, frame)
    region:EnableMouse(true)
    region:RegisterForDrag("LeftButton")
    region:SetScript("OnDragStart", function()
        if frame:IsMovable() then frame:StartMoving() end
    end)
    region:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        frame:SaveShellPosition()
    end)
end

-- The name in the bar. A skin whose titleBar role is the template's plate
-- puts it there, and a drag button over the plate keeps the bar's drag; the
-- rest draw a string at the bar's left edge.
local function BuildTitle(frame, titleBar, opts)
    local Theme = addon.UI.Theme
    local Chrome = addon.UI.Chrome
    local spec = Chrome.Spec("titleBar")
    if spec.kind == "window" and frame.SetTitle and frame.GetTitleText and frame.TitleContainer then
        frame:SetTitle(opts.title)
        if spec.offsets and frame.SetTitleOffsets then
            frame:SetTitleOffsets(spec.offsets.left, spec.offsets.right)
        end
        if spec.justify then
            frame:GetTitleText():SetJustifyH(spec.justify)
        end
        if spec.titleColor and frame.SetTitleColor then
            frame:SetTitleColor(CreateColor(Chrome.Color(spec.titleColor)))
        end
        local btn = CreateFrame("Button", nil, frame.TitleContainer)
        btn:SetAllPoints(frame.TitleContainer)
        WireDrag(btn, frame)
        frame._title = frame:GetTitleText()
        return
    end

    local fs = titleBar:CreateFontString(nil, "OVERLAY", spec.fontObject)
    if not spec.fontObject then
        local role = opts.titleFontRole or (spec.kind == "text" and spec.fontRole) or "header"
        Theme:ApplyFont(fs, role, opts.titleSize)
        fs:SetTextColor(Theme:GetAccentColor())
        local key = "WindowShell:" .. (opts.name or tostring(frame))
        frame._shellThemeKey = key
        Theme:Subscribe(key, function(r, g, b)
            fs:SetTextColor(r, g, b, 1)
        end)
    end
    fs:SetPoint("LEFT", titleBar, "LEFT", spec.x or 12, spec.y or 0)
    fs:SetJustifyH("LEFT")
    fs:SetText(opts.title)
    frame._title = fs
end

function WindowShell.Create(opts)
    opts = opts or {}
    local Window = addon.UI.Window
    local Controls = addon.UI.Controls
    local frame = Window:Create(opts.name, opts.parent or UIParent, opts.width, opts.height,
        { role = opts.role, template = opts.template })
    if opts.strata then frame:SetFrameStrata(opts.strata) end
    if opts.level then frame:SetFrameLevel(opts.level) end
    if opts.movable == false then frame:SetMovable(false) end
    local positionKey = opts.positionKey

    function frame:SaveShellPosition()
        SavePosition(self, positionKey)
    end

    function frame:RestoreShellPosition()
        RestorePosition(self, positionKey)
    end

    function frame:CloseShell()
        if opts.onClose then
            opts.onClose(self)
        else
            self:Hide()
        end
    end

    -- The bar across the top: the drag region, and the title's home
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetHeight(opts.titleHeight or M().titleBarHeight)
    titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    WireDrag(titleBar, frame)
    frame._titleBar = titleBar

    if opts.title then
        BuildTitle(frame, titleBar, opts)
    end

    function frame:SetShellTitle(text)
        if self._title and self._title.SetText then self._title:SetText(text or "") end
    end

    if opts.closeButton ~= false then
        local closeBtn, closeSpec = Controls:CreateCloseButton({
            parent = frame,
            name = opts.closeName,
            onClick = function() frame:CloseShell() end,
        })
        if closeBtn then
            -- The window kind's button is the template's own, already anchored
            if not (closeSpec and closeSpec.kind == "window") then
                closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", M().closeButton.x, M().closeButton.y)
                closeBtn:SetFrameLevel(frame:GetOverlayLevel())
            end
            frame._closeBtn = closeBtn
        end
    end

    local escape = opts.escape
    if escape == nil then escape = opts.onEscape and "capture" or (opts.name and "special") or false end
    if escape == "capture" then
        addon.EscapeKey.Attach(frame, function(f)
            if opts.onEscape then opts.onEscape(f) else f:CloseShell() end
        end)
    elseif escape == "special" and opts.name then
        -- A rebuild under the same name (the skin switch) keeps the one entry
        local listed = false
        for _, entry in ipairs(UISpecialFrames) do
            if entry == opts.name then listed = true break end
        end
        if not listed then
            tinsert(UISpecialFrames, opts.name)
        end
    end

    function frame:CleanupShell()
        if self._closeBtn and self._closeBtn.Cleanup then self._closeBtn:Cleanup() end
        if self._shellThemeKey then
            addon.UI.Theme:Unsubscribe(self._shellThemeKey)
            self._shellThemeKey = nil
        end
    end

    frame:RestoreShellPosition()
    return frame
end
