--------------------------------------------------------------------------------
-- bars/raidframes/visibility.lua
-- Whole-container raid frame visibility controller
--
-- Goal: let ScooterDeck / small-screen users hide the raid frames outright,
-- for when even minimum-sized frames eat too much of the screen.
--
-- Constraints:
--  - CompactRaidFrameContainer is an Edit Mode system frame. Scoot never calls
--    Hide() on it (protected during combat, and exactly when raid frames
--    matter) and never write fields to it.
--  - SetAlpha is genuinely unprotected and safe in and out of combat.
--    EnableMouse / SetMouseClickEnabled are NOT: on a protected frame they are
--    protected during combat lockdown. Blizzard calls Show() on the container
--    from UpdateRaidAndPartyFrames, which fires the re-enforcement hook with
--    addon taint on the stack -- calling them there during combat produces
--    ADDON_ACTION_BLOCKED. Note that pcall does not help, because a blocked
--    call is not a Lua error. Mouse changes are therefore deferred to
--    PLAYER_REGEN_ENABLED; alpha still applies immediately, so the frames go
--    invisible on time either way.
--  - Zero-Touch: do nothing at all until the user turns this on.
--------------------------------------------------------------------------------

local addonName, addon = ...

addon.RaidVisibility = addon.RaidVisibility or {}
local RaidVisibility = addon.RaidVisibility

local function SafeCall(obj, method, ...)
    if not obj or not method then return end
    local fn = obj[method]
    if type(fn) ~= "function" then return end
    pcall(fn, obj, ...)
end

local function getProfileSetting()
    local profile = addon and addon.db and addon.db.profile
    local groupFrames = profile and rawget(profile, "groupFrames") or nil
    local raid = groupFrames and rawget(groupFrames, "raid") or nil
    return raid and raid.hideRaidFrames == true
end

--------------------------------------------------------------------------------
-- Frame resolution
--------------------------------------------------------------------------------
-- Alpha on the container propagates to every child, so the container alone is
-- enough to make the frames invisible. Mouse state does NOT propagate, so the
-- member frames are collected separately to stop invisible frames from eating
-- clicks and the ConsolePort cursor.
--
-- Both naming schemes are walked, matching raidframes/extras.lua.
--------------------------------------------------------------------------------

local function ResolveContainer()
    return _G and _G.CompactRaidFrameContainer or nil
end

local function ResolveMemberFrames()
    local out = {}

    local function addFrame(name)
        local f = _G and _G[name]
        if f then
            out[name] = f
        end
    end

    -- Pattern 1: Separate groups (CompactRaidGroup1Member1, etc.)
    for group = 1, 8 do
        for member = 1, 5 do
            addFrame("CompactRaidGroup" .. group .. "Member" .. member)
        end
    end

    -- Pattern 2: Combined groups (CompactRaidFrame1, etc.)
    for i = 1, 40 do
        addFrame("CompactRaidFrame" .. i)
    end

    return out
end

--------------------------------------------------------------------------------
-- Baselines
--------------------------------------------------------------------------------

local function CaptureBaseline(self, name, frame)
    self._baselines = self._baselines or {}
    if self._baselines[name] then
        return
    end
    local baseline = {}
    local okAlpha, alpha = pcall(frame.GetAlpha, frame)
    baseline.alpha = (okAlpha and type(alpha) == "number") and alpha or 1
    local okMouse, mouse = pcall(frame.IsMouseEnabled, frame)
    baseline.mouse = (okMouse and mouse) and true or false
    self._baselines[name] = baseline
end

-- Both deferral sites queue the same full reapply under one key, matching the
-- single pending boolean they replaced.
local function QueueMouseSettle()
    addon.Events.RunOutOfCombat(function()
        local vis = addon and addon.RaidVisibility
        if vis then vis:ApplyFromProfile("CombatEnd") end
    end, "RaidVisibility:mouse")
end

local function ApplyHidden(self, name, frame, isContainer)
    CaptureBaseline(self, name, frame)

    -- Guard against the SetAlpha hook re-entering during this alpha write.
    self._enforcing = true
    SafeCall(frame, "SetAlpha", 0)
    self._enforcing = nil

    -- Stop invisible frames from capturing clicks / the controller cursor.
    -- Protected in combat; defer the full reapply to the shared regen drain.
    if InCombatLockdown() then
        QueueMouseSettle()
    else
        SafeCall(frame, "EnableMouse", false)
        if isContainer then
            SafeCall(frame, "SetMouseClickEnabled", false)
        end
    end
end

local function RestoreBaseline(self, name, frame)
    local baseline = self._baselines and self._baselines[name] or nil
    if not baseline then
        -- Zero-Touch: Scoot never hid this frame, so leave it alone.
        -- Never force raid frames visible.
        return
    end

    self._enforcing = true
    SafeCall(frame, "SetAlpha", baseline.alpha or 1)
    self._enforcing = nil

    -- Same protection as ApplyHidden. The baseline is deliberately NOT cleared
    -- while deferred -- it holds the mouse state still owed to this frame, and
    -- dropping it here would restore alpha but leave the frame click-dead.
    if InCombatLockdown() then
        QueueMouseSettle()
        return
    end

    SafeCall(frame, "EnableMouse", baseline.mouse and true or false)
    SafeCall(frame, "SetMouseClickEnabled", true)

    self._baselines[name] = nil
end

--------------------------------------------------------------------------------
-- Re-enforcement hooks
--------------------------------------------------------------------------------
-- Blizzard resets container alpha whenever the raid roster or display mode
-- changes. Hook rather than poll; re-apply only while the toggle is on.
--------------------------------------------------------------------------------

local function HookContainer(self, frame)
    if self._hookedContainer then
        return
    end
    self._hookedContainer = true

    local function reapply()
        if self._enforcing then return end
        if not getProfileSetting() then return end
        ApplyHidden(self, "CompactRaidFrameContainer", frame, true)
    end

    if frame.SetAlpha then
        hooksecurefunc(frame, "SetAlpha", reapply)
    end
    if frame.Show then
        hooksecurefunc(frame, "Show", reapply)
    end
    if frame.SetShown then
        hooksecurefunc(frame, "SetShown", function(_, shown)
            if shown then reapply() end
        end)
    end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function RaidVisibility:IsHidden()
    return getProfileSetting()
end

function RaidVisibility:ApplyFromProfile(reason)
    local shouldHide = getProfileSetting()

    -- Zero-Touch: nothing hidden and nothing to restore means never touch
    -- a single raid frame.
    if not shouldHide then
        if not (self._baselines and next(self._baselines)) then
            return
        end
    end

    local container = ResolveContainer()
    if container then
        if shouldHide then
            HookContainer(self, container)
            ApplyHidden(self, "CompactRaidFrameContainer", container, true)
        else
            RestoreBaseline(self, "CompactRaidFrameContainer", container)
        end
    end

    for name, frame in pairs(ResolveMemberFrames()) do
        if shouldHide then
            ApplyHidden(self, name, frame, false)
        else
            RestoreBaseline(self, name, frame)
        end
    end

    self._lastApplyReason = reason
end

function RaidVisibility:Initialize()
    if self._initialized then
        return
    end
    self._initialized = true

    -- Member frames are created and recycled as the roster changes, so newly
    -- spawned frames need the treatment applied to them too.
    --
    -- Ordering: this GROUP_ROSTER_UPDATE registration must precede
    -- RaidRosterOverlay's. The bus dispatches in registration order, and
    -- init.lua initializes RaidVisibility first, so the overlay reads
    -- member-frame geometry only after this handler has mutated visibility.
    local function onEvent()
        local self = addon and addon.RaidVisibility
        if not self then return end
        self:ApplyFromProfile("RaidEvent")
    end
    addon.Events.On("UnitFrames:RaidVisibility", "PLAYER_ENTERING_WORLD", onEvent)
    addon.Events.On("UnitFrames:RaidVisibility", "GROUP_ROSTER_UPDATE", onEvent)

    self:ApplyFromProfile("Initialize")
end

-- Exported for GF.applyStyles("raid")
function addon.ApplyRaidContainerVisibility(reason)
    if addon.RaidVisibility then
        addon.RaidVisibility:ApplyFromProfile(reason or "ApplyStyles")
    end
end
