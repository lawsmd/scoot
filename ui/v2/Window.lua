-- Window.lua - the settings window's frame: background, chrome and border,
-- drawn the way the active skin's window role says.
--
-- The window role (addon.UI.Chrome, Spec("window")) is flat, nineSlice or
-- template. Flat is the panel's own look: a background fill, a noise layer
-- over it, and a solid border windowBorderWidth wide. nineSlice puts
-- Blizzard's nine-slice pieces on a child frame. template makes the frame
-- itself an instance of a Blizzard panel template, whose border, title
-- plate, close button and portrait ring come with it; the descriptor names
-- what fills the ring (portrait) and the art laid under the title band
-- (contentBackground). A caller takes the template kind by passing
-- opts.template; a game menu or an editor window gets the role's fallback
-- instead of a portrait panel. The content inset the panes anchor from is
-- the skin's windowInset metric in every kind.
--
-- A template frame carries Blizzard's title and portrait mixin, so the two
-- methods added here, GetContentInset and GetOverlayLevel, share a name with
-- none of its methods; a new one has to be checked the same way.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Window = {}
local Window = addon.UI.Window
local Theme = addon.UI.Theme

local function Metrics()
    return addon.UI.Controls.Metrics()
end

--------------------------------------------------------------------------------
-- Window Factory
--------------------------------------------------------------------------------

-- Create the settings window frame
-- @param name: Global frame name
-- @param parent: Parent frame (default UIParent)
-- @param width: Window width (default 900)
-- @param height: Window height (default 650)
-- @param opts: template = true takes the window role's template kind; the
--               default declines it and draws the role's fallback
-- @return: The created frame
function Window:Create(name, parent, width, height, opts)
    local Chrome = addon.UI.Chrome
    local spec = Chrome.Spec("window")
    if spec.kind == "template" and not (opts and opts.template) then
        spec = Chrome.Resolve(spec.fallback, Chrome.FLAT.window)
    end
    local frame = Chrome.CreateFrame(spec, "Frame", name, parent or UIParent)
    frame:SetSize(width or 900, height or 650)
    -- Use DIALOG strata to match old SettingsPanel - HIGH strata + SetToplevel
    -- can cause Blizzard's ShowUIPanel to hide the frame unexpectedly
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(100)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)

    -- Store dimensions for reference
    frame._defaultWidth = width or 900
    frame._defaultHeight = height or 650

    frame._chromeSpec = spec

    if spec.kind == "template" then
        self:BuildTemplateParts(frame, spec)
    else
        self:CreateBackground(frame, spec)
        if spec.kind == "nineSlice" then
            frame._chrome = Chrome.NineSlice(frame, spec)
        else
            if spec.noise then
                self:CreateNoiseOverlay(frame, spec.noise)
            end
            self:CreateSolidBorder(frame, spec)
        end
    end

    -- The inset every pane anchors from: the flat border's width, or the
    -- distance a nine-slice frame's art reaches into the rect.
    function frame:GetContentInset()
        local m = Metrics()
        return (m and m.windowInset) or Theme.BORDER_WIDTH or 3
    end

    -- The frame level a part takes to draw over the window's border art: the
    -- resize grip sits in the corner the border owns. A template's border is
    -- a child frame of its own, levels above the panel's parts; flat and
    -- nine-slice borders draw on the frame itself, so a step above the
    -- panel's own children is enough.
    function frame:GetOverlayLevel()
        if self._chromeSpec and self._chromeSpec.kind == "template" and self.NineSlice then
            return self.NineSlice:GetFrameLevel() + 1
        end
        return self:GetFrameLevel() + 10
    end

    -- NOTE: Dragging is NOT registered on the main frame.
    -- The SettingsPanel creates a title bar that handles dragging instead,
    -- so users can only drag the window by the title bar area (not the entire window).
    -- Position saving is handled by the title bar's OnDragStop in SettingsPanel.lua.

    -- Mark as UI window
    frame._isSettingsWindow = true

    return frame
end

--------------------------------------------------------------------------------
-- Template parts: the portrait and the content background
--------------------------------------------------------------------------------

local function atlasExists(name)
    if type(name) ~= "string" or not (C_Texture and C_Texture.GetAtlasInfo) then return false end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    return ok and info ~= nil
end

-- portrait: { texture = <Theme.Textures key or path> } | { atlas = name } |
-- { unit = "player" } | { class = true } | false, which hides the ring's
-- contents; nil leaves the template's empty ring. Every call is the
-- template's own method. size, with x and y, redraws the icon at that side
-- and that offset from the frame's top-left corner, the template's own 62 at
-- -5, 7 otherwise. mask = false takes the round crop off, for a mark drawn
-- to its own edge. overlay = true lifts the icon over the border art, which
-- a portrait sitting in a ring's hole does not want and a mark standing on a
-- plain corner does.
-- layout: a NineSliceUtil layout name the border is rebuilt from, whatever
-- the portrait is. The template's top-left corner is the one that carries
-- the portrait ring, so a skin whose mark is already round names
-- ButtonFrameTemplateNoPortrait here: the same metal border with a plain
-- corner, and the mark left standing in the space the ring held.
-- contentBackground: the declared descriptor gives the rect (inset) and the
-- draw sublevel, the resolved one the art, so a missing atlas keeps the
-- geometry and changes only the fill. The template's own tiled background
-- stays under it in the margins and the title band. An atlas with grid =
-- { cols = { x }, rows = { y1, y2, ... } } is cut at those member pixels and
-- laid so its column split lands on the nav's right edge (windowInset plus
-- navWidth) and its last row split on the title bar's bottom edge, the
-- earlier row splits keeping their own distance above it; a background with
-- a panel edge baked into it then meets the panes where they meet. A grid
-- cell named in grid.tile repeats a band of the art down its rect instead
-- of stretching (Chrome.GridAtlas).
function Window:BuildTemplateParts(frame, spec)
    local Chrome = addon.UI.Chrome
    local portrait = spec.portrait
    -- The border is named on its own line, not behind portrait = false, so a
    -- skin can drop the ringed corner and still draw an icon there. A layout
    -- the client does not carry leaves the template's own border alone.
    if spec.layout and frame.SetBorder and NineSliceUtil
        and NineSliceUtil.GetLayout(spec.layout) then
        frame:SetBorder(spec.layout)
    end
    if portrait == false then
        if frame.SetPortraitShown then frame:SetPortraitShown(false) end
    elseif type(portrait) == "table" then
        local container = frame.PortraitContainer
        if portrait.size and frame.SetPortraitTextureSizeAndOffset then
            frame:SetPortraitTextureSizeAndOffset(portrait.size, portrait.x or 0, portrait.y or 0)
        end
        -- The round crop is there for a unit portrait. A mark drawn to its
        -- own edge asks for it off and keeps every pixel it was drawn with.
        if portrait.mask == false and container and container.CircleMask
            and container.portrait and container.portrait.RemoveMaskTexture then
            container.portrait:RemoveMaskTexture(container.CircleMask)
        end
        -- The border is a child frame levels above this one, so a ringless
        -- corner draws its metal over the icon. The same step GetOverlayLevel
        -- gives the resize grip, computed here because that method is added
        -- to the frame after this call.
        if portrait.overlay and container and frame.NineSlice then
            container:SetFrameLevel(frame.NineSlice:GetFrameLevel() + 1)
        end
        if portrait.unit and frame.SetPortraitToUnit then
            frame:SetPortraitToUnit(portrait.unit)
            frame:HookScript("OnShow", function(f) f:SetPortraitToUnit(portrait.unit) end)
        elseif portrait.atlas and frame.SetPortraitAtlasRaw then
            if atlasExists(portrait.atlas) then
                frame:SetPortraitAtlasRaw(portrait.atlas)
            elseif frame.SetPortraitShown then
                frame:SetPortraitShown(false)
            end
        elseif portrait.texture and frame.SetPortraitToAsset then
            local path = (Theme.Textures and Theme.Textures[portrait.texture]) or portrait.texture
            frame:SetPortraitToAsset(path)
        elseif portrait.class and frame.SetPortraitToClassIcon then
            local _, classFile = UnitClass("player")
            if classFile then frame:SetPortraitToClassIcon(classFile) end
        end
    end

    local declared = spec.contentBackground
    if declared then
        local cb = Chrome.Resolve(declared, { kind = "flat", fill = "window" })
        local inset = declared.inset or {}
        local left, top = inset.left or 0, inset.top or 0
        local host = CreateFrame("Frame", nil, frame)
        host:SetFrameLevel(frame:GetFrameLevel())
        host:SetPoint("TOPLEFT", frame, "TOPLEFT", left, -top)
        host:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(inset.right or 0), inset.bottom or 0)
        local sublevel = declared.sublevel or -5
        local tex
        if cb.kind == "atlas" and cb.atlas and cb.grid then
            -- The leading splits are placed here; the trailing ones the grid
            -- counts in fromRight and fromBottom place themselves
            local m = Metrics()
            local cols, rows = cb.grid.cols or {}, cb.grid.rows or {}
            local leadCols = #cols - (cb.grid.fromRight or 0)
            local leadRows = #rows - (cb.grid.fromBottom or 0)
            local xs, ys = {}, {}
            for i = 1, leadCols do
                xs[i] = (m.windowInset or 0) + (m.navWidth or 0) - left + (cols[i] - cols[1])
            end
            for i = 1, leadRows do
                ys[i] = (m.titleBarHeight or 0) - (rows[leadRows] - rows[i]) - top
            end
            tex = Chrome.GridAtlas(host, cb, "BACKGROUND", sublevel, xs, ys)
        end
        if not tex then
            tex = host:CreateTexture(nil, "BACKGROUND", nil, sublevel)
            tex:SetAllPoints()
        end
        if cb.kind == "atlas" and cb.atlas then
            if tex.SetAtlas then tex:SetAtlas(cb.atlas) end
        else
            local fill = cb.fill or "window"
            local r, g, b, a
            if fill == "window" then
                r, g, b, a = Theme:GetBackgroundColor()
            else
                r, g, b, a = Chrome.Color(fill)
            end
            tex:SetColorTexture(r, g, b, a or 1)
        end
        -- A grid names its own cells; one texture laid whole is the page fill
        if tex.SetAlpha then Chrome.ApplyOpacity("pageFill", tex) end
        frame._contentBackground = tex
    end

    -- The template's own regions, each on its piece: the border is a child
    -- frame and the fill a texture behind it, so the two fade apart. The
    -- portrait ring is drawn by the border's corner and goes with it.
    --
    -- spec.pieces renames them, because a surface standing on another one
    -- cannot take the window's numbers: the panel's fill is translucent
    -- against the world, and a dialog over that panel at the same value
    -- shows the world through two of them. The picker role names its own.
    local pieces = spec.pieces or {}
    Chrome.ApplyOpacity(pieces.border or "windowBorder", frame.NineSlice)
    Chrome.ApplyOpacity(pieces.fill or "windowFill", frame.Bg)
    Chrome.ApplyOpacity(pieces.streaks or "titleStreaks", frame.TopTileStreaks)
    Chrome.ApplyOpacity(pieces.portrait or "portrait", frame.PortraitContainer)
end

--------------------------------------------------------------------------------
-- Background Layer (semi-transparent dark)
--------------------------------------------------------------------------------

function Window:CreateBackground(frame, spec)
    frame._bg = addon.UI.Controls.AddBackground(frame, {
        color = (spec and spec.background) or "window",
        inset = (spec and spec.backgroundInset) or 0,
    })
end

--------------------------------------------------------------------------------
-- Noise Overlay (frosted glass effect)
--------------------------------------------------------------------------------

-- noise = { texture = <Theme.Textures key>, size = <texture side in px>,
--           alpha, blend }, from the window descriptor.
function Window:CreateNoiseOverlay(frame, noiseSpec)
    local path = Theme.Textures and Theme.Textures[noiseSpec.texture or "NOISE_OVERLAY"]
    if not path then return nil end
    local textureSize = noiseSpec.size or 2048

    local noise = frame:CreateTexture(nil, "BACKGROUND", nil, -7)  -- Above bg (-8)
    noise:SetAllPoints()
    noise:SetTexture(path)
    noise:SetAlpha(noiseSpec.alpha or 0.25)
    noise:SetBlendMode(noiseSpec.blend or "ADD")

    -- Manual tex-coord tiling (bypasses unreliable SetHorizTile/SetVertTile)
    local function UpdateNoiseCoords()
        local width, height = frame:GetSize()
        if width and height and width > 0 and height > 0 then
            noise:SetTexCoord(0, width / textureSize, 0, height / textureSize)
        end
    end

    -- Update on resize
    frame:HookScript("OnSizeChanged", UpdateNoiseCoords)

    -- Initial update
    UpdateNoiseCoords()

    frame._noise = noise
    return noise
end

--------------------------------------------------------------------------------
-- Solid Border (clean square border with proper corners)
--------------------------------------------------------------------------------

function Window:CreateSolidBorder(frame, spec)
    local m = Metrics()
    frame._border = addon.UI.Controls.CreateBorder(frame, {
        thickness = (m and m.windowBorderWidth) or Theme.BORDER_WIDTH or 3,
        corners = (spec and spec.corners) or "outset",
    })
end

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------

function Window:Destroy(frame)
    if not frame then return end

    if frame._border and frame._border.Destroy then
        frame._border:Destroy()
    end
    if frame._chrome and frame._chrome.Destroy then
        frame._chrome:Destroy()
    end
    if frame._contentBackground then
        local bg = frame._contentBackground
        if bg.Destroy then bg:Destroy() else bg:Hide() end
    end

    -- Hide and clear. A template frame created again under the same name
    -- takes over the name and its children's; the old one is orphaned here,
    -- which only the runtime skin switch does.
    frame:Hide()
    frame:SetParent(nil)
end

--------------------------------------------------------------------------------
-- Position Restoration
--------------------------------------------------------------------------------

function Window:RestorePosition(frame)
    if not frame or not addon.db or not addon.db.global then return end

    local pos = addon.db.global.windowPosition
    if pos and pos.point and pos.x and pos.y then
        frame:ClearAllPoints()
        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
    else
        -- Default to center
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end
