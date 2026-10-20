--------------------------------------------------------------------------------
-- forever/personalresourcedisplay/dynamic.lua
-- The Dynamic Layouts adapters for the Personal Resource Display: plain-tier
-- frames (no secure descendant, clicks off), so every channel switches live
-- in combat, which is where a PRD lives.
--
-- The display is one position and several bars. The frame's own adapter
-- carries position alone; each bar is an adapter of its own on opacity and
-- scale, so a player can keep the cast bar whole while the health and power
-- bars fade. All of them share the display's participation key, one
-- checkbox in the view, and the frame's dialog lists the bars' rows under
-- headers (core/editmode/positionables.lua, `parts`).
--
-- The engine replaces alpha rather than multiplying it, so the Opacity
-- setting is each bar's base and sits on the bars, never on the frame
-- (style.lua, ApplyOpacity). Scale stays on the frame: a bar's base scale is
-- 1, and its dynamic scale multiplies the display's.
--------------------------------------------------------------------------------

local addonName, addon = ...

local PRD = addon.PersonalResourceDisplay
local Style = PRD.Style
local DL = addon.DynamicLayouts
local CBZ = addon.CastBarZ

local Dynamic = {}
PRD.Dynamic = Dynamic

local ID = PRD.KEY

-- The bars and the combo point row, in the dialog's order.
local PARTS = {
    { id = ID .. ".health", label = "Health Bar",
      frame = function() local f = Style.Frame(); return f and Style.Container(f, "health") end },
    { id = ID .. ".power", label = "Power Bar",
      frame = function() local f = Style.Frame(); return f and Style.Container(f, "power") end },
    { id = ID .. ".castBar", label = "Cast Bar",
      frame = function() return PRD.CastBar and PRD.CastBar.Bar() end },
    { id = ID .. ".comboPoints", label = "Combo Points",
      frame = function() return PRD.Combo and PRD.Combo.Row() end },
}
local CAST_BAR_ID = ID .. ".castBar"

local registered = false
local castBarLanded = false

local function baseOpacity()
    return Style.Opacity() / 100
end

local function basePosition()
    local stored = PRD.EditMode and PRD.EditMode.Store.get(ID, addon.EditMode.GetActiveLayoutName())
    local p = stored or Style.DEFAULT_POSITION
    return p.point, p.x, p.y
end

-- The cast bar engine resets the bar's alpha on every cast start and after
-- its fade (castbarz/events.lua, restingAlpha), so the bar's opacity goes
-- through the resting seam forever/castbars/dynamic.lua fills: the engine's
-- last write while it holds the channel, else the setting.
local castResting
if CBZ and CBZ._RestingAlpha then
    local inner = CBZ._RestingAlpha
    CBZ._RestingAlpha = function(bar)
        if PRD.CastBar and bar == PRD.CastBar.Bar() then
            if castResting and DL.HoldsChannel(CAST_BAR_ID, "opacity") then return castResting end
            return baseOpacity()
        end
        return inner(bar)
    end
end

-- A record from before the split put opacity and scale on the frame: each
-- bar takes them, unless it holds its own, and the frame's are cleared.
local function migrateFrameRecord()
    local store = addon.DynamicLayoutsStore
    local rec = store and store.GetRecord and store.GetRecord(ID)
    if not rec then return end
    local opacity, scale = rec.opacity, rec.scale
    if type(opacity) ~= "number" and type(scale) ~= "number" then return end
    for _, part in ipairs(PARTS) do
        local own = store.GetRecord(part.id) or {}
        local fields = {}
        if type(opacity) == "number" and type(own.opacity) ~= "number" then fields.opacity = opacity end
        if type(scale) == "number" and type(own.scale) ~= "number" then fields.scale = scale end
        if next(fields) then store.SetRecord(part.id, fields) end
    end
    -- The frame's position was stored at its dynamic scale; with the scale
    -- gone from the frame it is re-expressed at the base one.
    local fields = { opacity = false, scale = false }
    if type(scale) == "number" and scale > 0 and type(rec.x) == "number" and type(rec.y) == "number" then
        local base = Style.Scale() / 100
        fields.x, fields.y = rec.x * scale / base, rec.y * scale / base
    end
    store.SetRecord(ID, fields)
end

local function partDefinition(part)
    local def = {
        id = part.id,
        label = part.label,
        group = ID,
        frame = part.frame,
        tier = "plain",
        channels = { "opacity", "scale" },
        base = {
            opacity = baseOpacity,
            scale = function() return 1 end,
        },
    }
    if part.id == CAST_BAR_ID then
        def.apply = {
            opacity = function(frame, a)
                castResting = a
                frame:SetAlpha(a)
            end,
        }
    end
    return def
end

--- After the positionable, so its restore has landed before the adapters'
--- snap.
function Dynamic.Register(frame)
    if registered or not (DL and DL.Register) then return end
    registered = true
    migrateFrameRecord()
    local parts = {}
    for _, part in ipairs(PARTS) do parts[#parts + 1] = part.id end
    DL.Register({
        id = ID,
        label = "Personal Resource Display",
        group = ID,
        frame = frame,
        tier = "plain",
        channels = { "position" },
        parts = parts,
        base = {
            position = basePosition,
        },
    })
    for _, part in ipairs(PARTS) do DL.Register(partDefinition(part)) end
end

--- The base geometry was just re-landed (a settings apply, a positionable
--- restore): put a held dynamic scale and position back on top. The cast bar
--- may have been built by that apply, so its state lands now too.
function Dynamic.Reassert()
    if not (registered and DL and DL.Reassert) then return end
    DL.Reassert(ID)
    for _, part in ipairs(PARTS) do DL.Reassert(part.id) end
    -- The cast bar is built on the first apply that switches it on, after
    -- its adapter registered with no frame: its state lands once, whole.
    if not castBarLanded and PRD.CastBar and PRD.CastBar.Bar() then
        castBarLanded = true
        DL.Refresh(CAST_BAR_ID, "snap")
    end
end

--- Whether the engine holds one bar's opacity, so the setting stays off it.
--- `key` is "health", "power", "castBar" or "comboPoints".
function Dynamic.HoldsOpacity(key)
    return registered and DL and DL.HoldsChannel and DL.HoldsChannel(ID .. "." .. key, "opacity") or false
end

--- Whether the dynamic state holds now.
function Dynamic.IsDynamic()
    return registered and DL and DL.IsDynamic and DL.IsDynamic(ID) or false
end

--- A line for /camelot prd.
function Dynamic.Describe()
    if not registered then return "not registered" end
    local held = {}
    for _, part in ipairs(PARTS) do
        local key = part.id:sub(#ID + 2)
        if DL.HoldsChannel(part.id, "opacity") or DL.HoldsChannel(part.id, "scale") then
            held[#held + 1] = key
        end
    end
    return string.format("%s; bars held: %s", Dynamic.IsDynamic() and "dynamic" or "base",
        #held > 0 and table.concat(held, ", ") or "none")
end
