local ADDON_NAME, NS = ...

-- Spell/item IDs for WoW: Forever 1.60.1, collected from Wowhead's Forever database (workspace tools/wowhead.ps1; from TankAuditForever Data/Buffs.lua).
-- Auras carry the ID of the rank that was cast, so every rank is listed. Verify with /bwk audit dump.
-- Display names come from the client (C_Spell.GetSpellName) unless an entry sets `label` (a locale key).

NS.AuditData = {}
local D = NS.AuditData

-- Self buffs per tank class. `stance` = shapeshift spellID that must be active (an OOC prompt, not an aura tile).
-- `requireKnown` = only check when the player knows the spell. `skipSolo` = ignore when ungrouped.
-- `warn` = seconds before expiry at which the tile's countdown turns red.
-- `alert` = in-combat sound + glow, timed from your own last cast (own casts aren't secret);
-- `duration` = fallback until the real duration is learned out of combat.
D.SELF = {
    WARRIOR = {
        { key = "BATTLE_SHOUT", ids = { 6673, 5242, 6192, 11549, 11550, 11551, 25289, 27578 }, warn = 15,
          requireKnown = true, alert = true, duration = 180, icon = "Interface\\Icons\\Ability_Warrior_BattleShout" },
        { key = "DEFENSIVE_STANCE", stance = 71, skipSolo = true, icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance" },
    },
    PALADIN = {
        { key = "RIGHTEOUS_FURY", ids = { 25780 }, warn = 60, requireKnown = true, alert = true, duration = 1800,
          icon = "Interface\\Icons\\Spell_Holy_SealOfFury" },
    },
}

-- Group buffs from other classes. Checked only when a `provider` class is in the group
-- (`subgroupOnly`: in your raid subgroup). `skipFor` = tank classes that don't need it.
-- `greater` = group/greater versions that also satisfy the buff.
D.GROUP = {
    { key = "FORTITUDE", provider = "PRIEST", icon = "Interface\\Icons\\Spell_Holy_WordFortitude",
      ids = { 1243, 1244, 1245, 2791, 10937, 10938 }, greater = { 21562, 21564 } },
    { key = "SPIRIT", provider = "PRIEST", icon = "Interface\\Icons\\Spell_Holy_DivineSpirit", skipFor = { WARRIOR = true }, -- mana regen only
      ids = { 14752, 14818, 14819, 27841 }, greater = { 27681 } },
    { key = "MARK_OF_THE_WILD", provider = "DRUID", icon = "Interface\\Icons\\Spell_Nature_Regeneration",
      ids = { 1126, 5232, 6756, 5234, 8907, 9884, 9885, 1291335, 1310503 }, greater = { 21849, 21850 } },
    { key = "THORNS", provider = "DRUID", icon = "Interface\\Icons\\Spell_Nature_Thorns",
      ids = { 467, 782, 1075, 8914, 9756, 9910 } },
    { key = "ARCANE_INTELLECT", provider = "MAGE", icon = "Interface\\Icons\\Spell_Holy_MagicalSentry", skipFor = { WARRIOR = true },
      ids = { 1459, 1460, 1461, 10156, 10157 }, greater = { 23028 } },
    { key = "BATTLE_SHOUT", provider = "WARRIOR", icon = "Interface\\Icons\\Ability_Warrior_BattleShout", subgroupOnly = true, skipFor = { WARRIOR = true },
      ids = { 6673, 5242, 6192, 11549, 11550, 11551, 25289, 27578 } },
    { key = "PALADIN_AURA", provider = "PALADIN", icon = "Interface\\Icons\\Spell_Holy_DevotionAura", subgroupOnly = true, label = "PALADIN_AURA",
      castId = 465, -- Devotion Aura: what a paladin tank casts when no aura is up
      ids = { 465, 643, 1032, 10290, 10291, 10292, 10293,   -- Devotion
              7294, 10298, 10299, 10300, 10301,             -- Retribution
              19746,                                        -- Concentration
              19876, 19895, 19896,                          -- Shadow Resistance
              19888, 19897, 19898,                          -- Frost Resistance
              19891, 19899, 19900 } },                      -- Fire Resistance
}

-- Paladin blessings, ordered by the user's priority list (NS.DefaultConfig.audit.blessingPriority).
-- Blessing of Sanctuary isn't in Forever (Wowhead); Kings is baseline (not a talent) on Forever.
D.BLESSINGS = {
    KINGS  = { icon = "Interface\\Icons\\Spell_Magic_MageArmor", ids = { 20217 }, greater = { 25898 } },
    MIGHT  = { icon = "Interface\\Icons\\Spell_Holy_FistOfJustice", ids = { 19740, 19834, 19835, 19836, 19837, 19838, 25291 }, greater = { 25782, 25916 } },
    LIGHT  = { icon = "Interface\\Icons\\Spell_Holy_PrayerOfHealing02", ids = { 19977, 19978, 19979 }, greater = { 25890 } },
    WISDOM = { icon = "Interface\\Icons\\Spell_Holy_SealOfWisdom", ids = { 19742, 19850, 19852, 19853, 19854, 25290 }, greater = { 25894, 25918 } },
}

-- Fixed tile order for blessing tiles (which ones show comes from the user's priority list)
D.BLESSING_ORDER = { "KINGS", "MIGHT", "LIGHT", "WISDOM" }

-- Buffs a tank wants removed (shown as click-to-cancel).
D.UNWANTED = {
    { key = "SALVATION", ids = { 1038, 25895 } },
}

-- Consumables (in groups and/or solo: audit.consumablesInGroup / consumablesSolo)
D.WELL_FED = { 19705, 19706, 19708, 19709, 19710, 19711, 24799, 24870, 25694, 25941,
               1225778, 1225779, 1225780, 1225782, 1248406, 1248420, 1248421, 1248422, 1248688,
               1249519, 1249520, 1249521, 1249523, 1249907, 1249926, 1249927, 1283082, 1294007,
               1302064, 1319310,
               25661 }  -- Dirge's Kickin' Chimaerok Chops: "Increased Stamina", not named Well Fed [data]
-- Elixir / flask BUFF spell IDs (not item IDs), generated 2026-10-05 from Wowhead Forever's elixir and flask item
-- categories: each item's Use: spell. Utility draughts (water breathing, detection, Giant Growth, Noggenfogger) and
-- plain alcohol are excluded. Forever renamed some buffs after their item (673 = Elixir of Minor Defense) [in-game].
D.ELIXIRS = {
    2367, -- Elixir of Minor Strength
    2374, -- Elixir of Minor Agility
    2378, -- Elixir of Minor Fortitude
    3219, -- Minor Troll's Blood Elixir
    3166, -- Elixir of Wisdom
    3222, -- Lesser Troll's Blood Elixir
    3220, -- Elixir of Lesser Defense
    3160, -- Elixir of Lesser Agility
    3164, -- Elixir of Ogre Strength
    3593, -- Elixir of Lesser Fortitude
    3223, -- Troll's Blood Elixir
    673, -- Elixir of Minor Defense
    7844, -- Elixir of Fire Power
    10667, -- R.O.I.D.S.
    10668, -- Lung Juice Cocktail
    10669, -- Ground Scorpok Assay
    10692, -- Cerebral Cortex Compound
    10693, -- Gizzard Gum
    11328, -- Elixir of Agility
    11349, -- Elixir of Defense
    11371, -- Gift of Arthas
    11390, -- Arcane Elixir
    11396, -- Elixir of Greater Intellect
    11334, -- Elixir of Greater Agility
    11405, -- Elixir of Greater Strength
    11406, -- Potion of Demon Slaying
    11474, -- Elixir of Shadow Power
    17038, -- Winterfall Firewater
    11348, -- Elixir of Greater Defense
    17535, -- Elixir of the Sages
    17538, -- Elixir of the Mongoose
    17537, -- Elixir of Brute Force
    17539, -- Greater Arcane Elixir
    21920, -- Elixir of Frost Power
    24361, -- Major Troll's Blood Elixir
    24363, -- Mageblood Elixir
    24382, -- Spirit of Zanza
    24417, -- Sheen of Zanza
    24383, -- Swiftness of Zanza
    1310077, -- Elixir of Holy Power
    439959, -- Lesser Arcane Elixir
    1245244, -- Minor Arcane Elixir
    1245249, -- Elixir of Minor Force
    1250889, -- Draught of Predatory Senses
    1250918, -- Elixir of Cunning
    1250920, -- Elixir of the Phalanx
    1250922, -- Minor Cleric's Elixir
    1250924, -- Lesser Cleric's Elixir
    1250925, -- Cleric's Elixir
    1250926, -- Greater Cleric's Elixir
    1250928, -- Elixir of Fortitude
    1250931, -- Elixir of Greater Fortitude
    1250932, -- Elixir of Wicked Regeneration
    1250940, -- Elixir of the Owl
    1250941, -- Elixir of Sages
    1250942, -- Minor Mageblood Elixir
    1250944, -- Lesser Mageblood Elixir
    1250948, -- Greater Mageblood Elixir
    1250971, -- Lesser Arcane Elixir
    1250972, -- Elixir of Nature Power
    1250974, -- Elixir of Minor Spirit
    1250976, -- Elixir of Lesser Spirit
    1250978, -- Elixir of Spirit
    1250979, -- Elixir of Greater Spirit
    1250981, -- Elixir of the Whale
    1250984, -- Elixir of Strength
    1250985, -- Elixir of Ferocity
    1250986, -- Elixir of the Grizzly
    1250988, -- Elixir of Lesser Intellect
    1250989, -- Elixir of Intellect
}
D.FLASKS = {
    17626, -- Flask of the Titans
    17627, -- Flask of Distilled Wisdom
    17628, -- Flask of Supreme Power
    17629, -- Flask of Chromatic Resistance
    1293740, -- Flask of Natural Accuracy
    1293741, -- Flask of Natural Aggression
    1293742, -- Flask of Natural Precision
    1293743, -- Flask of Natural Swiftness
}

D.HEALTHSTONES = { 5512, 19004, 19005, 5511, 19006, 19007, 5509, 19008, 19009,
                   5510, 19010, 19011, 9421, 19012, 19013 }

-- Fallback icons for category entries
D.ICONS = {
    WELL_FED = "Interface\\Icons\\Spell_Misc_Food",
    WEAPON_BUFF = "Interface\\Icons\\INV_Stone_SharpeningStone_01",
    ELIXIR = "Interface\\Icons\\INV_Potion_32",
    FLASK = "Interface\\Icons\\INV_Potion_62",
    HEALTHSTONE = "Interface\\Icons\\INV_Stone_04",
    DEFENSE_SKILL = "Interface\\Icons\\Ability_Defend",
    NO_SHIELD = "Interface\\Icons\\INV_Shield_06",
    DURABILITY = "Interface\\Icons\\Trade_BlackSmithing",
    UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark",
}

-- Which classes can remove each debuff type, and from which level (Wowhead Forever learn levels:
-- Dispel Magic 18, Cleanse 42, Remove Lesser Curse 18, Remove Curse 24, Cure Poison 14 (druid) / 16 (shaman),
-- Purify 8, Cure Disease 14 (priest) / 22 (shaman)).
D.DISPEL_LEVELS = {
    Magic   = { PRIEST = 18, PALADIN = 42 },
    Curse   = { MAGE = 18, DRUID = 24 },
    Poison  = { DRUID = 14, PALADIN = 8, SHAMAN = 16 },
    Disease = { PRIEST = 14, PALADIN = 8, SHAMAN = 22 },
}
D.DISPEL_ORDER = { "Magic", "Curse", "Poison", "Disease" }

-- The player's own dispels per debuff type (first known spell is cast)
D.PLAYER_DISPELS = {
    PALADIN = {
        Magic   = { 4987 },          -- Cleanse
        Poison  = { 4987, 1152 },    -- Cleanse, Purify
        Disease = { 4987, 1152 },
    },
    WARRIOR = {},
}

-- Chat messages (requests, thank-yous) live in Voices.lua.
