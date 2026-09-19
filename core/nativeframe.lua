--------------------------------------------------------------------------------
-- core/nativeframe.lua
-- Taking a Blizzard frame off screen when a Scoot component replaces it.
--
-- The mechanism is a HIDDEN PARENT, not alpha and not Hide():
--
--   holder = CreateFrame("Frame") ; holder:Hide()
--   blizzardFrame:SetParent(holder)
--
-- A hidden parent removes the whole subtree from the render tree, so it beats
-- alpha in the one place alpha cannot reach -- Blizzard frames that re-assert
-- their own alpha, and child regions flagged ignoreParentAlpha. It is a single
-- C-level call, it writes nothing to the Blizzard frame, and SetParent preserves
-- existing anchors, so restoring the parent puts the frame back exactly where the
-- user had it.
--
-- Deliberately NOT done here:
--
-- * No UnregisterAllEvents. Nothing can list what a frame had registered, so
--   re-arming after it means guessing, and a wrong guess leaves a frame alive
--   but subtly wrong for the session. Events are silenced only by name, from a
--   caller's quiet list, and put back exactly as captured (see THE COMBAT GAP).
-- * No Hide() on a frame that still has its events. On an Edit Mode system
--   frame Hide is a Lua override that writes to the frame's table
--   (EditModeSystemTemplates.lua:35-36); HideBase would dodge that, but Blizzard
--   calls plain Show() on the next update and the fight for the same pixel
--   would resume. A quiet entry may ask for a Hide, because its show events are
--   gone.
-- * No fields written to the Blizzard frame. All state lives in the weak-keyed
--   table below. Writing even one bookkeeping flag onto a system frame is the
--   documented permanent-taint vector.
--
-- Ownership is refcounted, so two components suppressing the same frame cannot
-- release it out from under each other, and a frame is only ever handed back to
-- the parent Scoot took it from.
--
-- NOT EVERY FRAME CAN BE PARKED. A frame whose own code reads fields off its
-- parent breaks the moment the parent is not the one Blizzard built it under:
-- TargetSpellBarMixin:AdjustPosition reads `parentFrame.auraRows > 2`
-- (TargetFrame.lua:1097) and BossSpellBarMixin:AdjustPosition indexes
-- `self:GetParent().powerBarAlt` (:1115) -- against a bare holder those are a
-- nil compare and a nil index, thrown from inside Blizzard's own event handler.
-- Those frames take METHOD "alpha" instead, which is weaker (it must be
-- re-asserted per cast) but is the only option that leaves the parent chain
-- Blizzard's layout code depends on intact. Rule of thumb: park top-level frames,
-- dim frames that are children of a system.
--
-- THE COMBAT GAP. Blizzard re-parents some parked frames itself. The Edit Mode
-- layout pass moves every frame the frame manager owns
-- (ApplySystemAnchor -> BreakFromFrameManager -> SetParent(UIParent),
-- EditModeSystemTemplates.lua:335-365), PlayerCastingBarFrame and
-- BossTargetFrameContainer among them, and it runs on EDIT_MODE_LAYOUTS_UPDATED
-- and PLAYER_SPECIALIZATION_CHANGED, in combat too. Every re-park here skips
-- combat, so a pass that lands mid-fight leaves Blizzard's frame on screen
-- until PLAYER_REGEN_ENABLED.
--
-- A "park" claim closes that gap with a QUIET list: entries of
-- { frame = f, events = { ... }, hide = true }. Park unregisters each named
-- event after capturing its registration with IsEventRegistered, units
-- included, and Unpark registers each one again exactly as captured. A frame
-- with no events left to show itself stays hidden wherever Blizzard puts it.
-- The caller owns the list and cites where Blizzard registers each event.
--------------------------------------------------------------------------------

local addonName, addon = ...

local NativeFrame = {}
addon.NativeFrame = NativeFrame

-- External, weak-keyed. Never write to a Blizzard frame's own table.
local data = setmetatable({}, { __mode = "k" })

local function State(frame)
    local d = data[frame]
    if not d then
        d = { owners = {} }
        data[frame] = d
    end
    return d
end

local holder

local function Holder()
    if not holder then
        -- Parented and sized rather than bare: a parentless, pointless frame gives
        -- its children no valid rect, and anything that measures a parked frame
        -- then reads nil. Hidden, so the subtree still never renders.
        holder = CreateFrame("Frame", nil, UIParent)
        holder:SetAllPoints(UIParent)
        holder:Hide()
    end
    return holder
end

--- True while Blizzard's Edit Mode manager is on screen, opening, or exiting.
---
--- Re-parenting is banned in that window. SetParent runs Blizzard's layout
--- handlers synchronously, in addon execution, and the Edit Mode manager carries
--- state into its next pass -- so a re-parent from addon context there taints the
--- manager rather than just the frame. Every skipped write is picked up by
--- Reapply() on Edit Mode close. The canonical check covers the opening and
--- exiting transition windows, which the old IsShown-only probe missed.
---
--- Resolved per call. A host that does not load core/editmode/core.lua has no
--- canonical check, and falls back to LibEditMode's own flag, which lacks the
--- transition windows; the regen and world-entered Reapply covers those.
local function EditModeOpen()
    local em = addon.EditMode
    local fn = em and (em.IsEditModeActiveOrOpening or em.IsEditing)
    if type(fn) ~= "function" then return false end
    return fn() == true
end

local function Resolve(frame)
    if type(frame) ~= "table" or type(frame.SetParent) ~= "function" then
        return nil
    end
    if frame.IsForbidden and frame:IsForbidden() then return nil end
    return frame
end

--------------------------------------------------------------------------------
-- The Edit Mode selection box
--------------------------------------------------------------------------------

--- Hide or restore a system frame's green Edit Mode outline.
---
--- Needs its own treatment because `EditModeSystemSelectionBaseTemplate` carries
--- ignoreParentAlpha="true" (EditModeSystemTemplates.xml:11). That defeats alpha
--- on the parent -- though not a hidden parent -- and matters in the window where
--- the frame is deliberately NOT parked: while Edit Mode is open.
---
--- EnableMouse(false) is not decoration. Alpha alone leaves an invisible box that
--- still swallows clicks and still shows its tooltip, which is worse than leaving
--- it visible.
local function ApplySelection(frame, suppress)
    local selection = frame.Selection
    if type(selection) ~= "table" or type(selection.SetAlpha) ~= "function" then
        return
    end

    -- The Selection box is an XML child of a system frame that inherits
    -- SecureUnitButtonTemplate (PlayerFrame.xml:14), so it is protected by
    -- parentage and EnableMouse on it is combat-blocked. This path is genuinely
    -- reachable in lockdown: Reapply runs from both Edit Mode callbacks, and
    -- CanEnterEditMode (EditModeManager.lua:1636-1655) has no lockdown check, so
    -- Edit Mode opens and closes mid-fight. Skipping whole rather than dropping
    -- only the mouse write is deliberate, per the note above: an invisible box
    -- that still swallows clicks is worse than a visible one. Nothing is lost --
    -- the state flags are untouched, so the PLAYER_REGEN_ENABLED Reapply below
    -- re-runs Park/Unpark and lands the writes then.
    if InCombatLockdown() then return end

    local d = State(selection)

    if suppress then
        if not d.selectionSuppressed then
            d.restoreAlpha = selection:GetAlpha()
            d.restoreMouse = selection:IsMouseEnabled()
            d.selectionSuppressed = true
        end
        selection:SetAlpha(0)
        selection:EnableMouse(false)

        if not d.showHooked then
            d.showHooked = true
            -- Kept off addon.Enforce: NativeFrame parks or dims whole system frames; Enforce is for regions below that level.
            -- Hooking a system frame's child is Rule 11 territory, and the rule's
            -- real content is "write nothing inside Blizzard's execution" -- this
            -- Show fires inside Edit Mode's own ShowSystemSelections pass. Hence
            -- the deferral: the hook observes, the timer writes.
            hooksecurefunc(selection, "Show", function(self)
                C_Timer.After(0, function()
                    if InCombatLockdown() then return end
                    if State(self).selectionSuppressed then
                        self:SetAlpha(0)
                        self:EnableMouse(false)
                    end
                end)
            end)
        end
        return
    end

    if d.selectionSuppressed then
        d.selectionSuppressed = false
        selection:SetAlpha(d.restoreAlpha or 1)
        selection:EnableMouse(d.restoreMouse or false)
    end
end

--------------------------------------------------------------------------------
-- Park / unpark
--------------------------------------------------------------------------------

--- METHOD "alpha": for frames that cannot survive losing their parent.
---
--- Weaker than parking and knowingly so. Blizzard re-asserts its own alpha from
--- the cast-start path (CastingBarMixin:ApplyAlpha(1.0), CastingBarFrame.lua:365),
--- so the caller has to re-assert per cast; Reapply(frame) is that seam. Deferred
--- for ordering: Blizzard's write is driven by the same event the caller hears and
--- inter-frame event order is undefined, so re-asserting inline is a coin flip.
local function Dim(frame)
    local d = State(frame)
    if d.restoreAlpha == nil then
        d.restoreAlpha = frame:GetAlpha()
    end
    d.parked = true
    C_Timer.After(0, function()
        if State(frame).parked then frame:SetAlpha(0) end
    end)
end

local function Undim(frame)
    local d = State(frame)
    d.parked = false
    frame:SetAlpha(d.restoreAlpha or 1)
    d.restoreAlpha = nil
end

--- Silence the events a claim's quiet list names, and hide what it asks for.
---
--- Runs under the same gate as the re-park, and after it, so a Hide lands on a
--- frame the holder has already taken off screen. Safe to repeat: a
--- registration is captured once, and an event registered again since is
--- removed again.
local function Quiet(d)
    local quiet = d.quiet
    if not quiet or InCombatLockdown() or EditModeOpen() then return end

    d.captured = d.captured or {}
    for _, entry in ipairs(quiet) do
        local frame = Resolve(entry.frame)
        if frame then
            local captured = d.captured[frame] or {}
            d.captured[frame] = captured
            for _, event in ipairs(entry.events) do
                if frame:IsEventRegistered(event) then
                    if not captured[event] then
                        -- The returns after the first are the units the
                        -- registration filters on; none means RegisterEvent.
                        captured[event] = { select(2, frame:IsEventRegistered(event)) }
                    end
                    frame:UnregisterEvent(event)
                end
            end
            -- Only while nothing is drawn. The engine fires OnHide when a frame
            -- goes from visible to hidden, so hiding a frame whose ancestor is
            -- already hidden runs no Blizzard handler in addon execution (a boss
            -- frame's OnHide lays out the container). HideBase is the C-level
            -- Hide a system frame keeps next to its table-writing override.
            if entry.hide and frame:IsShown() and not frame:IsVisible() then
                local hide = frame.HideBase or frame.Hide
                hide(frame)
            end
        end
    end
end

--- Register every captured event again, as it was captured.
---
--- A frame Quiet hid stays hidden until Blizzard's next show event for it: the
--- next cast, or the next boss engage.
local function Unquiet(d)
    local captured = d.captured
    if not captured then return end
    d.captured = nil

    for frame, events in pairs(captured) do
        for event, units in pairs(events) do
            if units[1] then
                frame:RegisterUnitEvent(event, unpack(units))
            else
                -- Kept off addon.Events: this restores a Blizzard frame's own registration, not a Scoot handler.
                frame:RegisterEvent(event)
            end
        end
    end
end

local function Park(frame)
    local d = State(frame)
    local hidden = Holder()

    if frame:GetParent() ~= hidden then
        -- Captured once, before the first move, so a second Suppress() while
        -- already parked cannot overwrite the real parent with the holder.
        if d.origParent == nil then
            d.origParent = frame:GetParent()
        end
        if not InCombatLockdown() and not EditModeOpen() then
            frame:SetParent(hidden)
        end
    end

    if not d.setParentHooked then
        d.setParentHooked = true
        -- Blizzard re-parents its own frames on layout and Edit Mode changes
        -- (EditModeCastBarSystemMixin:UpdateSystemSettingLockToPlayerFrame calls
        -- SetParent(UIParent) outright). Observe here, write a frame later.
        hooksecurefunc(frame, "SetParent", function(self, newParent)
            local s = data[self]
            if not s or not s.parked then return end
            if newParent == holder then return end
            C_Timer.After(0, function()
                local cur = data[self]
                if cur and cur.parked and not InCombatLockdown() and not EditModeOpen()
                    and self:GetParent() ~= holder then
                    self:SetParent(holder)
                end
            end)
        end)
    end

    d.parked = true
    ApplySelection(frame, true)
    Quiet(d)
end

local function Unpark(frame)
    local d = State(frame)
    d.parked = false
    ApplySelection(frame, false)

    if InCombatLockdown() or EditModeOpen() then return end

    -- Before the ownership check below: the silenced events are Scoot's own
    -- write, and they go back whoever holds the frame now.
    Unquiet(d)

    -- Only ever hand back a frame Scoot itself parked. If something else has
    -- since taken it, resurrecting it would put two bars on screen -- the exact
    -- bug this whole facility exists to prevent.
    if holder and frame:GetParent() ~= holder then
        d.origParent = nil
        return
    end

    -- Never restore into a parent that is itself hidden. Blizzard parents the
    -- cast bar under PlayerFrame and Edit Mode moves it into layout frames that
    -- are hidden outside Edit Mode; handing it back there leaves the frame fully
    -- armed and permanently invisible, which is indistinguishable from the
    -- suppression never lifting. UIParent is where Edit Mode positions it from
    -- anyway, and SetParent keeps the anchors, so it lands where the user had it.
    local restore = d.origParent
    if type(restore) ~= "table" or not restore.IsVisible or not restore:IsVisible() then
        restore = UIParent
    end

    frame:SetParent(restore)
    d.origParent = nil
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Take a Blizzard frame off screen on behalf of `owner`.
--- Refcounted: the frame comes back only when every owner has released it.
---
--- `method` is "park" (default, hidden parent) or "alpha". Use "alpha" for any
--- frame whose own code reads its parent -- see the header note on the spell bars.
---
--- `quiet` is an optional list for "park" claims, one entry per frame:
--- { frame = f, events = { ... }, hide = true }. See THE COMBAT GAP in the header.
function NativeFrame:Suppress(frame, owner, method, quiet)
    frame = Resolve(frame)
    if not frame or not owner then return false end

    local d = State(frame)
    d.owners[owner] = true
    d.method = method or d.method or "park"
    if quiet then d.quiet = quiet end

    if d.method == "alpha" then
        Dim(frame)
    else
        Park(frame)
    end
    return true
end

--- Drop `owner`'s claim. Restores the frame when no owner is left.
--- A frame Scoot never suppressed is never written to, so zero-touch holds.
function NativeFrame:Release(frame, owner)
    frame = Resolve(frame)
    if not frame or not owner then return false end

    local d = data[frame]
    if not d then return false end

    d.owners[owner] = nil
    if next(d.owners) == nil and d.parked then
        if d.method == "alpha" then
            Undim(frame)
        else
            Unpark(frame)
        end
    end
    return true
end

function NativeFrame:IsSuppressed(frame)
    local d = frame and data[frame]
    return (d and d.parked) or false
end

--- Re-run one claim, or every claim currently in force.
---
--- The catch-all for writes skipped by the combat and Edit Mode gates, for
--- Blizzard re-parenting a frame unobserved, and -- with a frame
--- argument -- for the per-cast alpha re-assert that "alpha" method frames need.
--- Safe to call freely: it only touches frames Scoot already owns.
function NativeFrame:Reapply(frame)
    if frame then
        local d = data[frame]
        if not d or not d.parked then return end
        if d.method == "alpha" then Dim(frame) else Park(frame) end
        return
    end

    for f, d in pairs(data) do
        if d.parked then
            if d.method == "alpha" then Dim(f) else Park(f) end
        elseif d.origParent ~= nil or d.captured then
            Unpark(f)
        end
    end
end

local function reapplyAll()
    NativeFrame:Reapply()
end
addon.Events.On("NativeFrame", "PLAYER_ENTERING_WORLD", reapplyAll)
addon.Events.On("NativeFrame", "PLAYER_REGEN_ENABLED", reapplyAll)
