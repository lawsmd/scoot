--------------------------------------------------------------------------------
-- core/strata.lua
-- The frame-strata doctrine for Scoot-owned frames.
--
-- THE RULE: in-world HUD elements live at MEDIUM and order themselves by frame
-- LEVEL. Nothing Scoot draws over the world goes above MEDIUM, ever.
--
-- Why, from Blizzard's own source (12.0.0):
--
--   * UIParent is frameStrata="MEDIUM"
--     (Blizzard_UIParent/Mainline/UIParent.xml:4).
--   * The full-screen panels -- PlayerSpellsFrame (the talent pane),
--     CharacterFrame, EncounterJournal -- declare NO frameStrata of their own,
--     so they inherit MEDIUM. They are only toplevel="true"
--     (Blizzard_PlayerSpellsFrame.xml:5, CharacterFrame.xml:147,
--     Blizzard_EncounterJournal.xml:1190).
--   * ShowUIPanel raises a panel with frame:Raise() and nothing else --
--     there is no SetFrameStrata call anywhere in the panel manager
--     (UIParentPanelManager.lua:478, 606, 625, 672, 710).
--
-- Raise() only reorders WITHIN a strata. So the entire UIPanelWindows system
-- is confined to MEDIUM, and any addon frame parked at HIGH or above draws in
-- front of every Blizzard panel permanently, no matter how high the panel is
-- raised. That was the bug this file exists to prevent: UFZ unit frames and the
-- PRD number overlay floating over an open talent pane (2026-08-06).
--
-- For scale, Blizzard's own baseline: PlayerFrame, TargetFrame,
-- CompactUnitFrameTemplate and BaseAuraFrameTemplate are all LOW; action bars
-- and the Cooldown Viewer are MEDIUM. The one HUD element Blizzard puts at HIGH
-- is PlayerCastingBarFrame. LOW was considered for our unit frames and rejected:
-- UFZ is user-positioned and would then vanish behind an action bar it overlaps.
--
-- THE LEVEL LADDER inside MEDIUM (keep this table current):
--
--     ~2   Cast Bar Z                      (inherited, no explicit call)
--     10   UFZ unit frames                 unitframesz/engine.lua
--     20   group aura icons                groupauras/icons.lua
--     25   ScootAuras shells and groups    scootauras/engine.lua, groups.lua
--     30   CDM Custom Group containers     cooldowns/customgroups/core.lua
--     35   CDM Tracked Bars vertical       cooldowns/trackedbars/vertical.lua
--     49   PRD bar background overlay      prd/bars.lua
--     50   PRD bar foreground overlay      prd/bars.lua
--     ~55  PRD border containers           (derived: foreground level + 5)
--     100  PRD number text overlay         prd/text.lua
--     100  minimap darkening               minimap/overlay.lua
--     200  minimap pin button              minimap/overlay.lua
--
-- Panels a Blizzard pane RAISES land above all of these, which is the point.
--
-- LEVEL GOVERNS THE MOUSE TOO, not just drawing: WoW hit-tests by strata, then
-- frame level, then insertion order. A mouse-enabled frame at the floor of the
-- band silently loses OnEnter/OnClick to anything above it -- nothing errors,
-- the tooltip just stops appearing.
--
-- BUT LEVEL IS OFTEN THE WRONG LEVER, because mouse input is TWO independent
-- flags: SetMouseClickEnabled (clicks) and SetMouseMotionEnabled (hover).
-- EnableMouse sets both; legacy IsMouseEnabled() reports only the CLICK flag.
-- Click-only = transparent to hover; motion-only = transparent to clicks.
-- Level cannot help when the frame you lose to is a Blizzard system frame
-- (writing its level is taint -- the Cooldown Viewers sit at MEDIUM level 2,
-- motion-only) or when your own frame must stay high to DRAW correctly:
-- drawing and hit-testing share the one number, and only the flag split
-- separates them. Rule: an invisible catch-all input surface takes clicks only
-- -- that is why the UFZ click overlay calls SetMouseMotionEnabled(false).
-- Diagnose with /scoot debug hover before theorising. Full write-up and the
-- current mouse-surface table: ADDONCONTEXT/docs/framestrata.md.
--
-- THE EXCEPTION: a frame that decorates a Blizzard panel (rather than the
-- world) must not pick a strata at all -- it should ride whatever strata its
-- anchor is on, so it is occluded together with the thing it decorates. That is
-- MatchAnchor, and the Dungeon Journal loot checkboxes are its first user.
--
-- Out of scope for both helpers: Scoot's own settings window, pickers,
-- dropdowns and context menus. Those are things the user opened on purpose and
-- belong above the game UI; they set DIALOG/FULLSCREEN_DIALOG directly.
--------------------------------------------------------------------------------
local addonName, addon = ...

addon.Strata = addon.Strata or {}
local Strata = addon.Strata

-- The one strata every Scoot in-world element uses.
Strata.HUD = "MEDIUM"

-- Put a Scoot-owned HUD frame in the MEDIUM band.
--
-- `level` is optional but strongly encouraged: a frame created as a child of
-- UIParent (level 0) otherwise lands at level 1, the floor of the band, under
-- every other Scoot overlay. Pass a value from the ladder above.
function Strata.ApplyHUD(frame, level)
    if not frame or not frame.SetFrameStrata then return end
    pcall(frame.SetFrameStrata, frame, Strata.HUD)
    if level and frame.SetFrameLevel then
        pcall(frame.SetFrameLevel, frame, level)
    end
end

-- Put a decorator on the same strata as the Blizzard frame it decorates, `bump`
-- levels above it. Use this instead of ApplyHUD whenever the frame only makes
-- sense while some panel is open -- it inherits that panel's occlusion for free.
--
-- Safe to call repeatedly: pooled decorators move between recycled ScrollBox
-- buttons, and each attach re-reads the new anchor.
function Strata.MatchAnchor(frame, anchor, bump)
    if not frame or not frame.SetFrameStrata then return end
    if not anchor then return end

    if anchor.GetFrameStrata then
        local ok, strata = pcall(anchor.GetFrameStrata, anchor)
        if ok and strata then
            pcall(frame.SetFrameStrata, frame, strata)
        end
    end

    if frame.SetFrameLevel and anchor.GetFrameLevel then
        local ok, base = pcall(anchor.GetFrameLevel, anchor)
        pcall(frame.SetFrameLevel, frame, (ok and base or 0) + (bump or 0))
    end
end
