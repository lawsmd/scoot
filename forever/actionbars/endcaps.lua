--------------------------------------------------------------------------------
-- forever/actionbars/endcaps.lua
-- The end caps: a gryphon (Alliance) or wyvern (Horde) on each side of
-- Action Bar Cluster 1, hidden for a neutral character. Two styles:
--
-- * Standing, Camelot's own upright art. A cap is 90 percent of the
--   container's height times the End Cap Scale, centered on it vertically,
--   with its inner edge on the container's outer edge.
-- * Sitting, Blizzard's own atlases at the size Forever draws them, 154 by
--   95 times the End Cap Scale, reaching 30 units over the bar as Forever's
--   preset does (the beta's Blizzard_EditMode/Mainline/EditModePresetLayouts,
--   EndCapLeft and EndCapRight). The art's opaque rows run to the atlas rect's bottom
--   edge, so the cap's bottom on the container's bottom stands the creature
--   on the lowest bar's bottom edge however many bars the cluster holds.
--
-- The caps are sized, never scaled, so the inner anchor holds at every scale.
-- Standing caps are regions of the container, under the bars; sitting caps
-- are regions of a child frame above the bars, in front of the buttons they
-- reach over. Either way the container carries them through a drag, a
-- dynamic scale and a fade. The settings are cluster 1's endCaps, endCapStyle and
-- endCapScale fields.
--
-- Each cap carries an Edit Mode box of its own that opens the end cap rows.
-- The box cannot move the cap: its drag is unregistered, and any position
-- the library writes (an arrow key, Reset Position) is put back on the cap
-- and never stored.
--
-- One standing file per creature ships, facing right for the left cap; the
-- right cap is the same file mirrored through its texture coordinates.
--------------------------------------------------------------------------------

local _, addon = ...

local ActionBars = addon.ActionBars
local EndCaps = {}
ActionBars.EndCaps = EndCaps

-- Cluster 1, Clusters.PRIMARY; clusters.lua loads after this file.
local PRIMARY = 1

EndCaps.STYLE_VALUES = { standing = "Standing", sitting = "Sitting" }
EndCaps.STYLE_ORDER = { "standing", "sitting" }
EndCaps.SCALE_RANGE = { min = 50, max = 200, step = 5 }

-- The standing cap's height as a share of the cluster's, at scale 100.
local HEIGHT_SHARE = 0.9

-- The standing art sits in the top left of a 512 x 1024 canvas; w and h are
-- its pixel size there. inset is how far the cap reaches over the bar, as a
-- share of its own width: the gryphon's inner edge is flat, the wyvern's is
-- its outermost spikes, and the eye pass decides whether either moves.
local CANVAS_W, CANVAS_H = 512, 1024
local MEDIA = addon.MediaPath .. "forever\\media\\actionbars\\"
local STANDING = {
    Alliance = { file = MEDIA .. "gryphon.png", w = 446, h = 880, inset = 0 },
    Horde = { file = MEDIA .. "wyvern.png", w = 512, h = 880, inset = 0 },
}

-- Forever's MainMenuBarEndCaps frames are 154 x 95, and its preset sets each
-- 30 units in from the bar's edge. The plain names draw the bronze -c60
-- members on Forever and the gray ones on retail.
local SITTING_W, SITTING_H, SITTING_INSET = 154, 95, 30
local SITTING = {
    Alliance = { left = "ui-hud-actionbar-gryphon-left", right = "ui-hud-actionbar-gryphon-right" },
    Horde = { left = "ui-hud-actionbar-wyvern-left", right = "ui-hud-actionbar-wyvern-right" },
}

local SIDES = { "left", "right" }
local caps = {} -- container -> { left, right }
local boxes = {} -- side -> { frame, texture, inset }

-- How far above the container the sitting caps' frame stands: over the bars,
-- their buttons and the buttons' cooldown and glow children.
local FRONT_LEVELS = 20

local function Cap(container)
    local pair = caps[container]
    if not pair then
        -- The sitting caps draw in front of the bars, the owner's call: a
        -- region draws under its frame's children, so they hang off a frame
        -- of their own. It takes no mouse, so every click reaches the bar.
        local front = CreateFrame("Frame", nil, container)
        front:SetAllPoints(container)
        pair = { front = front }
        for _, side in ipairs(SIDES) do
            local t = container:CreateTexture(nil, "ARTWORK")
            t:SetSnapToPixelGrid(false)
            t:SetTexelSnappingBias(0)
            pair[side] = t
        end
        caps[container] = pair
    end
    return pair
end

function EndCaps.Hide(container)
    local pair = caps[container]
    if not pair then return end
    pair.left:Hide()
    pair.right:Hide()
end

local function Primary()
    local Clusters = ActionBars.Clusters
    return Clusters and Clusters.Find(PRIMARY)
end

local function Field(name, default)
    return function()
        local c = Primary()
        local v = c and c[name]
        if v == nil then return default end
        return v
    end
end

local function Write(name)
    return function(v) ActionBars.Clusters.SetClusterField(PRIMARY, name, v) end
end

--------------------------------------------------------------------------------
-- The Edit Mode boxes
--------------------------------------------------------------------------------
-- A box covers its cap less the part over the bar, so it never sits on the
-- cluster's own box. It is anchored to the cap texture, which is anchored
-- whether the cap shows or not, so the box stays to be clicked while End
-- Caps is off.

local function AnchorBox(box)
    local f, t, inset = box.frame, box.texture, box.inset or 0
    f:ClearAllPoints()
    if box.side == "left" then
        f:SetPoint("TOPRIGHT", t, "TOPRIGHT", -inset, 0)
        f:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 0, 0)
    else
        f:SetPoint("TOPLEFT", t, "TOPLEFT", inset, 0)
        f:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 0, 0)
    end
end

-- The dialog's rows. Style and Scale are absent while End Caps is off, so
-- the toggle re-lists the slot.
local function Mirror()
    local rows = {
        { kind = "toggle", label = "End Caps",
          get = function() return Field("endCaps", false)() and true or false end,
          set = Write("endCaps"), rebuild = true },
    }
    if Field("endCaps", false)() then
        rows[#rows + 1] = { kind = "selector", label = "Style",
            values = EndCaps.STYLE_VALUES, order = EndCaps.STYLE_ORDER,
            get = Field("endCapStyle", "standing"), set = Write("endCapStyle") }
        local r = EndCaps.SCALE_RANGE
        rows[#rows + 1] = { kind = "slider", label = "Scale", min = r.min, max = r.max,
            step = r.step, precision = 0, get = Field("endCapScale", 100), set = Write("endCapScale") }
    end
    return rows
end

-- Nothing is stored and nothing is restored: the key is nil. A position the
-- library writes reaches apply as a drop, which puts the box back on its cap
-- and reports the drop handled.
local NO_STORE = { get = function() return nil end, set = function() end }
local DEFAULT = { point = "CENTER", x = 0, y = 0 }

local function Register(box)
    if box.registered then return end
    local EM = addon.EditMode
    if not (EM and EM.RegisterPositionable) then return end
    box.registered = true
    local selection = EM.RegisterPositionable(box.frame, {
        key = nil,
        default = DEFAULT,
        store = NO_STORE,
        apply = function()
            AnchorBox(box)
            return true
        end,
        positionEditable = function() return false end,
        brand = { mirror = Mirror },
    })
    if selection then selection:RegisterForDrag() end
end

local function Box(side, container, texture)
    local box = boxes[side]
    if not box then
        local f = CreateFrame("Frame", "CamelotActionBarEndCap" .. (side == "left" and "Left" or "Right"), container)
        f.editModeName = side == "left" and "Left End Cap" or "Right End Cap"
        box = { side = side, frame = f }
        boxes[side] = box
    end
    box.texture = texture
    return box
end

--------------------------------------------------------------------------------
-- Apply
--------------------------------------------------------------------------------

-- Size and anchor the pair for the style. Returns the size and the art's
-- name for the report.
local function Lay(pair, container, style, faction, scale)
    local left, right = pair.left, pair.right
    local w, h, inset, name
    left:ClearAllPoints()
    right:ClearAllPoints()
    if style == "sitting" then
        local art = SITTING[faction] or SITTING.Alliance
        w, h, inset = SITTING_W * scale, SITTING_H * scale, SITTING_INSET * scale
        pair.front:SetFrameLevel(container:GetFrameLevel() + FRONT_LEVELS)
        left:SetParent(pair.front)
        right:SetParent(pair.front)
        -- SetAtlas keeps the texture coordinates the standing style set and
        -- reads them inside the atlas rect: left in place they cut the base
        -- off and flip the right cap back. Cleared first.
        left:SetTexCoord(0, 1, 0, 1)
        right:SetTexCoord(0, 1, 0, 1)
        left:SetAtlas(art.left)
        right:SetAtlas(art.right)
        left:SetPoint("BOTTOMRIGHT", container, "BOTTOMLEFT", inset, 0)
        right:SetPoint("BOTTOMLEFT", container, "BOTTOMRIGHT", -inset, 0)
        name = art.left
    else
        local art = STANDING[faction] or STANDING.Alliance
        h = container:GetHeight() * HEIGHT_SHARE * scale
        w = h * art.w / art.h
        inset = art.inset * w
        local u, v = art.w / CANVAS_W, art.h / CANVAS_H
        left:SetParent(container)
        right:SetParent(container)
        left:SetTexture(art.file)
        right:SetTexture(art.file)
        left:SetTexCoord(0, u, 0, v)
        right:SetTexCoord(u, 0, 0, v)
        left:SetPoint("RIGHT", container, "LEFT", inset, 0)
        right:SetPoint("LEFT", container, "RIGHT", -inset, 0)
        name = art == STANDING.Alliance and "gryphon" or "wyvern"
    end
    left:SetSize(w, h)
    right:SetSize(w, h)
    return w, h, inset, name
end

--- Size, anchor and show the pair beside a laid-out container, or hide it,
--- and keep the boxes on the caps. Only cluster 1 carries end caps.
--- Returns the line /camelot actionbars prints under the cluster.
function EndCaps.Apply(cluster, container)
    if cluster.id ~= PRIMARY then
        EndCaps.Hide(container)
        return "end caps: cluster 1 only"
    end

    local faction = UnitFactionGroup("player") or ""
    local style = cluster.endCapStyle == "sitting" and "sitting" or "standing"
    local scale = (cluster.endCapScale or 100) / 100
    local pair = Cap(container)
    local w, h, inset, name = Lay(pair, container, style, faction, scale)

    for _, side in ipairs(SIDES) do
        local box = Box(side, container, pair[side])
        box.inset = inset
        AnchorBox(box)
        Register(box)
    end

    if not cluster.endCaps then
        EndCaps.Hide(container)
        return "end caps off"
    end
    if not STANDING[faction] then
        EndCaps.Hide(container)
        return "end caps hidden: no faction"
    end
    pair.left:Show()
    pair.right:Show()
    return string.format("end caps %s %.0fx%.0f %s, scale %d", style, w, h, name, cluster.endCapScale or 100)
end

-- A neutral Pandaren who picks a side gets the side's caps.
addon.Events.On(ActionBars.OWNER, "NEUTRAL_FACTION_SELECT_RESULT", function()
    if ActionBars.Clusters and ActionBars.Clusters.IsBuilt() then
        ActionBars.Clusters.Rebuild()
    end
end)
