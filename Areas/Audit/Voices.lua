local ADDON_NAME, NS = ...
local Utils, D, L = NS.Utils, NS.AuditData, NS.L

-- Chat messages for Audit tile clicks, in the player's race voice (or Neutral), addressed to whoever can answer.
-- Placeholders: {spell} = spell name as plain "[Name]" (never a link), {who} = the caster's first name when exactly
-- one other group member can provide it, else the plural class ("Paladins"), {name} = thank-you target's first name,
-- {type} = dispel type. Lines with {who} start with the address, so they read right with a name or a plural.
-- Design + review: kb/addons/Bulwark-Voices.md.
local Voices = {}
NS.AuditVoices = Voices

-- Fields per voice (a race voice falls back to NEUTRAL for anything it lacks):
--   request (addressed, any buff), requestByBuff (NEUTRAL: addressed lines per messageKey, DEFAULT for the rest),
--   requestNoWho, thanks, dispelWho, dispelNoWho, healthstone (addressed), healthstoneNoWho.
Voices.DATA = {
    NEUTRAL = {
        requestByBuff = {
            FORTITUDE = {
                "{who}, could you bolster my health with {spell}?",
                "{who}, my shield is strong, but my health is low. {spell} please!",
                "Fortify me, {who}! I could use {spell}.",
            },
            SPIRIT = {
                "{who}, I need the guidance of the {spell}.",
                "{who}, if you can spare the mana, {spell} please!",
                "{who}, my spirit is willing, but the buff is missing. {spell} please.",
            },
            MARK_OF_THE_WILD = {
                "{who}, grant me the {spell} if you can!",
                "{who}, the spirits whisper... I need {spell}!",
                "{who}, my fur needs thickening. {spell} please!",
            },
            THORNS = {
                "{who}, a layer of {spell} would help with threat.",
                "{who}, I could use {spell} to make them pay for striking me!",
                "{who}, let them bleed when they strike. {spell} please!",
            },
            ARCANE_INTELLECT = {
                "{who}, I need some brilliance! {spell} please!",
                "{who}, my mind feels dull. {spell}, if you please!",
                "{who}, grant me the intellect to hold this aggro! ({spell})",
            },
            BATTLE_SHOUT = {
                "{who}, let me hear your {spell}!",
                "Roar for glory, {who}! I need {spell}!",
                "Strengthen our arms, {who}! {spell} please!",
            },
            KINGS = {
                "{who}, grant me the majesty of {spell}!",
                "{who}, a tank is nothing without a crown. {spell} please!",
                "A touch of royalty would help, {who}. {spell} please!",
            },
            MIGHT = {
                "{who}, grant me the strength to crush my foes! {spell}!",
                "{who}, my swings are weak. I need {spell}!",
                "Empower me, {who}! {spell}!",
            },
            WISDOM = {
                "{who}, my mana is draining fast. {spell} please!",
                "{who}, grant me the clarity of the Light. {spell}!",
                "{who}, I need mana to hold the line! {spell} please!",
            },
            LIGHT = {
                "{who}, illumine my path and my healing! {spell}!",
                "{who}, let the healers' light shine brighter on me! {spell}!",
                "{who}, I need the holy light to mend me faster. {spell} please!",
            },
            PALADIN_AURA = {
                "{who}, I need an Aura ({spell})!",
                "{who}, my armor needs boosting! {spell} please!",
                "We are missing an Aura, {who}! ({spell})",
            },
            DEFAULT = {
                "{who}, I could use {spell}!",
                "{who}, can I get {spell} please?",
                "{who}, {spell} please!",
            },
        },
        requestNoWho = {
            "I could use {spell}!",
            "Can I get {spell} please?",
            "Buff {spell} please!",
        },
        thanks = {
            "Thanks for the {spell}, {name}!",
            "Got the {spell} - thank you, {name}!",
            "Much appreciated, {spell} received. Thanks {name}!",
        },
        dispelWho = { "{who}, I have a {type} effect on me - dispel me please!" },
        dispelNoWho = { "I have a {type} effect on me - dispel me please!" },
        healthstone = { "{who}, I need a Healthstone please!" },
        healthstoneNoWho = { "I need a Healthstone please!" },
    },

    HUMAN = {
        request = {
            "{who}, by the Light, I could use {spell} before the next pull!",
            "{who}, I'll hold the line if you lend me {spell}!",
            "{who}, steel and shield are ready. Only {spell} is missing!",
            "{who}, for the Alliance! {spell}, please!",
            "{who}, the Light favors the prepared. {spell}, if you would!",
        },
        requestNoWho = {
            "By the Light, I could use {spell} before we press on!",
            "Shield up, sword ready, {spell} missing. Anyone?",
        },
        thanks = {
            "Light bless you, {name}! {spell} received.",
            "Much obliged, {name}. The {spell} will serve me well.",
            "Thank you for the {spell}, {name}. For the Alliance!",
        },
        dispelWho = { "{who}, I've got a {type} effect on me. Cleanse me, by the Light!" },
        dispelNoWho = { "Some {type} foulness clings to me. Can anyone dispel it?" },
        healthstone = {
            "{who}, a Healthstone for the one taking the blows?",
            "{who}, could you spare a Healthstone? I'd rather not test the Spirit Healer's patience.",
        },
    },

    DWARF = {
        request = {
            "{who}, by me beard, I'd fight better with {spell}!",
            "{who}, a dwarf's as stubborn as stone, but {spell} wouldn't hurt!",
            "{who}, toss me some {spell} and I'll hold 'em like a mountain!",
            "{who}, I've had me ale, now I need {spell}!",
            "{who}, for Ironforge! Lend me {spell}, would ye?",
        },
        requestNoWho = {
            "By me beard, I'm missin' {spell}! Anyone?",
            "Stone-stubborn, aye, but {spell} would help. Anyone spare it?",
        },
        thanks = {
            "Ye're a gem, {name}! Thanks for the {spell}.",
            "Next round's on me, {name}. Cheers for the {spell}!",
            "That's the stuff, {name}! {spell} received, thank ye.",
        },
        dispelWho = { "{who}, some {type} nonsense is stuck to me. Clear it, would ye?" },
        dispelNoWho = { "Got a {type} effect on me, and it's worse than a hangover. Dispel, anyone?" },
        healthstone = {
            "{who}, a Healthstone for the dwarf up front, if ye please!",
            "{who}, spare a Healthstone? Stone's a dwarf's best friend.",
        },
    },

    NIGHTELF = {
        request = {
            "{who}, Elune light your path. Would you grant me {spell}?",
            "{who}, Ishnu-alah. The battle ahead calls for {spell}.",
            "{who}, the forest remembers kindness. {spell}, please.",
            "{who}, I will stand like the ancients if you grant me {spell}.",
            "{who}, may the moon guide your hand. I am in need of {spell}.",
        },
        requestNoWho = {
            "By Elune, I am without {spell}. Can anyone help?",
            "The night is long and I lack {spell}. Who can help?",
        },
        thanks = {
            "Elune-adore, {name}. The {spell} is a gift.",
            "Ishnu-alah, {name}. My thanks for the {spell}.",
            "May the moon light your way, {name}. Thank you for the {spell}.",
        },
        dispelWho = { "{who}, a {type} taint clings to me. Please cleanse it." },
        dispelNoWho = { "A {type} taint clings to me. Can anyone cleanse it?" },
        healthstone = {
            "{who}, might I trouble you for a Healthstone?",
            "{who}, a Healthstone, please. The night is long.",
        },
    },

    GNOME = {
        request = {
            "{who}, my calculations show a {spell}-shaped hole in my defenses!",
            "{who}, quick upgrade request: one {spell}, please!",
            "{who}, for Gnomeregan! I need {spell}!",
            "{who}, small tank, big job. {spell} would help a lot!",
            "{who}, my survival odds go up 37% with {spell}! Roughly.",
        },
        requestNoWho = {
            "System check: {spell} missing! Anyone have a spare?",
            "Diagnostics say I'm lacking {spell}. Any volunteers?",
        },
        thanks = {
            "Splendid, {name}! {spell} installed!",
            "Thanks, {name}! The {spell} works perfectly!",
            "Efficiency up! Thanks for the {spell}, {name}!",
        },
        dispelWho = { "{who}, I've got a {type} malfunction! Please dispel it!" },
        dispelNoWho = { "Error: {type} effect detected! Can someone dispel it?" },
        healthstone = {
            "{who}, could I get a Healthstone? Emergency repair kit!",
            "{who}, a Healthstone for my emergency kit, please!",
        },
    },

    ORC = {
        request = {
            "{who}, Lok'tar! Give me {spell} and I'll crush them!",
            "{who}, blood and thunder! I need {spell}!",
            "{who}, Throm-Ka. The front line needs {spell}.",
            "{who}, an orc doesn't beg, but I'd take {spell}!",
            "{who}, for the Horde! Give me {spell}!",
        },
        requestNoWho = {
            "Lok'tar! I need {spell}! Who has it?",
            "Blood and thunder! I'm missing {spell}. Anyone?",
        },
        thanks = {
            "Aka'Magosh, {name}! The {spell} is welcome.",
            "You fight with honor, {name}. Thanks for the {spell}!",
            "Lok'tar, {name}! {spell} received!",
        },
        dispelWho = { "{who}, some {type} filth clings to me! Purge it!" },
        dispelNoWho = { "Some {type} filth clings to me! Who can purge it?" },
        healthstone = {
            "{who}, a Healthstone for the one up front!",
            "{who}, give me a Healthstone. I don't plan to die today.",
        },
    },

    UNDEAD = {
        request = {
            "{who}, I'm already dead, but {spell} would still help.",
            "{who}, for the Dark Lady. {spell}, if you please.",
            "{who}, my flesh is weak. Literally. {spell}?",
            "{who}, death came for me once already. Help me avoid a second visit with {spell}.",
            "{who}, I'd feel more alive with {spell}. Figuratively.",
        },
        requestNoWho = {
            "I'm missing {spell}. Not that I feel much anyway.",
            "The Dark Lady watches, and I still lack {spell}. Anyone?",
        },
        thanks = {
            "Dark Lady watch over you, {name}. Thanks for the {spell}.",
            "The {spell} is noted, {name}. Thank you.",
            "How kind, {name}. Thanks for the {spell}.",
        },
        dispelWho = { "{who}, something {type} is festering on me. More than usual. Dispel it?" },
        dispelNoWho = { "A {type} affliction clings to me. Can anyone remove it?" },
        healthstone = {
            "{who}, a Healthstone? My bones are wearing thin.",
            "{who}, I'll take a Healthstone. Dying twice is tiresome.",
        },
    },

    TAUREN = {
        request = {
            "{who}, the Earth Mother would smile on {spell}. Will you grant it?",
            "{who}, walk with the Earth Mother, and lend me {spell}.",
            "{who}, I stand firm as the plains, but {spell} would help.",
            "{who}, the ancestors call for strength. {spell}, please.",
            "{who}, the herd is strong together. Grant me {spell}.",
        },
        requestNoWho = {
            "By the Earth Mother, I lack {spell}. Who can help?",
            "The ancestors whisper that I'm missing {spell}. Anyone?",
        },
        thanks = {
            "Walk with the Earth Mother, {name}. Thank you for the {spell}.",
            "The ancestors smile on you, {name}. My thanks for the {spell}.",
            "Your kindness is noted, {name}. {spell} received.",
        },
        dispelWho = { "{who}, a {type} sickness clouds my spirit. Please cleanse it." },
        dispelNoWho = { "A {type} sickness clouds my spirit. Who can cleanse it?" },
        healthstone = {
            "{who}, a Healthstone for the one who stands in front?",
            "{who}, may I have a Healthstone? The ancestors aren't ready for me yet.",
        },
    },

    TROLL = {
        request = {
            "{who}, de loa say I be needin' {spell}, mon!",
            "{who}, gimme dat {spell} and I hold de line!",
            "{who}, Darkspear never die! But {spell} would help, mon.",
            "{who}, de spirits be restless. {spell}, please!",
            "{who}, ya got some {spell} for me, mon?",
        },
        requestNoWho = {
            "I be missin' {spell}, mon! Who got it?",
            "De loa be watchin', and I still need {spell}!",
        },
        thanks = {
            "Ya got it, {name}! Thanks for de {spell}, mon.",
            "De loa smile on ya, {name}. {spell} received!",
            "Stay away from de voodoo, {name}... but thanks for de {spell}!",
        },
        dispelWho = { "{who}, some {type} voodoo be stickin' to me! Clear it, mon!" },
        dispelNoWho = { "Some {type} voodoo be stickin' to me! Who can clear it?" },
        healthstone = {
            "{who}, gimme one of dem Healthstones, mon!",
            "{who}, a Healthstone for de one takin' de hits?",
        },
    },

    -- Shen'dorei, Alliance: pragmatic scholars, self-reliance, arcane
    HIGH_ORDER = {
        request = {
            "{who}, the High Order values preparation. {spell}, please.",
            "{who}, I see no reason to fight without {spell}. Would you oblige?",
            "{who}, self-reliance has its limits. I would welcome {spell}.",
            "{who}, the scholars of Eldre'Thalas never fought unprepared. Lend me {spell}.",
            "{who}, the shen'dorei no longer wait on the winds. I'll ask you instead: {spell}, please.",
        },
        requestNoWho = {
            "The High Order fights prepared, and I lack {spell}. Can anyone help?",
            "A sensible request: {spell}, from whoever can spare it.",
        },
        thanks = {
            "The High Order remembers its friends, {name}. Thank you for the {spell}.",
            "A sound decision, {name}. My thanks for the {spell}.",
            "Your aid is noted, {name}. {spell} received with gratitude.",
        },
        dispelWho = { "{who}, I carry a {type} effect. Please remove it before it spreads." },
        dispelNoWho = { "A {type} effect has taken hold of me. Can anyone remove it?" },
        healthstone = {
            "{who}, a Healthstone would be a prudent precaution.",
            "{who}, might I have a Healthstone? Even scholars bleed.",
        },
    },

    -- Shen'dorei, Horde: wind spirits, Skywall, skysight
    WINDSHAPER = {
        request = {
            "{who}, the winds of Skywall carry my plea: {spell}, please!",
            "{who}, may the wind fill your sails. I need {spell}.",
            "{who}, my skysight sees a hard fight ahead. {spell}, please!",
            "{who}, the wind spirits would want me ready. Will you grant {spell}?",
            "{who}, lend me {spell} and I'll stand fast as the Skywall gale!",
        },
        requestNoWho = {
            "The winds whisper that I lack {spell}. Who can help?",
            "By the spirits of Skywall, I'm missing {spell}!",
        },
        thanks = {
            "May the wind spirits guide you, {name}. My thanks for the {spell}.",
            "The winds favor you, {name}! {spell} received.",
            "Swift winds to you, {name}. Thank you for the {spell}.",
        },
        dispelWho = { "{who}, a {type} effect clouds my skysight. Please clear it!" },
        dispelNoWho = { "A {type} effect clouds my skysight. Can anyone clear it?" },
        healthstone = {
            "{who}, a Healthstone, before the winds carry me off?",
            "{who}, might I have a Healthstone? I'd like to see Skywall again.",
        },
    },
}

-- UnitRace raceID -> voice. DB2 ChrRaces (wowf): 95 High Order Skyborne (Alliance), 96 Windshaper Skyborne (Horde),
-- both "Skyborne" by English name [data].
Voices.RACE_IDS = {
    [1] = "HUMAN", [2] = "ORC", [3] = "DWARF", [4] = "NIGHTELF", [5] = "UNDEAD", [6] = "TAUREN", [7] = "GNOME",
    [8] = "TROLL", [95] = "HIGH_ORDER", [96] = "WINDSHAPER",
}
local RACE_FILES = {
    Human = "HUMAN", Orc = "ORC", Dwarf = "DWARF", NightElf = "NIGHTELF", Scourge = "UNDEAD", Tauren = "TAUREN",
    Gnome = "GNOME", Troll = "TROLL",
}

local raceKey, raceName -- cached once read (the player's own race never changes)

-- The player's race voice key ("WINDSHAPER", ...) and localized race name, or nil when unknown / unsupported.
function Voices.PlayerRace()
    if raceKey then return raceKey, raceName end
    local ok, localized, file, id = pcall(UnitRace, "player")
    if not ok or Utils.IsSecret(localized) or Utils.IsSecret(file) or Utils.IsSecret(id) then return nil end
    local key = Voices.RACE_IDS[id] or RACE_FILES[file]
    if not key and file == "Skyborne" then
        key = (UnitFactionGroup("player") == "Horde") and "WINDSHAPER" or "HIGH_ORDER"
    end
    if key then raceKey, raceName = key, localized end
    return key, localized
end

-- The voice table in use: the player's race when the option is on and the race is known, else NEUTRAL.
function Voices.Current()
    if NS.db.audit.raceVoice then
        local key = Voices.PlayerRace()
        if key and Voices.DATA[key] then return Voices.DATA[key], key end
    end
    return Voices.DATA.NEUTRAL, "NEUTRAL"
end

local function Field(voice, field)
    return voice[field] or Voices.DATA.NEUTRAL[field]
end

local function Pick(list)
    return list[math.random(1, #list)]
end

function Voices.Fill(template, vars)
    return (template:gsub("{(%a+)}", function(k) return vars[k] end))
end

local function FirstName(unit)
    local ok, name = pcall(UnitName, unit)
    name = ok and Utils.SafeString(name, nil)
    if name and name ~= "" then return name end
end

-- How to address these group members: one -> first name; several of one class -> plural class; else nil.
function Voices.Address(members)
    if #members == 0 then return nil end
    if #members == 1 then return FirstName(members[1].unit) end
    local class = members[1].class
    for _, m in ipairs(members) do
        if m.class ~= class then return nil end
    end
    return L["CLASS_PLURAL_" .. class]
end

-- {who} for a tile: providers of its buff (entry.provider / entry.subgroupOnly), or who can remove its debuff type.
function Voices.Who(entry)
    local Roster = NS.AuditRoster
    if entry.kind == "debuff" then
        local requirements = D.DISPEL_LEVELS[entry.dispelType]
        return requirements and Voices.Address(Roster:Dispellers(requirements)) or nil
    end
    if entry.provider then
        return Voices.Address(Roster:Others(entry.provider, entry.subgroupOnly))
    end
end

-- The group message for a tile click (without the "fading in" suffix).
function Voices.Request(entry, spellText)
    local voice = Voices.Current()
    local who = Voices.Who(entry)
    local pool
    if entry.kind == "debuff" then
        pool = Field(voice, who and "dispelWho" or "dispelNoWho")
    elseif entry.key == "HEALTHSTONE" then
        pool = Field(voice, who and "healthstone" or "healthstoneNoWho")
    elseif who then
        pool = voice.request
        if not pool then
            local byBuff = Field(voice, "requestByBuff")
            pool = byBuff[entry.messageKey] or byBuff.DEFAULT
        end
    else
        pool = Field(voice, "requestNoWho")
    end
    local dtype = entry.dispelType
    return Voices.Fill(Pick(pool), { who = who, spell = spellText,
                                     type = dtype and (L[dtype] or dtype) or nil })
end

-- The thank-you whisper.
function Voices.Thanks(spellText, name)
    return Voices.Fill(Pick(Field(Voices.Current(), "thanks")), { spell = spellText, name = name })
end
