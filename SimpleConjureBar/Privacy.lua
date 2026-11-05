-- SimpleConjureBar - what a bug report may carry (ruleset plan 2026-10-17-bug-report-details)
-- Everything the addon collects passes an allowlist (D.REPORT_SAFE): a string not on it is
-- reported by its length only. Free text and error messages cannot be allowlisted - they are
-- the bug - so they pass a filter for the names the client knows, GUIDs, BattleTags, account
-- folders, e-mail addresses and file paths. The report is built out of combat, where names are
-- readable (phase 1 research).

local _, ns = ...
if not ns.enabled then return end

local D = ns.D

---------------------------------------------------------------------------
-- Allowlist
---------------------------------------------------------------------------
function ns.IsSafe(s)
    s = tostring(s)
    if D.VALUE_DEFAULTS[s] ~= nil then return true end -- a settings key
    for _, p in ipairs(D.REPORT_SAFE) do
        if s:find(p) then return true end
    end
    return false
end

-- The value as the report may show it: itself if allowlisted, else its length
function ns.SafeValue(v)
    if type(v) ~= "string" then return tostring(v) end
    if ns.IsSafe(v) then return v end
    return ("<text:%d>"):format(#v)
end

-- A macro text, line by line (the gem macro has several "/use item:N" lines)
function ns.SafeMacro(text)
    local out = {}
    for line in tostring(text):gmatch("[^\n]+") do out[#out + 1] = ns.SafeValue(line) end
    return table.concat(out, " / ")
end

---------------------------------------------------------------------------
-- Names the client knows now: the player, realm, guild, group, target, focus, mouseover, the
-- trade partner. nil when one of them is secret - the filter could not compare it.
---------------------------------------------------------------------------
local IsSecret = ns.IsSecret

function ns.KnownNames()
    local names, secret = {}, false
    local function Add(v)
        if IsSecret(v) then secret = true return end
        if type(v) == "string" and #v >= 2 then names[#names + 1] = v end
    end
    local units = { "player", "pet", "target", "targettarget", "focus", "mouseover", "NPC" }
    for i = 1, 4 do units[#units + 1] = "party" .. i; units[#units + 1] = "partypet" .. i end
    for i = 1, 40 do units[#units + 1] = "raid" .. i; units[#units + 1] = "raidpet" .. i end
    for _, u in ipairs(units) do
        local name, realm = UnitName(u)
        Add(name); Add(realm)
        if not IsSecret(name) and not IsSecret(realm) and name and realm and realm ~= "" then
            Add(name .. "-" .. realm)
        end
    end
    Add(GetRealmName())
    Add(GetNormalizedRealmName())
    Add((GetGuildInfo("player")))
    if secret then return nil end
    -- longest first, so "Name-Realm" goes before "Name"
    table.sort(names, function(a, b) return #a > #b end)
    return names
end

---------------------------------------------------------------------------
-- Filter for free text, error messages, stack lines and addon names
---------------------------------------------------------------------------
-- The letters of the scripts that part words with spaces: Latin (without × and ÷), Greek,
-- Cyrillic, Armenian, Hebrew, Arabic. Any other character - punctuation, spaces, symbols, and
-- the scripts written without spaces (kana, CJK, Hangul) - ends a word, so a name inside
-- Chinese text or before a Korean particle is still found (ruleset plan
-- 2026-10-25-report-filter-fixes, after SmartBlessingBar's audit).
local LETTERS = { { 0xC0, 0xD6 }, { 0xD8, 0xF6 }, { 0xF8, 0x24F }, { 0x370, 0x3FF }, { 0x400, 0x52F },
    { 0x531, 0x556 }, { 0x561, 0x587 }, { 0x5D0, 0x5EA }, { 0x620, 0x64A }, { 0x1E00, 0x1EFF } }

local function IsWordChar(cp)
    if cp < 128 then
        return cp == 95 or (cp >= 48 and cp <= 57) or (cp >= 65 and cp <= 90) or (cp >= 97 and cp <= 122)
    end
    for _, r in ipairs(LETTERS) do
        if cp >= r[1] and cp <= r[2] then return true end
    end
    return false
end

-- The code point of the UTF-8 character starting at byte i; a stray byte is itself
local function CodePoint(text, i)
    local c = text:byte(i)
    local len = c >= 0xF0 and 4 or c >= 0xE0 and 3 or c >= 0xC0 and 2 or 1
    if len == 1 then return c end
    local cp = c % (len == 2 and 32 or len == 3 and 16 or 8)
    for k = i + 1, i + len - 1 do cp = cp * 64 + (text:byte(k) or 0) % 64 end
    return cp
end

-- Whether no word character ends at byte i (before = true) or starts there
local function Edge(text, i, before)
    if i < 1 or i > #text then return true end
    if before then
        -- back to the first byte of the character that ends at i
        local start = i
        while start > 1 and start > i - 3 do
            local b = text:byte(start)
            if b < 0x80 or b >= 0xC0 then break end
            start = start - 1
        end
        i = start
    end
    return not IsWordChar(CodePoint(text, i))
end

-- Lower case for ASCII, Latin-1 and Cyrillic capitals. Each keeps its byte length, so a
-- position in the folded text is the same position in the original.
local function Fold(s)
    s = s:lower():gsub("\195([\128-\150\152-\158])", function(b) return "\195" .. string.char(b:byte() + 32) end)
    return (s:gsub("\208([\128-\175])", function(b)
        b = b:byte()
        if b < 0x90 then return "\209" .. string.char(b + 0x10) end -- Ѐ-Џ
        if b < 0xA0 then return "\208" .. string.char(b + 0x20) end -- А-П
        return "\209" .. string.char(b - 0x20)                       -- Р-Я
    end))
end

-- Whole words only, in any case Fold knows, found as plain text (realm names hold "-", "'").
-- `lowText` is Fold(text), kept beside it so the text is folded once, not once per name; both
-- come back with the same replacements.
local function ReplaceName(text, lowText, name)
    local lowName = Fold(name)
    local out, lowOut, pos, from = {}, {}, 1, 1
    while true do
        local s, e = lowText:find(lowName, from, true)
        if not s then break end
        if Edge(lowText, s - 1, true) and Edge(lowText, e + 1, false) then
            out[#out + 1], lowOut[#lowOut + 1] = text:sub(pos, s - 1), lowText:sub(pos, s - 1)
            out[#out + 1], lowOut[#lowOut + 1] = "<name>", "<name>"
            pos = e + 1
        end
        from = e + 1
    end
    if pos == 1 then return text, lowText end
    out[#out + 1], lowOut[#lowOut + 1] = text:sub(pos), lowText:sub(pos)
    return table.concat(out), table.concat(lowOut)
end

local GUID_KINDS = { "Player", "Pet", "Creature", "Vehicle", "GameObject", "Item" }

-- The text without the characters D.HIDDEN lists, nor combining marks (U+0300-036F): inside
-- or beside a name they hide it, and in a report they mean nothing
local function LeadByte(cp)
    if cp < 0x800 then return 0xC0 + math.floor(cp / 0x40) end
    if cp < 0x10000 then return 0xE0 + math.floor(cp / 0x1000) end
    return 0xF0 + math.floor(cp / 0x40000)
end

-- The first bytes those characters can start with: any other character is kept unexamined, so
-- a long error message in any script costs one table lookup per character
local HIDDEN_LEADS = { [0xCC] = true, [0xCD] = true }
for _, r in ipairs(D.HIDDEN) do
    for b = LeadByte(r[1]), LeadByte(r[2]) do HIDDEN_LEADS[b] = true end
end

local function Visible(text)
    return (text:gsub("[\192-\247][\128-\191]*", function(ch)
        if not HIDDEN_LEADS[ch:byte()] then return nil end
        local cp = CodePoint(ch, 1)
        if cp >= 0x300 and cp <= 0x36F then return "" end
        for _, r in ipairs(D.HIDDEN) do
            if cp >= r[1] and cp <= r[2] then return "" end
        end
    end))
end

-- Folders that hold a user's name: a path from one of them runs to a quote, bracket or line
-- end, spaces included ("C:\Users\First Last\..."). Its line number stays readable, and the
-- rest of the line stays for the next round: it may hold a second path. A replaced path holds
-- no root, so the rounds end; a loop, not a recursion, so hundreds of paths overflow nothing.
-- The lower-case "users" and "account" need a second separator in the word: "users/players" in
-- a sentence is no folder. The first two roots can leave any folder, so they count everywhere;
-- the others do not inside an addon's own path, where "media/" or "opt/" are its folders.
local HOME_ROOTS = { "%f[%a]%a:[\\/]", "\\\\", "/Users/", "/home/", "/Volumes/", "/Applications/",
    "/run/media/", "/media/", "/mnt/", "/opt/", "~/", "/users/", "%f[%w]Users[\\/]",
    "%f[%w]users[\\/][^\\/%s]+[\\/]", "%f[%w][Aa]ccount[\\/][^\\/%s]+[\\/]" }
local ROOTS_EVERYWHERE = 2
local function Path(p)
    local from = 1
    while true do
        local s, e = p:find(":%d+", from)
        if not s then return "<path>" end
        -- a line number, not a port: "\\srv:445\share"
        if not p:sub(e + 1, e + 1):find("[\\/]") then return "<path>" .. p:sub(s) end
        from = e + 1
    end
end

-- Where each addon path of the text runs: to a space, bracket, quote or ".."
local function AddonRuns(text)
    local runs, from = {}, 1
    while true do
        local s, e = text:find("Interface/AddOns/", from, true)
        if not s then return runs end
        local stop = text:find("[%]%s\"']", e + 1) or #text + 1
        local dots = text:find("..", e + 1, true)
        if dots and dots < stop then stop = dots end
        runs[#runs + 1] = { s, stop }
        from = stop
    end
end

-- A path runs to a bracket, the line's end or a quote that ends it: an apostrophe with a letter,
-- digit or separator after it is part of a name ("O'Brien")
local function PathEnd(text, i)
    while i <= #text do
        local stop = text:find("[%[%]\n\"']", i)
        if not stop then return #text + 1 end
        local c = text:sub(stop, stop)
        if (c ~= '"' and c ~= "'") or not text:sub(stop + 1, stop + 1):find("[%w\\/]") then return stop end
        i = stop + 1
    end
    return i
end

-- Every path from this root replaced by replace(path); runs, if given, are left alone
local function ReplaceRoot(text, root, replace, runs)
    local out, pos, from, r = {}, 1, 1, 1
    while true do
        local s, e = text:find(root, from)
        if not s then break end
        while runs and runs[r] and runs[r][2] <= s do r = r + 1 end
        if runs and runs[r] and runs[r][1] < s then
            from = s + 1
        else
            local stop = PathEnd(text, e + 1)
            out[#out + 1] = text:sub(pos, s - 1)
            out[#out + 1] = replace(text:sub(s, stop - 1))
            pos, from = stop, stop
        end
    end
    if pos == 1 then return text end
    out[#out + 1] = text:sub(pos)
    return table.concat(out)
end

-- A display code the game would draw: the report shows and copies text, and in text a code hides
-- what stands beside it. It leaves a marker that ends a word, so taking it out joins no two
-- words into a name that was none. A pair only up to its last closing code: without one, each
-- opening code would scan the rest of the text.
local MARK = "\1"
local function Pairs(text, open, close)
    local last, from = nil, 1
    while true do
        local s, e = text:find(close, from, true)
        if not s then break end
        last, from = e, e + 1
    end
    if not last then return text end
    return text:sub(1, last):gsub(open .. "[^\n]-" .. close, MARK) .. text:sub(last + 1)
end

local function WithoutCodes(text)
    if not text:find("|", 1, true) then return text end
    repeat
        local before = text
        text = text:gsub("|n", " ")
        -- a link's payload may hold a name no filter knows, so only its visible text stays
        text = Pairs(text, "|H", "|h")
        text = text:gsub("|H[^\n]*", MARK):gsub("|h", MARK)
        text = Pairs(text, "|T", "|t")
        text = Pairs(text, "|A", "|a")
        text = Pairs(text, "|K", "|k")
        text = text:gsub("|c%x%x%x%x%x%x%x%x", MARK):gsub("|cn[%w_]+:", MARK):gsub("|r", MARK)
    until text == before
    return text
end

-- An address without a dot in its domain: letters only, no unit token ("x@focus"), and nothing
-- that makes it a file or a version after it ("Ace3@r1234", "foo@Interface/AddOns")
local UNIT_TOKENS = { player = true, target = true, targettarget = true, focus = true, mouseover = true,
    pet = true, none = true, cursor = true, vehicle = true }
local function WithoutDotlessAddress(text)
    return (text:gsub("%f[%w%.%%%+%-_\128-\255][%w%.%%%+%-_\128-\255]+@([%a\128-\255]+)()", function(domain, after)
        if UNIT_TOKENS[domain:lower()] or text:sub(after, after):find("[%w_/\\\1]") then return nil end
        return "<email>"
    end))
end

-- A name written with combining marks reaches the name filter without them, so it is also looked
-- for without its accents - but only then: on any other text "B\195\161r" would take "Bar.lua".
local BASE_LETTERS = { A = "\128\129\130\131\132\133", C = "\135", E = "\136\137\138\139", I = "\140\141\142\143",
    N = "\145", O = "\146\147\148\149\150", U = "\153\154\155\156", Y = "\157",
    a = "\160\161\162\163\164\165", c = "\167", e = "\168\169\170\171", i = "\172\173\174\175",
    n = "\177", o = "\178\179\180\181\182", u = "\185\186\187\188", y = "\189\191" }
local BASE = {}
for base, seconds in pairs(BASE_LETTERS) do
    for i = 1, #seconds do BASE["\195" .. seconds:sub(i, i)] = base end
end
local function BaseForm(name) return (name:gsub("\195.", BASE)) end

local function Filter(text, names, marked)
    text = WithoutCodes(Visible(text))
    -- A path ends at Interface/AddOns, whatever drive or folder the game sits in
    text = text:gsub("%a:[\\/][^%[%]\"\n]-[\\/][Ii]nterface[\\/][Aa]dd[Oo]ns[\\/]", "Interface/AddOns/")
    text = text:gsub("Interface[\\/]AddOns[\\/][^%]%s\"']*", function(p) return (p:gsub("\\", "/")) end)
    -- after each change from the first root again, so "/Users/" is never taken for "Users/"
    local i = 1
    while i <= #HOME_ROOTS do
        local runs = i > ROOTS_EVERYWHERE and AddonRuns(text) or nil
        local after = ReplaceRoot(text, HOME_ROOTS[i], Path, runs)
        if after ~= text then text, i = after, 1 else i = i + 1 end
    end
    text = ReplaceRoot(text, "%f[%a][Ww][Tt][Ff][\\/]", function() return "<wtf>" end)
    -- The frontier starts a match only where a run of address characters starts: without it a
    -- long run would be scanned again from every byte
    text = text:gsub("%f[%w%.%%%+%-_\128-\255][%w%.%%%+%-_\128-\255]+@[%w%-\128-\255]+%.[%w%.%-\128-\255]+", "<email>")
    text = WithoutDotlessAddress(text)
    for _, kind in ipairs(GUID_KINDS) do
        text = text:gsub(kind .. "%-%d+%-[%x%-]+", "<guid>")
    end
    -- a frontier as for e-mail: a match starts only where a run starts; %z, because the frontier
    -- sees the start of the text as a zero byte, which the set would otherwise hold
    text = text:gsub("%f[^%z%s#<>\"'=%[%]][^%s#<>\"'=%[%]]+#%d%d%d%d+", "<tag>")
    text = text:gsub("%f[%d]%d+#%d+", "<tag>") -- an account folder, "12345678#1"
    local low = Fold(text)
    for _, name in ipairs(names or {}) do
        text, low = ReplaceName(text, low, name)
        if marked then
            local base = BaseForm(name)
            if base ~= name then text, low = ReplaceName(text, low, base) end
        end
    end
    return (text:gsub(MARK, ""))
end

function ns.Scrub(text, names)
    text = tostring(text or "")
    local marked = text:find("\204[\128-\191]") or text:find("\205[\128-\175]")
    local out = Filter(text, names, marked)
    -- Data a display code split is whole only now: "Tes|rta", "joe@exa|rmple.de"
    if text:find("|", 1, true) then out = Filter(out, names, marked) end
    return out
end

---------------------------------------------------------------------------
-- Locals: BugGrabber's text, one "name=value" per line, strings unescaped (phase 1 research).
-- Each line is rebuilt from its parts; a line that does not parse is dropped.
---------------------------------------------------------------------------
local MAX_LOCALS = 20
local LOCAL_KINDS = { table = true, ["function"] = true, userdata = true, thread = true, unnamed = true }

local function SafeLocalValue(v)
    if v:find('^".*"$') and #v >= 2 then return '"' .. ns.SafeValue(v:sub(2, -2)) .. '"' end
    if v:find("^%-?%d+%.?%d*$") or v == "true" or v == "false" or v == "nil" then return v end
    local kind = v:match("^<(%a+)>")
    if LOCAL_KINDS[kind] then return "<" .. kind .. ">" .. (v:find("{%s*$") and " {" or "") end
    if v:find("{%s*$") then return "<table> {" end -- a frame or table printed by its name
    return nil
end

function ns.SafeLocals(text, names)
    local out = {}
    -- BugGrabber's strings are unescaped, so a line of one could read as a local. A string line
    -- that itself ends in a quote closes it early: that much cannot be told from the text.
    local inString = false
    for line in tostring(text or ""):gmatch("[^\n]+") do
        if #out >= MAX_LOCALS then break end
        local indent, key, value = line:match("^(%s*)([^=]-)%s*=%s*(.-)%s*$")
        if inString then
            inString = not line:find('"%s*$')
        elseif value and value:sub(1, 1) == '"' and (#value < 2 or value:sub(-1) ~= '"') then
            inString = true
        elseif line:find("^%s*}%s*$") then
            out[#out + 1] = line:match("^%s*") .. "}"
        elseif key and key ~= "" then
            local safeKey
            if indent == "" then
                -- a local variable's name, from the addon's source
                if key:find("^[%a_][%w_]*$") then safeKey = ns.Scrub(key, names) end
            elseif key:find("^%[?%d+%]?$") or ns.IsSafe(key) then
                safeKey = key
            else
                safeKey = "<key>"
            end
            local safeValue = SafeLocalValue(value)
            if safeKey and safeValue then out[#out + 1] = indent .. safeKey .. "=" .. safeValue end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Size: at most D.REPORT_MAX_BYTES, cut at the start of a character, the cut marked
---------------------------------------------------------------------------
function ns.CapReport(text)
    if #text <= D.REPORT_MAX_BYTES then return text end
    local limit = D.REPORT_MAX_BYTES - #D.REPORT_CUT - 1
    while limit > 0 do
        local b = text:byte(limit + 1)
        if not b or b < 0x80 or b >= 0xC0 then break end -- the next byte starts a character
        limit = limit - 1
    end
    return text:sub(1, limit) .. "\n" .. D.REPORT_CUT
end
