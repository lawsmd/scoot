-- searchterms.lua - The short words players type for settings that spell
-- themselves out in full.
--
-- Contract: data only. The settings framework reads addon.SearchVocabulary and
-- knows nothing about what is in it, which is what lets the framework move to a
-- shared tree while this table stays with the product. Expansion runs on the
-- query and never on the index, so editing this file needs no index rebuild.
--
-- Scope is abbreviations. Structure carries the rest: the page path and the
-- section title are matched fields, and spacing and plurals fold, so "castbar"
-- already reaches "Cast Bars" and "unitframe" reaches "Unit Frames" with no
-- entry here. A general thesaurus was considered and refused: it has to be fed
-- every time a feature ships, and it goes stale in silence.
--
-- The key is what someone types. The values are words the index carries, in a
-- label, a page path or a section title. A value may be a phrase, and every
-- word of the phrase has to land in the same field for it to count.
local _, addon = ...

addon.SearchVocabulary = {
    synonyms = {
        hp   = { "health" },
        mp   = { "power" },
        cd   = { "cooldown" },
        cdm  = { "cooldown manager" },
        prd  = { "personal resource" },
        sct  = { "scrolling combat text" },
        qol  = { "quality of life" },
        ui   = { "interface" },
        tot  = { "target of target" },
        tof  = { "target of focus" },
        dps  = { "damage meters" },
        ooc  = { "out of combat" },
    },

    -- Words a page answers to that its own name does not carry, keyed by nav
    -- key. The matcher reads it and a page entry inherits it, so the seam is
    -- live; it stays empty because page names and section titles already carry
    -- the vocabulary, and a hand-fed list per page is the thing this file is
    -- scoped away from.
    pages = {},
}
