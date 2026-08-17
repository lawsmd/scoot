-- scootauras/regions.lua - Element creation and engine bindings for slot buttons
--
-- Every visual element lives under the engine-managed button so its secret
-- show/hide propagates natively; the addon never branches on aura presence.
-- All element types exist on every tracker; the shape only changes bindings
-- and visibility, so a shape edit is a rebind, never a rebuild.
local addonName, addon = ...

local SAU = addon.ScootAuras
local Engine = SAU.Engine

local SafeToString = Engine._SafeToString
local SetResult = Engine._SetResult

local DIR_ELAPSED = (Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime) or 0
local DIR_REMAINING = (Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime) or 1

--------------------------------------------------------------------------------
-- Element creators
--------------------------------------------------------------------------------

local function CreateTextElement(parent, elemDef, textParent)
    local fs = (textParent or parent):CreateFontString(nil, "OVERLAY")
    local fontFace = addon.ResolveFontFace("FRIZQT__")
    addon.ApplyFontStyle(fs, fontFace, elemDef.baseSize or 24, "OUTLINE")
    if elemDef.justifyH then
        fs:SetJustifyH(elemDef.justifyH)
    end
    fs:Hide()
    return { type = "text", widget = fs, def = elemDef }
end

local function CreateTextureElement(parent, elemDef)
    local tex = parent:CreateTexture(nil, "ARTWORK")
    local size = elemDef.defaultSize or { 32, 32 }
    tex:SetSize(size[1], size[2])
    tex:Hide()
    return { type = "texture", widget = tex, def = elemDef }
end

local function CreateBarElement(parent, elemDef)
    local barRegion = CreateFrame("Frame", nil, parent)
    local size = elemDef.defaultSize or { 120, 12 }
    barRegion:SetSize(size[1], size[2])

    local barBg = barRegion:CreateTexture(nil, "BACKGROUND", nil, -1)
    barBg:SetAllPoints(barRegion)

    -- Cadence lock geometry (cadence.lua). Both clips are neutral here and are
    -- re-anchored by BindForMode (structural gate) to the lock bar, which
    -- lives outside the button tree and holds remaining / original as a
    -- secret-fed StatusBar:
    --   deplete: barFill inside barClip anchored to the lock bar's fill;
    --            visible = min(lock, engine)
    --   fill:    lockOverlay inside lockClip, drawn under barFill; the lock
    --            bar is reverse-filled and lockClip spans from its left edge
    --            to its texture's left edge (the elapsed share);
    --            visible = max(lock, engine)
    -- lockOverlay spans the full bar so its texcoords stay intact; the clip
    -- does the cutting. It draws at barRegion's level so it sits above barBg
    -- and below barFill.
    local lockClip = CreateFrame("Frame", nil, barRegion)
    lockClip:SetClipsChildren(true)
    lockClip:SetFrameLevel(barRegion:GetFrameLevel())
    lockClip:SetAllPoints(barRegion)
    lockClip:Hide()
    local lockOverlay = lockClip:CreateTexture(nil, "ARTWORK")
    lockOverlay:SetAllPoints(barRegion)

    local barClip = CreateFrame("Frame", nil, barRegion)
    barClip:SetClipsChildren(true)
    barClip:SetAllPoints(barRegion)

    -- Created under barClip from the start: ChangeParent is forbidden once the
    -- engine binds the bar. Same rect and level as before (barRegion + 1).
    local barFill = CreateFrame("StatusBar", nil, barClip)
    barFill:SetFrameLevel(barRegion:GetFrameLevel() + 1)
    barFill:SetAllPoints(barRegion)
    barFill:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    barFill:SetMinMaxValues(0, 1)
    barFill:SetValue(0)

    barRegion:Hide()

    return {
        type = "bar",
        widget = barRegion,
        barFill = barFill,
        barBg = barBg,
        barClip = barClip,
        lockClip = lockClip,
        lockOverlay = lockOverlay,
        def = elemDef,
    }
end

-- Drain swipe host: a native Cooldown clipped to its parent. On the live
-- button the engine drives it through SetDurationCooldown, and the swipe
-- animation is C-side, so it keeps ticking while the button subtree is denied
-- in combat. The Edit Mode preview reuses the same recipe on its own frame.
local function CreateDrainCooldown(parent)
    local drain = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
    drain:SetAllPoints(parent)
    drain:SetFrameLevel(parent:GetFrameLevel() + 1)
    drain:SetDrawEdge(false)
    drain:SetDrawBling(false)
    drain:SetHideCountdownNumbers(true)
    drain:SetReverse(true)
    drain:SetDrawSwipe(false)
    return drain
end

-- Icon border frame structure ApplyBorders expects, parented to the button so
-- it hides with it.
local function PreCreateIconBorder(elem, button)
    if elem.type ~= "texture" or elem.borderFrame then return end
    local bf = CreateFrame("Frame", nil, button)
    bf:SetFrameLevel(button:GetFrameLevel() + 2)
    bf.borderEdges = {
        Top = bf:CreateTexture(nil, "OVERLAY", nil, 1),
        Bottom = bf:CreateTexture(nil, "OVERLAY", nil, 1),
        Left = bf:CreateTexture(nil, "OVERLAY", nil, 1),
        Right = bf:CreateTexture(nil, "OVERLAY", nil, 1),
    }
    for _, tex in pairs(bf.borderEdges) do tex:Hide() end
    bf.atlasBorder = bf:CreateTexture(nil, "OVERLAY", nil, 2)
    bf.atlasBorder:Hide()
    elem.borderFrame = bf
end

--------------------------------------------------------------------------------
-- Region creation (runs inside the slot's initializeFrame)
--------------------------------------------------------------------------------

-- Builds entry.elements/entry.textFrame under the button. Called from
-- initializeFrame, where the button tree is guaranteed touchable.
function Engine.WireButton(trackerId, tracker, state, entry, button)
    button:ClearAllPoints()
    button:SetAllPoints(state.container)

    local textHost = CreateFrame("Frame", nil, button)
    textHost:SetAllPoints(button)
    textHost:SetFrameLevel(button:GetFrameLevel() + 4)
    entry.textFrame = textHost
    state.textFrame = textHost

    local elements = entry.elements
    if not elements then
        elements = {}
        entry.elements = elements
    end

    table.insert(elements, CreateTextureElement(button, {
        type = "texture", key = "icon", defaultSize = { 32, 32 },
    }))
    PreCreateIconBorder(elements[#elements], button)

    table.insert(elements, CreateTextElement(button, {
        type = "text", key = "duration", source = "duration", baseSize = 24,
    }, textHost))

    table.insert(elements, CreateBarElement(button, {
        type = "bar", key = "durationBar", source = "duration", defaultSize = { 120, 12 },
    }))
    -- Cadence lock: start the tracker's record now; Configure reads the bound
    -- bar's duration object later, under the structural gate.
    if SAU.Cadence then
        SAU.Cadence.OnWire(entry)
    end

    table.insert(elements, CreateTextElement(button, {
        type = "text", key = "name", source = "name", baseSize = 10,
    }, textHost))

    -- Stack count; the wire-time corner anchor is a pre-layout default only
    -- (LayoutElements repositions it per the stackText* settings). It must not
    -- start unanchored: initializeFrame can fire while ApplyAll is gated.
    local stacks = CreateTextElement(button, {
        type = "text", key = "stacks", source = "applications", baseSize = 14,
    }, textHost)
    stacks.widget:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    stacks.widget:Show()
    table.insert(elements, stacks)

    -- Drain swipe host (shape trackers); the engine drives it through
    -- SetDurationCooldown.
    table.insert(elements, { type = "cooldown", widget = CreateDrainCooldown(button), def = { key = "drain" } })

    state.elements = elements
end

--------------------------------------------------------------------------------
-- Engine bindings per shape
--------------------------------------------------------------------------------

local function CallBinding(trackerId, button, methodName, region, options)
    local fn = button[methodName]
    if not fn then
        SetResult("bind.t" .. trackerId .. "." .. methodName, "method missing")
        return false
    end
    local ok, err
    if options ~= nil then
        ok, err = pcall(fn, button, region, options)
    elseif region ~= nil then
        ok, err = pcall(fn, button, region)
    else
        ok, err = pcall(fn, button)
    end
    if not ok then
        SetResult("bind.t" .. trackerId .. "." .. methodName, "FAILED: " .. SafeToString(err))
    end
    return ok
end

-- Binds or clears each element against the button per the tracker's shape.
-- Caller must hold the structural gate (ApplyAll does).
function Engine.BindForMode(trackerId, tracker, state)
    local entry = Engine._byTracker[trackerId]
    if not entry or not entry.button then return end
    local db = SAU.GetDB(trackerId)
    if not db then return end
    local button = entry.button
    local vis = SAU.ResolveVisibility(tracker, db)

    if vis.missing then
        -- Missing-buff trackers own no button (EnsureBuilt adds a gate group,
        -- not a slot) and bind nothing; the visible reminder is Scoot-owned
        -- (missing.lua). Guarded here for an entry that once had a button.
        return
    end

    for _, elem in ipairs(state.elements or {}) do
        if elem.type == "texture" then
            if tracker.shape == "shape" then
                -- The atlas art is Scoot-owned; the engine must not stamp the
                -- matched aura's icon over it.
                CallBinding(trackerId, button, "ClearIcon")
            elseif vis.showIcon and (db.iconMode or "default") == "default" then
                CallBinding(trackerId, button, "SetIcon", elem.widget)
            else
                CallBinding(trackerId, button, "ClearIcon")
            end
        elseif elem.type == "text" then
            local source = elem.def.source
            if source == "duration" then
                if vis.showText then
                    CallBinding(trackerId, button, "SetDurationText", elem.widget, {})
                else
                    CallBinding(trackerId, button, "ClearDurationText")
                end
            elseif source == "applications" then
                if vis.showStacks then
                    CallBinding(trackerId, button, "SetApplicationCount", elem.widget)
                else
                    CallBinding(trackerId, button, "ClearApplicationCount")
                end
            elseif source == "name" then
                if vis.showName then
                    CallBinding(trackerId, button, "SetSpellName", elem.widget)
                else
                    CallBinding(trackerId, button, "ClearSpellName")
                end
            end
        elseif elem.type == "bar" then
            local fillMode = (db.barFillMode == "fill")
            -- Cadence lock geometry (see CreateBarElement). The lock bar is
            -- outside the tree; only its fill texture is referenced here, and
            -- only under the gate, so re-anchoring the in-tree clips is legal.
            local lockBar = (vis.showBar and db.barLockCadence == true) and state.lockBar or nil
            local lockTex = lockBar and lockBar:GetStatusBarTexture() or nil
            state.cadenceGeometry = lockTex and (fillMode and "fill-lock" or "deplete-lock") or "neutral"
            if elem.barClip then
                elem.barClip:ClearAllPoints()
                if lockTex and not fillMode then
                    elem.barClip:SetAllPoints(lockTex)
                else
                    elem.barClip:SetAllPoints(elem.widget)
                end
            end
            if elem.lockClip then
                if lockTex and fillMode then
                    -- The lock bar is reverse-filled in fill mode
                    -- (Cadence.Configure): its texture is the remaining share
                    -- on the right, so left edge to texture left edge = elapsed.
                    elem.lockClip:ClearAllPoints()
                    elem.lockClip:SetPoint("TOPLEFT", lockBar, "TOPLEFT", 0, 0)
                    elem.lockClip:SetPoint("BOTTOMRIGHT", lockTex, "BOTTOMLEFT", 0, 0)
                    elem.lockClip:Show()
                else
                    elem.lockClip:Hide()
                    elem.lockClip:ClearAllPoints()
                    elem.lockClip:SetAllPoints(elem.widget)
                end
            end
            if vis.showBar then
                local direction = fillMode and DIR_ELAPSED or DIR_REMAINING
                -- Cadence.Configure (right after this pass) asks this bar for
                -- the duration object it was just timed with, so the binding
                -- must precede it.
                CallBinding(trackerId, button, "SetDurationBar", elem.barFill, { direction = direction })
            else
                CallBinding(trackerId, button, "ClearDurationBar")
            end
        elseif elem.type == "cooldown" then
            if tracker.shape == "shape" and db.shapeShowDrain ~= false then
                CallBinding(trackerId, button, "SetDurationCooldown", elem.widget)
            else
                CallBinding(trackerId, button, "ClearDurationCooldown")
                pcall(elem.widget.Clear, elem.widget)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Edit Mode preview (Scoot-side art; engine buttons cannot fake auras)
--------------------------------------------------------------------------------
-- A second element set with the same record shapes as WireButton, parented
-- under a Scoot-owned frame instead of the engine button, so the real
-- styling/layout chain applies to it unchanged and the preview matches the
-- live tracker by construction. Cached per pool entry: pool frames are
-- session-permanent, and every Show pass re-runs the full chain, so reuse
-- across occupants is safe.

--- A Scoot-owned element set with the same record shapes as WireButton, under
-- `root` (a Scoot frame, never the engine button), so the styling/layout chain
-- runs on it unchanged. Used by the Edit Mode preview and by the missing-buff
-- visual (missing.lua). Returns { root, textFrame, elements }.
function Engine.BuildElementSet(root)
    local textHost = CreateFrame("Frame", nil, root)
    textHost:SetAllPoints(root)
    textHost:SetFrameLevel(root:GetFrameLevel() + 4)

    local elements = {}

    local icon = CreateTextureElement(root, {
        type = "texture", key = "icon", defaultSize = { 32, 32 },
    })
    PreCreateIconBorder(icon, root)
    -- Pre-created so ApplyShapeStyling never reaches for state.entry.button
    -- (the engine subtree) on a Scoot-owned pass; the apply re-anchors it.
    icon.silhouette = root:CreateTexture(nil, "ARTWORK", nil, -1)
    icon.silhouette:Hide()
    table.insert(elements, icon)

    table.insert(elements, CreateTextElement(root, {
        type = "text", key = "duration", source = "duration", baseSize = 24,
    }, textHost))

    table.insert(elements, CreateBarElement(root, {
        type = "bar", key = "durationBar", source = "duration", defaultSize = { 120, 12 },
    }))

    table.insert(elements, CreateTextElement(root, {
        type = "text", key = "name", source = "name", baseSize = 10,
    }, textHost))

    table.insert(elements, CreateTextElement(root, {
        type = "text", key = "stacks", source = "applications", baseSize = 14,
    }, textHost))

    table.insert(elements, { type = "cooldown", widget = CreateDrainCooldown(root), def = { key = "drain" } })

    return { root = root, textFrame = textHost, elements = elements }
end

local function BuildPreviewElements(entry)
    local visual = entry.visual
    local pv = CreateFrame("Frame", nil, visual)
    pv:SetFrameLevel(visual:GetFrameLevel() + 10)
    pv:SetAllPoints(visual)
    entry.preview = Engine.BuildElementSet(pv)
    return entry.preview
end

-- All previews share one epoch so every tracker's countdown ticks in sync,
-- and the cycle resumes across Edit Mode bounces (the editor-preview rule).
-- One central driver instead of per-preview OnUpdates: lockstep by
-- construction, one start/stop site, and it hides itself when idle.
local previewEpoch
local activePreviews = {}   -- [poolEntry] = { fill, invertFill, text, drain, lastShown, lastCycle }
local driver

local function DriverOnUpdate()
    if not next(activePreviews) then
        driver:Hide()
        return
    end
    local now = GetTime()
    local remaining = 15 - ((now - previewEpoch) % 15)
    local shown = math.ceil(remaining)
    local cycle = math.floor((now - previewEpoch) / 15)
    for _, rec in pairs(activePreviews) do
        if rec.fill then
            rec.fill:SetValue(rec.invertFill and (1 - remaining / 15) or (remaining / 15))
        end
        if rec.text and shown ~= rec.lastShown then
            rec.lastShown = shown
            rec.text:SetText(tostring(shown))
        end
        if rec.drain and cycle ~= rec.lastCycle then
            -- One SetCooldown per cycle; the swipe animates C-side and a
            -- past start lands mid-sweep correctly.
            rec.lastCycle = cycle
            rec.drain:SetCooldown(previewEpoch + cycle * 15, 15)
        end
    end
end

local function RegisterPreviewAnimation(entry, rec)
    if not (rec.fill or rec.text or rec.drain) then
        activePreviews[entry] = nil
        return
    end
    previewEpoch = previewEpoch or GetTime()
    activePreviews[entry] = rec
    if not driver then
        driver = CreateFrame("Frame")
        driver:Hide()
        driver:SetScript("OnUpdate", DriverOnUpdate)
    end
    driver:Show()
end

function Engine.ShowEditModePreview(trackerId, tracker, state)
    local db = SAU.GetDB(trackerId)
    local entry = state and state.entry
    if not db or not entry or not state.container then return end

    local preview = entry.preview or BuildPreviewElements(entry)
    local pv = preview.root
    pv:ClearAllPoints()
    pv:SetAllPoints(state.container)

    -- The chain reads exactly these three state fields. The REAL entry rides
    -- along so SetHostSize writes hostW/hostH where the group layout reads
    -- them (idempotent with the live pass: same db, same numbers).
    local shim = { container = pv, elements = preview.elements, entry = entry }

    if tracker.kind == "missingbuff" and SAU.Missing then
        -- The live visual may be pushed out of view (buff up) or gated off
        -- (out of combat); the preview paints the reminder as it would look
        -- while missing, and the live clip hides for the duration.
        SAU.Missing.PaintElementSet(trackerId, tracker, shim, preview.elements)
        activePreviews[entry] = nil
        pv:Show()
        SAU.Missing.UpdateGate(trackerId)
        return
    end

    -- ApplyAll's order minus BindForMode: bindings need the engine button;
    -- everything else is element-table driven.
    SAU._ApplyIconMode(trackerId, tracker, shim)
    SAU._ApplyShapeStyling(trackerId, tracker, shim)
    SAU._ApplyBorders(trackerId, tracker, shim)
    SAU._ApplyBarStyling(trackerId, tracker, shim)
    SAU._ApplyTextStyling(trackerId, tracker, shim)

    local vis = SAU.ResolveVisibility(tracker, db)
    local durationFS, nameFS, stacksFS, barFill, drainCD
    for _, elem in ipairs(preview.elements) do
        if elem.type == "text" then
            local source = elem.def.source
            if source == "duration" then
                durationFS = elem.widget
            elseif source == "name" then
                nameFS = elem.widget
            elseif source == "applications" then
                stacksFS = elem.widget
            end
        elseif elem.type == "bar" then
            barFill = elem.barFill
        elseif elem.type == "cooldown" then
            drainCD = elem.widget
        end
    end

    -- Sample content before layout: the outside-text path measures string
    -- width, so the duration text must carry its widest value in its final
    -- font. Stacks are excluded from the preview on purpose: most tracked
    -- auras never stack, and a sample count on them reads as a bug.
    durationFS:SetText("15")
    nameFS:SetText(tracker.name or "Aura Tracker")
    stacksFS:SetText("")
    stacksFS:SetShown(false)

    SAU._LayoutElements(trackerId, tracker, shim)

    local wantDrain = (tracker.shape == "shape") and (db.shapeShowDrain ~= false)
    if not wantDrain then
        pcall(drainCD.Clear, drainCD)
    end
    RegisterPreviewAnimation(entry, {
        fill = (vis.showBar and barFill) or nil,
        invertFill = (db.barFillMode == "fill"),
        text = (vis.showText and durationFS) or nil,
        drain = wantDrain and drainCD or nil,
    })

    pv:Show()
end

function Engine.HideEditModePreview(state)
    local entry = state and state.entry
    if not entry then return end
    activePreviews[entry] = nil
    if entry.preview then
        entry.preview.root:Hide()
    end
    -- A missing-buff occupant re-evaluates its live gate now that the preview
    -- no longer stands in for it.
    if SAU.Missing and entry.occupantId then
        SAU.Missing.UpdateGate(entry.occupantId)
    end
end
