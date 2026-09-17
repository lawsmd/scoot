-- persist.lua - Edit Mode layout persistence, the layer under the profile engine
--
-- Loads under both addons, before any other core/editmode/ file. It owns the
-- LibEditModeOverride handle, layout loading, the guard that keeps a write
-- inside the layout matching the active profile, the save-only path, the
-- resync that runs after every SaveLayouts, and the hook that schedules it.
-- Nothing here knows a component or a system frame; core/editmode/core.lua
-- and sync.lua add the setting-level work on top, and register their
-- back-sync passes here.
local _, addon = ...

addon.EditMode = addon.EditMode or {}
local EditMode = addon.EditMode

local LEO = LibStub("LibEditModeOverride-1.0")

-- Central suppression check, used only during the short post-copy window.
local function shouldSuppressWrites()
    local prof = addon.Profiles
    if not prof or not prof.IsPostCopySuppressed then return false end
    return prof:IsPostCopySuppressed()
end

function EditMode.LoadLayouts()
    if not LEO or not LEO.LoadLayouts or not LEO.IsReady then return end
    if not LEO:IsReady() then return end
    if LEO.AreLayoutsLoaded and LEO:AreLayoutsLoaded() then return end
    pcall(LEO.LoadLayouts, LEO)
end

-- Addon-authored Edit Mode writes are only valid when the active AceDB profile
-- and the active Edit Mode layout agree (they are keyed 1:1 by name). They
-- disagree in exactly two situations: a cross-machine login where the
-- account-synced layout differs from this machine's last-used profile, and the
-- post-reload window where the C API still reports the previous session's
-- layout. In both, a write would land data from one profile in another
-- profile's layout, so callers skip. Skipped syncs are retried by the
-- SaveLayouts 3-pass hook once RefreshFromEditMode aligns profile and layout.
function EditMode.ProfileMatchesActiveLayout()
    if not (LEO and LEO.AreLayoutsLoaded and LEO:AreLayoutsLoaded()) then return false end
    local ok, layoutName = pcall(LEO.GetActiveLayout, LEO)
    if not ok or type(layoutName) ~= "string" then return false end
    local prof = addon.db and addon.db.GetCurrentProfile and addon.db:GetCurrentProfile()
    return prof == layoutName
end

-- Persist Edit Mode settings and trigger the visual refresh through LEO's
-- deferred SetActiveLayout. The primary "apply settings visually" entry point
-- for addon writes. Debug logging: `/run <Addon>._dbgEditMode = true`.
--
-- IMPORTANT: The visual refresh depends on LEO:SaveOnly() calling
-- SetActiveLayout in a deferred context. If settings save but do not apply
-- visually, check:
-- 1. That LEO:SaveOnly() is being called (not suppressed)
-- 2. That layoutInfo.activeLayout is valid (not nil, must be >= 1)
-- 3. That the deferred C_Timer.After callback executes
function EditMode.SaveOnly()
    if not LEO or not LEO.SaveOnly then
        if addon._dbgEditMode then addon.DebugPrint("|cFFFF0000[EM.SaveOnly]|r LEO not available") end
        return
    end
    if shouldSuppressWrites() then
        if addon._dbgEditMode then addon.DebugPrint("|cFFFF0000[EM.SaveOnly]|r Suppressed by post-copy window") end
        return
    end
    if not EditMode.ProfileMatchesActiveLayout() then
        if addon._dbgEditMode then addon.DebugPrint("|cFFFF6600[EM.SaveOnly]|r Skipped: profile ~= active layout") end
        return
    end
    -- Kept off Theme accent: severity mark, same palette as the red and orange
    -- lines above. Green here means the save ran.
    if addon._dbgEditMode then addon.DebugPrint("|cFF00FF00[EM.SaveOnly]|r Calling LEO:SaveOnly()") end
    LEO:SaveOnly()
end

--------------------------------------------------------------------------------
-- The resync after a layout change
--------------------------------------------------------------------------------

-- Back-sync passes pull Edit Mode state into the addon's own store. A host
-- registers them in the order they should run; fn(origin, isRetry) runs once
-- before the profile resync and, when the resync has just aligned profile and
-- layout, once more with isRetry true so the pull is not starved until the
-- next external trigger.
local backSyncPasses = {}

function EditMode.RegisterBackSync(name, fn)
    if type(name) ~= "string" or type(fn) ~= "function" then return false end
    for i = #backSyncPasses, 1, -1 do
        if backSyncPasses[i].name == name then table.remove(backSyncPasses, i) end
    end
    backSyncPasses[#backSyncPasses + 1] = { name = name, fn = fn }
    return true
end

local function runBackSync(origin, isRetry)
    for _, pass in ipairs(backSyncPasses) do
        pass.fn(origin, isRetry)
    end
end

function EditMode.RefreshSyncAndNotify(origin)
    if LEO and LEO.IsReady and LEO:IsReady() and LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end

    local matchedBeforePull = EditMode.ProfileMatchesActiveLayout()

    runBackSync(origin, false)

    if addon.Profiles and addon.Profiles.RefreshFromEditMode then
        addon.Profiles:RefreshFromEditMode(origin)
    end

    if not matchedBeforePull and EditMode.ProfileMatchesActiveLayout() then
        runBackSync(origin, true)
    end

    -- The settings list is not refreshed here; routine Edit Mode saves reach
    -- it through control bindings and per-row helpers, which avoids right-pane
    -- flicker.

    if addon._dbgSync and origin then
        addon.DebugPrint((addon.Brand or "Scoot") .. " RefreshSyncAndNotify origin=" .. tostring(origin))
    end
end

-- Every SaveLayouts, from any addon or from Blizzard's own Edit Mode, is
-- followed by three resync passes: the first on the next frame, the others
-- after the client has settled. Idempotent; the host calls it once its Edit
-- Mode integration is up.
function EditMode.InstallLayoutHooks()
    if addon._hookedSave then return end
    if type(_G.C_EditMode) ~= "table" or type(_G.C_EditMode.SaveLayouts) ~= "function" then return end
    hooksecurefunc(_G.C_EditMode, "SaveLayouts", function()
        C_Timer.After(0.0, function() if addon.EditMode then addon.EditMode.RefreshSyncAndNotify("SaveLayouts:pass1") end end)
        C_Timer.After(0.25, function() if addon.EditMode then addon.EditMode.RefreshSyncAndNotify("SaveLayouts:pass2") end end)
        C_Timer.After(0.6, function() if addon.EditMode then addon.EditMode.RefreshSyncAndNotify("SaveLayouts:pass3") end end)
    end)
    addon._hookedSave = true
end
