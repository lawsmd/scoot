--------------------------------------------------------------------------------
-- bars/raidframes/rosteroverlay.lua
-- Scoot-owned two-column raid roster overlay
--
-- Goal: a compact "who is in my raid" panel for small screens, meant to pair
-- with the Hide Raid Frames toggle in visibility.lua. Reads like a book:
-- group 1 top-left, group 2 top-right, group 3 next row left, and so on.
--
-- Constraints:
--  - This is a Scoot-owned frame parented to UIParent. Blizzard frames are
--    never re-parented, resized, or written to.
--  - 12.0 secrets: UnitName() returns secret values for raid tokens and no
--    longer accepts secret unit tokens at all. This file NEVER calls
--    UnitName(). Names arrive by mirroring SetText on Blizzard's own raid
--    frame name FontStrings via hooksecurefunc, which is the same technique
--    raidframes/text.lua uses. Passing a secret to FontString:SetText is
--    explicitly allowed; the secret aspect then sticks to the row FontString,
--    so GetText() is never called on a row.
--  - Group numbers come from the frame NAME (CompactRaidGroup<N>Member<M>),
--    never from GetRaidRosterInfo, which is not documented as secret-safe.
--  - Colour is mirrored the same way, off the SAME FontString the text comes
--    from. UnitClass is secret and raid unit tokens are secret,
--    so there is no legal way to ask "what class is raid7", and no need
--    to ask. Whatever the raid frame name is wearing, the overlay row wears too.
--  - WHICH FontString that is depends on Scoot's own settings. When Player Name
--    has any non-default text setting, text.lua hides Blizzard's frame.name
--    (alpha 0 + Hide) and draws its own state.nameOverlayText, applying the
--    class/custom colour to that one. Binding to frame.name in that case yields
--    correct text but Blizzard's default white, because nothing ever calls
--    SetTextColor on the hidden FontString. resolveNameSource() picks whichever
--    one the user is looking at.
--------------------------------------------------------------------------------

local addonName, addon = ...

addon.RaidRosterOverlay = addon.RaidRosterOverlay or {}
local RosterOverlay = addon.RaidRosterOverlay

local MAX_GROUPS = 8
local MAX_MEMBERS = 5
local MAX_FLAT = 40

-- Layout
--
-- Everything scales off the Player Name font size rather than sitting at fixed
-- pixel values. The panel is meant for small screens, so the defaults are tight:
-- rows are the font size plus two, and the gaps are the smallest that still let
-- group blocks read as separate blocks.
local function computeMetrics(size)
    size = tonumber(size) or 12
    local row = math.max(8, math.floor(size + 2))
    return {
        padding     = 4,
        columnGap   = 8,
        columnWidth = math.max(64, math.floor(size * 7)),
        rowHeight   = row,
        headerHeight = row,
        headerGap   = 0,
        blockGap    = math.max(2, math.floor(size * 0.35)),
    }
end

-- Used only to size FontStrings at creation time, before the first layout pass
-- has resolved the real font. Relayout() overwrites all of it.
local INITIAL_WIDTH = 100
local INITIAL_HEIGHT = 14

local function SafeCall(obj, method, ...)
    if not obj or not method then return end
    local fn = obj[method]
    if type(fn) ~= "function" then return end
    pcall(fn, obj, ...)
end

--------------------------------------------------------------------------------
-- Profile access
--------------------------------------------------------------------------------
-- Zero-Touch: no config means no overlay. Stored as true / nil, never false.
--------------------------------------------------------------------------------

local function getRaidDB()
    local profile = addon and addon.db and addon.db.profile
    local groupFrames = profile and rawget(profile, "groupFrames") or nil
    return groupFrames and rawget(groupFrames, "raid") or nil
end

local function isEnabled()
    local raid = getRaidDB()
    return raid and raid.rosterOverlay == true
end

local function getAlpha()
    local raid = getRaidDB()
    local pct = raid and tonumber(raid.rosterOverlayAlpha) or nil
    if not pct then pct = 100 end
    if pct < 0 then pct = 0 elseif pct > 100 then pct = 100 end
    return pct / 100
end

--------------------------------------------------------------------------------
-- Font resolution
--------------------------------------------------------------------------------
-- Deliberately shares the Raid Frames > Player Name font config rather than
-- owning its own. One font control, two places it lands.
--------------------------------------------------------------------------------

local function resolveNameFont()
    local raid = getRaidDB()
    local cfg = (raid and rawget(raid, "textPlayerName")) or {}

    local fontFace = cfg.fontFace or "FRIZQT__"
    local resolved
    if addon and addon.ResolveFontFace then
        resolved = addon.ResolveFontFace(fontFace)
    end
    if not resolved then
        local defaultFont = _G.GameFontNormal and _G.GameFontNormal:GetFont()
        resolved = defaultFont or "Fonts\\FRIZQT__.TTF"
    end

    local size = tonumber(cfg.size) or 12
    local style = cfg.style or "OUTLINE"
    return resolved, size, style
end

--------------------------------------------------------------------------------
-- Frame construction
--------------------------------------------------------------------------------

-- Inherit GameFontNormal so the FontString always has a font from the moment
-- it exists. SetText() errors with "Font not set" otherwise, and Relayout()
-- does not assign the real font until the first layout pass.
local function createRow(parent)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetJustifyH("LEFT")
    fs:SetWidth(INITIAL_WIDTH)
    fs:SetHeight(INITIAL_HEIGHT)
    -- Long names clip rather than wrapping onto a second line, which would
    -- desync every row below them from the fixed row pitch.
    fs:SetWordWrap(false)
    fs:SetText("")
    return fs
end

function RosterOverlay:EnsureFrame()
    if self._frame then
        return self._frame
    end

    local frame = CreateFrame("Frame", "ScootRaidRosterOverlay", UIParent)
    frame:SetSize(280, 300)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:Hide()

    -- Drag to move. The panel takes mouse input while visible, which is the
    -- price of being draggable without a separate lock control -- it will eat
    -- clicks that land on it. Keeping it small is the mitigation.
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        RosterOverlay:SavePosition()
    end)

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)
    frame._bg = bg

    -- Per-group blocks: a header plus MAX_MEMBERS name rows.
    frame._groups = {}
    for g = 1, MAX_GROUPS do
        local block = {}
        block.header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        block.header:SetJustifyH("LEFT")
        block.header:SetWidth(INITIAL_WIDTH)
        block.header:SetHeight(INITIAL_HEIGHT)
        block.header:SetWordWrap(false)
        block.header:SetText("Group " .. g)

        block.rows = {}
        for m = 1, MAX_MEMBERS do
            block.rows[m] = createRow(frame)
        end
        frame._groups[g] = block
    end

    -- Flat rows, used when raid frames are in combined-groups mode and no
    -- per-group frames exist to read group membership from.
    frame._flatRows = {}
    for i = 1, MAX_FLAT do
        frame._flatRows[i] = createRow(frame)
    end

    self._frame = frame
    return frame
end

--------------------------------------------------------------------------------
-- Position
--------------------------------------------------------------------------------
-- Saved as an explicit UIParent-relative anchor rather than trusting whatever
-- relativeTo StartMoving happened to leave behind.
--------------------------------------------------------------------------------

function RosterOverlay:ApplyPosition()
    local frame = self._frame
    if not frame then return end

    local raid = getRaidDB()
    local pos = raid and rawget(raid, "rosterOverlayPos") or nil

    frame:ClearAllPoints()
    if type(pos) == "table" and pos.point and tonumber(pos.x) and tonumber(pos.y) then
        frame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

function RosterOverlay:SavePosition()
    local frame = self._frame
    local raid = getRaidDB()
    if not frame or not raid then return end

    local ok, point, _, _, x, y = pcall(frame.GetPoint, frame, 1)
    if not ok or not point or not tonumber(x) or not tonumber(y) then return end

    raid.rosterOverlayPos = {
        point = point,
        x = math.floor(x + 0.5),
        y = math.floor(y + 0.5),
    }
end

--------------------------------------------------------------------------------
-- Name mirroring
--------------------------------------------------------------------------------
-- The name is never read. A hook on Blizzard's SetText on the raid frame's name
-- FontString forwards the argument straight through to the overlay row. Colour
-- rides along on the same FontString via SetTextColor / SetVertexColor.
--
-- Deliberately a straight passthrough with no filtering: the overlay row is
-- meant to look like the raid frame name it came from. That means class colours
-- when the raid frames are class-colouring names, and Scoot's configured Player
-- Name colour when they are not -- both are correct, because both are what the
-- raid frame is showing.
--------------------------------------------------------------------------------

-- Scoot does not colour Blizzard's name FontString. When Player Name has any
-- non-default text setting, text.lua hides frame.name and draws its own
-- FontString, applying the class/custom colour to that one instead. Mirror
-- whichever one the user is looking at -- taking text from the same
-- source also means the row inherits Player Name's Hide Realm processing.
--
-- nameOverlayText is only ever read from and hooked, never SetText on. It is
-- created with no font template (text.lua:385-389) and Scoot's own styling pass
-- is what gives it a font.
local function resolveNameSource(frame)
    if not frame then return nil end
    local BRF = addon.BarsRaidFrames
    local state = BRF and BRF._getState and BRF._getState(frame)
    local overlay = state and state.nameOverlayText
    if overlay and state.nameOverlayActive and overlay.SetText then
        return overlay
    end
    return frame.name
end

-- Exported so core/debug/rosteroverlay.lua reports the source the real code
-- picked, rather than a copy of this logic that can drift out of sync.
RosterOverlay.ResolveNameSource = function(_, frame)
    return resolveNameSource(frame)
end

function RosterOverlay:BindRow(sourceFrame, targetFS)
    if not sourceFrame or not targetFS then return end
    local nameFS = resolveNameSource(sourceFrame)
    if not nameFS or not nameFS.SetText then return end

    self._bindings = self._bindings or setmetatable({}, { __mode = "k" })
    local binding = self._bindings[nameFS]

    if binding then
        -- Frame already hooked; just retarget it. Blizzard recycles these
        -- frames across roster changes, so the hook outlives the assignment.
        binding.target = targetFS
    else
        binding = { target = targetFS }
        self._bindings[nameFS] = binding

        hooksecurefunc(nameFS, "SetText", function(_, text)
            local t = binding.target
            if not t then return end
            -- text may be a secret in 12.0. SetText accepts secrets natively,
            -- so forward it without inspecting or comparing it.
            pcall(t.SetText, t, text)
        end)

        -- Blizzard's CompactUnitFrame name colouring and Scoot's own Player
        -- Name colouring do not agree on which setter they use, so mirror both.
        -- Neither value is inspected -- a secret colour would simply fail the
        -- pcall and leave the row on whatever it was already wearing.
        -- Hue only -- alpha is deliberately dropped and forced to 1. The raid
        -- frame name can legitimately be sitting at alpha 0 (Hide Raid Frames
        -- does exactly that), and mirroring it would paint invisible rows onto
        -- a panel that is already carrying its own SetAlpha from the
        -- transparency slider. Two alphas multiplying is never the intent.
        local function forwardColor(_, r, g, b)
            local t = binding.target
            if not t then return end
            pcall(t.SetTextColor, t, r, g, b, 1)
        end
        hooksecurefunc(nameFS, "SetTextColor", forwardColor)
        if nameFS.SetVertexColor then
            hooksecurefunc(nameFS, "SetVertexColor", forwardColor)
        end
    end

    -- Seed the current value so the row is populated immediately rather than
    -- waiting for Blizzard's next SetText call.
    local ok, current = pcall(nameFS.GetText, nameFS)
    if ok and current ~= nil then
        pcall(targetFS.SetText, targetFS, current)
    end

    -- Same rule as forwardColor: take the hue, force alpha to 1.
    local okc, r, g, b = pcall(nameFS.GetTextColor, nameFS)
    if okc and r then
        pcall(targetFS.SetTextColor, targetFS, r, g, b, 1)
    end
end

function RosterOverlay:ClearBindings()
    if not self._bindings then return end
    for _, binding in pairs(self._bindings) do
        binding.target = nil
    end
end

-- Re-run BindRow over the pairs the last layout pass established, without
-- redoing layout. This exists because nameOverlayText is created lazily off
-- CompactUnitFrame_UpdateName and is never created during combat lockdown
-- (text.lua:557-577) -- so at first Relayout a frame may only have frame.name,
-- and without a retrigger the row would stay on Blizzard's FontString for the
-- rest of the session. Re-binding is idempotent: an already-hooked FontString
-- is only retargeted.
function RosterOverlay:RefreshBindings()
    local pairsList = self._boundPairs
    if not pairsList then return end
    for i = 1, #pairsList do
        local p = pairsList[i]
        self:BindRow(p.frame, p.row)
    end
end

-- Scoot re-applies name overlays on its own schedule (per-frame update hooks,
-- plus a delayed pass on GROUP_ROSTER_UPDATE at text.lua:702-733). Piggyback on
-- that rather than polling. Installed lazily because .toc load order relative to
-- text.lua is not something to depend on.
function RosterOverlay:EnsureOverlayHook()
    if self._overlayHookInstalled then return end
    if not addon.ApplyRaidFrameNameOverlays then return end
    self._overlayHookInstalled = true

    hooksecurefunc(addon, "ApplyRaidFrameNameOverlays", function()
        -- Debounced: the per-frame paths all funnel through here, so an
        -- un-debounced refresh would run once per member per update.
        if RosterOverlay._refreshQueued then return end
        RosterOverlay._refreshQueued = true
        C_Timer.After(0, function()
            RosterOverlay._refreshQueued = nil
            local frame = RosterOverlay._frame
            if frame and frame:IsShown() then
                RosterOverlay:RefreshBindings()
            end
        end)
    end)
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------
-- Book order: odd groups fill the left column, even groups the right, so the
-- pairs read 1|2 / 3|4 / 5|6 / 7|8 down the panel.
--------------------------------------------------------------------------------

-- A member frame existing is NOT the same as it holding a current raid member.
-- Blizzard keeps retired member frames allocated with the previous occupant's
-- name text still on them, which showed up as duplicate names at the end of a
-- group -- and as names of players who had already left. Blizzard hides the
-- retired ones, so IsShown is the discriminator.
--
-- This stays correct under Hide Raid Frames: visibility.lua deliberately uses
-- SetAlpha(0) and never Hide() (see its header), so live frames still report
-- shown while invisible. Do NOT switch this to IsVisible() -- that walks the
-- parent chain and would report false for every frame once the container is
-- hidden by anything else.
--
-- The unit token is deliberately not consulted. Raid unit tokens are secret in
-- 12.0, and reading frame.unit off a Blizzard frame is exactly the sort of
-- content read the secrets rules forbid.
local function isLiveMemberFrame(frame)
    if not frame or not frame.name then return false end
    if not frame.IsShown then return false end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown and true or false
end

function RosterOverlay:Relayout()
    local frame = self:EnsureFrame()
    local font, size, style = resolveNameFont()
    local M = computeMetrics(size)

    local function columnX(index)
        -- index is 1 (left) or 2 (right)
        return M.padding + ((index - 1) * (M.columnWidth + M.columnGap))
    end

    local function placeFS(fs, colIndex, y, height)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", frame, "TOPLEFT", columnX(colIndex), y)
        fs:SetWidth(M.columnWidth)
        fs:SetHeight(height)
        addon.ApplyFontStyle(fs, font, size, style)
        fs:Show()
    end

    -- Hide everything, then show only what this pass populates.
    for g = 1, MAX_GROUPS do
        local block = frame._groups[g]
        block.header:Hide()
        for m = 1, MAX_MEMBERS do
            block.rows[m]:Hide()
        end
    end
    for i = 1, MAX_FLAT do
        frame._flatRows[i]:Hide()
    end

    self:ClearBindings()
    -- Recorded so RefreshBindings can re-resolve sources later without a full
    -- layout pass. Reset every pass; stale frames must not survive.
    self._boundPairs = {}

    -- Prefer per-group frames so groups can be labelled. These only exist while
    -- raid frames are in separate-groups mode.
    local usedGrouped = false
    local leftY, rightY = -M.padding, -M.padding
    local maxY = 0

    for g = 1, MAX_GROUPS do
        local groupFrame = _G["CompactRaidGroup" .. g]
        local members = {}
        for m = 1, MAX_MEMBERS do
            local mf = _G["CompactRaidGroup" .. g .. "Member" .. m]
            if isLiveMemberFrame(mf) then
                members[#members + 1] = mf
            end
        end

        if groupFrame and #members > 0 then
            usedGrouped = true
            local isLeft = (g % 2 == 1)
            local colIndex = isLeft and 1 or 2
            local y = isLeft and leftY or rightY
            local block = frame._groups[g]

            placeFS(block.header, colIndex, y, M.headerHeight)
            block.header:SetTextColor(1, 0.82, 0, 1)
            y = y - M.headerHeight - M.headerGap

            for m = 1, #members do
                local row = block.rows[m]
                placeFS(row, colIndex, y, M.rowHeight)
                -- Default; BindRow upgrades this to whatever colour the raid
                -- frame's name is wearing.
                row:SetTextColor(1, 1, 1, 1)
                self:BindRow(members[m], row)
                self._boundPairs[#self._boundPairs + 1] = { frame = members[m], row = row }
                y = y - M.rowHeight
            end

            y = y - M.blockGap
            if isLeft then leftY = y else rightY = y end
            if -y > maxY then maxY = -y end
        end
    end

    -- Combined-groups fallback: CompactRaidFrame1..40 carry no group number in
    -- their names, so this path lists members in roster order without headers.
    if not usedGrouped then
        local found = {}
        for i = 1, MAX_FLAT do
            local f = _G["CompactRaidFrame" .. i]
            if isLiveMemberFrame(f) then
                found[#found + 1] = f
            end
        end

        for i = 1, #found do
            -- Book order across two columns.
            local colIndex = ((i - 1) % 2 == 0) and 1 or 2
            local rowIndex = math.floor((i - 1) / 2)
            local row = frame._flatRows[i]
            local y = -M.padding - (rowIndex * M.rowHeight)

            placeFS(row, colIndex, y, M.rowHeight)
            row:SetTextColor(1, 1, 1, 1)
            self:BindRow(found[i], row)
            self._boundPairs[#self._boundPairs + 1] = { frame = found[i], row = row }

            if -y + M.rowHeight > maxY then maxY = -y + M.rowHeight end
        end
    end

    -- The trailing blockGap on the last block is padding already accounted for.
    if usedGrouped and maxY > M.blockGap then
        maxY = maxY - M.blockGap
    end

    local width = (M.columnWidth * 2) + M.columnGap + (M.padding * 2)
    local height = math.max(maxY + M.padding, M.rowHeight + (M.padding * 2))
    frame:SetSize(width, height)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function RosterOverlay:ApplyFromProfile(reason)
    local enabled = isEnabled()

    -- Zero-Touch: never built a frame and not enabled means do nothing at all.
    if not enabled and not self._frame then
        return
    end

    local frame = self:EnsureFrame()

    if not enabled then
        self:ClearBindings()
        SafeCall(frame, "Hide")
        self._lastApplyReason = reason
        return
    end

    self:EnsureOverlayHook()
    self:Relayout()
    self:ApplyPosition()
    SafeCall(frame, "SetAlpha", getAlpha())
    SafeCall(frame, "Show")
    self._lastApplyReason = reason
end

function RosterOverlay:Initialize()
    if self._initialized then
        return
    end
    self._initialized = true

    -- Ordering: RaidVisibility's GROUP_ROSTER_UPDATE handler is already on the
    -- bus (init.lua initializes it first), so this one runs after member-frame
    -- visibility has been applied and reads the resulting geometry.
    local function onEvent()
        local self = addon and addon.RaidRosterOverlay
        if not self then return end

        self:ApplyFromProfile("RaidEvent")

        -- Blizzard has not necessarily reflowed its member frames by the time
        -- GROUP_ROSTER_UPDATE arrives, so the pass above can read the old
        -- shape. Re-run once things have settled. Debounced, because a raid
        -- forming fires this event many times in quick succession.
        if self._settlePending then return end
        self._settlePending = true
        C_Timer.After(0.6, function()
            self._settlePending = nil
            self:ApplyFromProfile("RaidEventSettle")
        end)
    end
    addon.Events.On("UnitFrames:RaidRosterOverlay", "PLAYER_ENTERING_WORLD", onEvent)
    addon.Events.On("UnitFrames:RaidRosterOverlay", "GROUP_ROSTER_UPDATE", onEvent)

    self:ApplyFromProfile("Initialize")
end

-- Exported for GF.applyStyles("raid")
function addon.ApplyRaidRosterOverlay(reason)
    if addon.RaidRosterOverlay then
        addon.RaidRosterOverlay:ApplyFromProfile(reason or "ApplyStyles")
    end
end
