--------------------------------------------------------------------------------
-- session.lua
-- Closing Edit Mode from addon code, with a continuation that runs once it has
-- exited. Listed on both TOCs: the Edit Mode dialog's Configure button needs it,
-- and it touches EditModeManagerFrame only, never LibEditModeOverride.
--------------------------------------------------------------------------------

local addonName, addon = ...

addon.EditMode = addon.EditMode or {}

-- Past EditModeExit:pass1 (0.1s), before pass2.
local POST_EXIT_DELAY = 0.2
local PENDING_TTL = 8.0

local pendingPostExit, pendingArmedAt

local function ArmPostExit(fn)
    pendingPostExit, pendingArmedAt = fn, GetTime()
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(PENDING_TTL, function()
            if pendingPostExit == fn then pendingPostExit = nil end
        end)
    end
end

-- Fired from EditModeManagerFrame's OnHide (installed below). HookScript rather
-- than the EditMode.Exit EventRegistry callback, which can no-fire under 12.0.5.
function addon.EditMode._FlushPostExit()
    local fn = pendingPostExit
    pendingPostExit = nil
    if not fn then return end
    if (GetTime() - (pendingArmedAt or 0)) > PENDING_TTL then return end

    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(POST_EXIT_DELAY, fn)
    else
        fn()
    end
end

--- Close Edit Mode, then run onClosed once it has exited.
---
--- Routes through mgr.onCloseCallback rather than a bare HideUIPanel: that is
--- what surfaces Blizzard's Save/Exit/Cancel prompt when there are unsaved layout
--- changes. ExitEditMode calls RevertAllChanges unconditionally, so skipping the
--- prompt would silently discard the user's work. (LibEditMode frame positions
--- are never at risk - they persist at drag-stop, not at layout save.)
---
--- onClosed cannot run synchronously: UIPanel:Show runs RefreshSyncAndNotify,
--- which must not execute inside the ExitEditMode -> UpdateSystems teardown.
function addon.EditMode.CloseEditMode(onClosed)
    local mgr = _G.EditModeManagerFrame
    if not mgr then
        if onClosed then onClosed() end
        return
    end

    local shown = false
    local ok, isShown = pcall(mgr.IsShown, mgr)
    if ok and isShown == true then shown = true end

    if not shown then
        if onClosed then onClosed() end
        return
    end

    if onClosed then ArmPostExit(onClosed) end

    -- Host seam: the LibEditModeOverride sync marks the exit so its own
    -- listeners stand down. Absent where that sync is not loaded.
    if addon.EditMode.MarkExitingEditMode then
        addon.EditMode.MarkExitingEditMode()
    end

    -- Never write to mgr. The HideUIPanel -> OnHide -> ExitEditMode ->
    -- UpdateSystems chain is the documented 12.0 taint cascade, so the secure
    -- wrapper matters.
    local cb = mgr.onCloseCallback
    if type(cb) == "function" and _G.securecallfunction then
        pcall(_G.securecallfunction, cb)
    elseif _G.HideUIPanel then
        if _G.securecallfunction then
            pcall(_G.securecallfunction, _G.HideUIPanel, mgr)
        else
            pcall(_G.HideUIPanel, mgr)
        end
    end
end

-- OnHide is the reliable exit signal. EditModeManagerFrame exists at login, so
-- one install on the first world entry covers the session.
addon.Events.OnWorldEntered(function()
    if addon._editModePostExitHooked then return end
    local mgr = _G.EditModeManagerFrame
    if mgr and mgr.HookScript then
        addon._editModePostExitHooked = true
        mgr:HookScript("OnHide", function()
            addon.EditMode._FlushPostExit()
        end)
    end
end)
