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
local HOME_ROOTS = { "%f[%a]%a:[\\/]", "\\\\", "/Users/", "/home/", "/Volumes/", "/Applications/",
    "/run/media/", "/media/", "%f[%w]Users[\\/]" }
local function Path(p)
    local s = p:find(":%d+")
    if not s then return "<path>" end
    return "<path>" .. p:sub(s)
end

function ns.Scrub(text, names)
    text = Visible(tostring(text or ""))
    -- A path ends at Interface/AddOns, whatever drive or folder the game sits in
    text = text:gsub("%a:[\\/][^%[%]\"'\n]-[\\/][Ii]nterface[\\/][Aa]dd[Oo]ns[\\/]", "Interface/AddOns/")
    text = text:gsub("Interface[\\/]AddOns[\\/][^%]%s\"']*", function(p) return (p:gsub("\\", "/")) end)
    -- after each change from the first root again, so "/Users/" is never taken for "Users/"
    local i = 1
    while i <= #HOME_ROOTS do
        local after = text:gsub(HOME_ROOTS[i] .. "[^%[%]\"'\n]*", Path)
        if after ~= text then text, i = after, 1 else i = i + 1 end
    end
    text = text:gsub("%f[%a][Ww][Tt][Ff][\\/][^%[%]\"'\n]*", "<wtf>")
    -- The frontier starts a match only where a run of address characters starts: without it a
    -- long run would be scanned again from every byte
    text = text:gsub("%f[%w%.%%%+%-_\128-\255][%w%.%%%+%-_\128-\255]+@[%w%-]+%.[%w%.%-]+", "<email>")
    for _, kind in ipairs(GUID_KINDS) do
        text = text:gsub(kind .. "%-%d+%-[%x%-]+", "<guid>")
    end
    -- a frontier as for e-mail: a match starts only where a run starts
    text = text:gsub("%f[^%s#<>\"'=%[%]][^%s#<>\"'=%[%]]+#%d%d%d%d+", "<tag>")
    text = text:gsub("%f[%d]%d+#%d+", "<tag>") -- an account folder, "12345678#1"
    local low = Fold(text)
    for _, name in ipairs(names or {}) do text, low = ReplaceName(text, low, name) end
    return text
end

---------------------------------------------------------------------------
-- Locals: BugGrabber's text, one "name=value" per line, strings unescaped (phase 1 research).
-- Each line is rebuilt from its parts; a line that does not parse is dropped.
---------------------------------------------------------------------------
local MAX_LOCALS = 20

local function SafeLocalValue(v)
    if v:find('^".*"$') and #v >= 2 then return '"' .. ns.SafeValue(v:sub(2, -2)) .. '"' end
    if v:find("^%-?%d+%.?%d*$") or v == "true" or v == "false" or v == "nil" then return v end
    local kind = v:match("^<(%a+)>")
    if kind then return "<" .. kind .. ">" .. (v:find("{%s*$") and " {" or "") end
    if v:find("{%s*$") then return "<table> {" end -- a frame or table printed by its name
    return nil
end

function ns.SafeLocals(text, names)
    local out = {}
    for line in tostring(text or ""):gmatch("[^\n]+") do
        if #out >= MAX_LOCALS then break end
        local indent, key, value = line:match("^(%s*)([^=]-)%s*=%s*(.-)%s*$")
        if line:find("^%s*}%s*$") then
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
