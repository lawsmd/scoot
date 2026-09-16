--------------------------------------------------------------------------------
-- forever/camelot.lua
-- Camelot's entry point.
--
-- Camelot and Scoot are two addons cut from one working tree. WoW picks an
-- addon's TOC by matching the basename to the folder name, so the folder
-- `Scoot` reads Scoot.toc and a folder named `Camelot` pointed at the same
-- tree reads Camelot.toc. On this machine that second folder is a junction:
--
--   mklink /J "...\_retail_\Interface\AddOns\Camelot" "...\AddOns\Scoot"
--
-- Both addons then load in the retail client at once, each with its own saved
-- variables and its own checkbox at character select.
--
-- The files Camelot.toc borrows out of core/ are listed, never copied. WoW
-- hands each addon a different `addon` table through the vararg below, so a
-- borrowed file builds a second, private instance here and Scoot's copy never
-- sees it. A file earns a place on that list by being needed, not by looking
-- reusable.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Identity resolves through the table rather than a literal, so a file that
-- later moves to the shared tree carries no brand of its own. Nothing under
-- forever/ reads the other addon's global.
addon.Brand = "Camelot"
addon.MediaPath = "Interface\\AddOns\\" .. addonName .. "\\"
addon.SlashToken = "camelot"

_G.CamelotAddon = addon

-- One namespace for the unit frames, filled by the files after this one.
addon.UnitFrames = addon.UnitFrames or {}
