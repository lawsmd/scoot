-- scootauras/underlay.lua - Missing-state visuals for debuff trackers
--
-- "When it's missing, show..." (tracker.missingVisual, vocabulary in
-- core.lua). The engine cannot report a missing aura: the button's shown state
-- is a secret boolean, so no Lua branch on presence exists. The visual is a
-- reveal instead: a Scoot-owned element set on entry.visual at a frame level
-- below the container, painted to match the live art. While the aura is up the
-- engine button draws over it; when the slot empties the engine hides the
-- button and uncovers it. Lua never branches on presence, which also means the
-- blink runs behind the shown button and a translucent style (the default bar
-- background is 50%) lets the underlay read through while the aura is up.
--
-- Everything here is Tier 1 (Scoot frames only): build, restyle and gate run
-- mid-combat and never wait on the structural gate. The combat gate is not
-- read here; hiding the shell/visual (styling.lua) takes the underlay with it.
-- The unit gate IS read here: UnitExists is plain, and a "missing" warning
-- with no unit at all is noise, so target/focus trackers hide the underlay
-- until their unit exists (events.lua refreshes it on retarget).
local addonName, addon = ...

local SAU = addon.ScootAuras
local Engine = SAU.Engine

local Underlay = {}
SAU.Underlay = Underlay

-- One cadence for every reveal blink (missing.lua exports its constants).
local BLINK_LOW_ALPHA = (SAU.Missing and SAU.Missing.BLINK_LOW_ALPHA) or 0.15
local BLINK_SECONDS = (SAU.Missing and SAU.Missing.BLINK_SECONDS) or 0.5

--------------------------------------------------------------------------------
-- Scoot-owned art (per pool entry, session-permanent)
--------------------------------------------------------------------------------

local function EnsureUnderlay(entry)
    if entry.underlay then return entry.underlay end
    local visual = entry.visual

    -- Above the cadence lock bar and the missing-buff clip (visual + 1), below
    -- the container (visual + 5) and the Edit Mode preview (visual + 10).
    local root = CreateFrame("Frame", nil, visual)
    root:SetAllPoints(visual)
    root:SetFrameLevel(visual:GetFrameLevel() + 2)
    root:Hide()

    local set = Engine.BuildElementSet(root)

    local blink = root:CreateAnimationGroup()
    blink:SetLooping("BOUNCE")
    local alpha = blink:CreateAnimation("Alpha")
    alpha:SetFromAlpha(1)
    alpha:SetToAlpha(BLINK_LOW_ALPHA)
    alpha:SetDuration(BLINK_SECONDS)

    entry.underlay = {
        root = root,
        elements = set.elements,
        textFrame = set.textFrame,
        blink = blink,
    }
    return entry.underlay
end

--------------------------------------------------------------------------------
-- Variant paint (after the shared chain; every pass settles every element)
--------------------------------------------------------------------------------

-- A vertex-colored white mask ignores SetDesaturated; graying the tint by
-- luminance is what reads as desaturated on shape art.
local function Luminance(r, g, b)
    return 0.299 * (r or 1) + 0.587 * (g or 1) + 0.114 * (b or 1)
end

local function PaintVariant(trackerId, tracker, u, traits)
    local db = SAU.GetDB(trackerId)

    local texElem, barElem
    for _, elem in ipairs(u.elements) do
        if elem.type == "texture" then
            texElem = elem
        elseif elem.type == "bar" then
            barElem = elem
        elseif elem.type == "text" then
            -- The reveal carries no duration, name, or stacks.
            elem.widget:Hide()
        elseif elem.type == "cooldown" then
            -- No duration exists while missing; the swipe never runs here.
            pcall(elem.widget.Clear, elem.widget)
            elem.widget:Hide()
        end
    end
    if barElem then
        -- This set is never engine-bound, so the fill holds 0; hidden anyway,
        -- with the cadence pieces the live bar may use.
        barElem.barFill:Hide()
        barElem.lockClip:Hide()
        barElem.lockOverlay:Hide()
    end

    if traits.art == "emptybar" then
        -- Background and borders as the chain styled them, no fill, and no
        -- side icon: a full-color icon beside an empty bar reads as present.
        if barElem then barElem.widget:Show() end
        if texElem then
            texElem.widget:Hide()
            if texElem.borderFrame then texElem.borderFrame:Hide() end
        end
    elseif traits.art == "baricon" then
        -- The bar frame is hidden (its borders are its children and vanish
        -- with it) but keeps the rect the layout gave it, and the icon centers
        -- on that rect. Painted here rather than by the chain, which skips the
        -- icon whenever Show Icon is off; the Icon tab's settings still apply,
        -- and its border follows the icon via SetAllPoints (ApplyBorders).
        if barElem then barElem.widget:Hide() end
        if texElem then
            local w = texElem.widget
            w:SetTexture(SAU._SpellIcon(tracker.spellId))
            w:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            w:SetVertexColor(1, 1, 1, 1)
            w:SetDesaturated(traits.desat == true)
            local size = tonumber(db and db.iconSize) or 32
            w:ClearAllPoints()
            -- The bar's icon stays square (layout.lua).
            w:SetSize(size, size)
            if barElem then
                w:SetPoint("CENTER", barElem.widget, "CENTER", 0, 0)
            else
                w:SetPoint("CENTER", u.root, "CENTER", 0, 0)
            end
            w:Show()
        end
    else
        -- "self": the shape's own art, desaturated when asked. The chain
        -- resets desaturation and tint every pass, so this runs after it.
        if texElem then
            if tracker.shape == "shape" then
                if traits.desat and db and SAU._ResolveShapeColor then
                    local r, g, b, a = SAU._ResolveShapeColor(db)
                    local gray = Luminance(r, g, b)
                    texElem.widget:SetVertexColor(gray, gray, gray, a or 1)
                    texElem.widget:SetDesaturated(true)
                end
            else
                texElem.widget:SetDesaturated(traits.desat == true)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Restyle, gate, lifecycle
--------------------------------------------------------------------------------

--- Alpha for the reveal root, 1 for every token that does not carry the
-- Opacity sub-option. The root is a child of the visual, so this multiplies
-- with the tracker's own opacity (styling.lua) instead of replacing it: a
-- tracker at 60% with a 50% reveal shows the reveal at 30% of full.
local function RevealAlpha(trackerId, traits)
    if not (traits and traits.opacity) then return 1 end
    local db = SAU.GetDB(trackerId)
    local pct = tonumber(db and db.missingVisualOpacity) or 100
    if pct < 0 then pct = 0 elseif pct > 100 then pct = 100 end
    return pct / 100
end

--- Full Tier 1 pass for one live tracker: build the art on first use, run the
-- shared styling/layout chain on it, settle the variant, apply the gate.
function Underlay.Restyle(trackerId, tracker, state)
    local entry = state and state.entry
    if not entry then return end
    local u = EnsureUnderlay(entry)
    local traits = SAU.MissingVisualTraits(SAU.MissingVisualFor(tracker))
    if not traits then
        Underlay.UpdateGate(trackerId)
        return
    end

    -- The chain reads exactly these state fields. The REAL entry rides along
    -- so SetHostSize writes hostW/hostH where the group layout reads them
    -- (idempotent with the live pass: same db, same numbers). No lockBar: the
    -- live pass owns its placement. Text styling is skipped; nothing textual
    -- ever shows here.
    local shim = { container = u.root, elements = u.elements, entry = entry }
    SAU._ApplyIconMode(trackerId, tracker, shim)
    SAU._ApplyShapeStyling(trackerId, tracker, shim)
    SAU._ApplyBorders(trackerId, tracker, shim)
    SAU._ApplyBarStyling(trackerId, tracker, shim)
    SAU._LayoutElements(trackerId, tracker, shim)
    PaintVariant(trackerId, tracker, u, traits)
    Underlay.UpdateGate(trackerId)
end

--- The one entry point from ApplyStyling. Runs for every non-missingbuff
-- kind, so a tracker whose token resolved away (kind flip, shape flip, or a
-- previous occupant's art) still hides its underlay.
function Underlay.Sync(trackerId, tracker, state)
    if SAU.MissingVisualFor(tracker) ~= "none" then
        Underlay.Restyle(trackerId, tracker, state)
    else
        Underlay.UpdateGate(trackerId)
    end
end

--- Plain state only, never presence: this decides whether the reveal exists
-- at all; the engine button decides what covers it. The combat gate is not
-- consulted (the shell hide carries the underlay down). Safe for any tracker
-- id; an occupant of an entry that never built one is a no-op.
function Underlay.UpdateGate(trackerId)
    local state = SAU._activeStates[trackerId]
    local entry = state and state.entry
    local u = entry and entry.underlay
    if not u then return end

    local tracker = SAU.GetTracker(trackerId)
    local token = SAU.MissingVisualFor(tracker)
    local traits = SAU.MissingVisualTraits(token)
    local show = traits ~= nil
        and SAU.IsTrackerActive(trackerId, tracker)
        and SAU.IsModuleActive()
    if show and SAU._isEditModeActive and SAU._isEditModeActive() then
        -- The Edit Mode preview stands in for the live art.
        show = false
    end
    -- No unit, no warning. UnitExists is plain and never touches aura data.
    if show and (tracker.unit == "target" or tracker.unit == "focus")
        and not UnitExists(tracker.unit) then
        show = false
    end

    u.root:SetShown(show)

    if Engine._SetResult then
        Engine._SetResult("underlay.t" .. trackerId,
            token .. (show and " shown" or " hidden"))
    end

    local wantBlink = show and traits ~= nil and traits.blink == true
    if wantBlink then
        if not u.blink:IsPlaying() then u.blink:Play() end
    else
        if u.blink:IsPlaying() then u.blink:Stop() end
        -- Set after the stop: an Alpha animation drives the root while it
        -- plays and hands the value back on Stop.
        u.root:SetAlpha(RevealAlpha(trackerId, traits))
    end
end

--- Retarget and refocus: re-evaluate the unit half of the gate for trackers
-- bound to that unit. The engine kick beside this call refreshes the
-- container; this refreshes the reveal.
function Underlay.RefreshUnit(unitToken)
    for trackerId in pairs(SAU._activeStates) do
        local tracker = SAU.GetTracker(trackerId)
        if tracker and tracker.unit == unitToken then
            Underlay.UpdateGate(trackerId)
        end
    end
end

-- The art is not torn down: pool frames are session-permanent, and the next
-- occupant's Sync repaints it or leaves it hidden.
function Underlay.OnEntryReleased(entry)
    local u = entry.underlay
    if not u then return end
    u.root:Hide()
    if u.blink:IsPlaying() then u.blink:Stop() end
    u.root:SetAlpha(1)
end
