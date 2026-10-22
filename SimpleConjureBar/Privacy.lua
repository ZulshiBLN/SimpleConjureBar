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
local function Secret(v) return issecretvalue and issecretvalue(v) end

function ns.KnownNames()
    local names, secret = {}, false
    local function Add(v)
        if v == nil then return end
        if Secret(v) then secret = true return end
        if type(v) == "string" and #v >= 2 then names[#names + 1] = v end
    end
    local units = { "player", "pet", "target", "targettarget", "focus", "mouseover", "NPC" }
    for i = 1, 4 do units[#units + 1] = "party" .. i; units[#units + 1] = "partypet" .. i end
    for i = 1, 40 do units[#units + 1] = "raid" .. i; units[#units + 1] = "raidpet" .. i end
    for _, u in ipairs(units) do
        local name, realm = UnitName(u)
        Add(name); Add(realm)
        if name and realm and not Secret(name) and not Secret(realm) and realm ~= "" then
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
-- Letters, digits, "_" and every byte of a non-ASCII character count as part of a word
local function IsWord(b)
    return b ~= nil and (b >= 128 or b == 95 or (b >= 48 and b <= 57) or (b >= 65 and b <= 90)
        or (b >= 97 and b <= 122))
end

-- Non-ASCII bytes count as letters, but these characters part words: the no-break space and
-- the typographic quotes (a phone or Mac keyboard types a curly apostrophe after a name)
local BOUNDARIES = { "\194\160", "\226\128\152", "\226\128\153", "\226\128\156", "\226\128\157" }

-- Whether a word ends at position i (before = true) or starts there
local function Edge(text, i, before)
    if not IsWord(text:byte(i)) then return true end
    for _, b in ipairs(BOUNDARIES) do
        local part = before and text:sub(i - #b + 1, i) or text:sub(i, i + #b - 1)
        if part == b then return true end
    end
    return false
end

-- Whole words only, ASCII letters in any case, found as plain text (realm names hold "-", "'")
local function ReplaceName(text, name)
    local lowText, lowName = text:lower(), name:lower()
    local out, pos, from = {}, 1, 1
    while true do
        local s, e = lowText:find(lowName, from, true)
        if not s then break end
        if Edge(lowText, s - 1, true) and Edge(lowText, e + 1, false) then
            out[#out + 1] = text:sub(pos, s - 1)
            out[#out + 1] = "<name>"
            pos = e + 1
        end
        from = e + 1
    end
    out[#out + 1] = text:sub(pos)
    return table.concat(out)
end

local GUID_KINDS = { "Player", "Pet", "Creature", "Vehicle", "GameObject", "Item" }

-- Characters that show nothing: zero-width ones, direction marks, the word joiner, the byte
-- order mark, the soft hyphen, tag characters. Inside or beside a name they hide it.
local INVISIBLE = { "\226\128[\139-\143]", "\226\128[\170-\174]", "\226\129[\160-\164]",
    "\226\129[\166-\169]", "\239\187\191", "\194\173", "\243\160[\128-\129][\128-\191]" }

-- Folders that hold a user's name: a path from one of them runs to a quote, bracket or line
-- end, spaces included ("C:\Users\First Last\..."); its line number stays readable
local HOME_ROOTS = { "%f[%a]%a:[\\/]", "\\\\", "/Users/", "/home/", "/Volumes/", "/Applications/" }
local function Path(p) return "<path>" .. (p:match("(:%d+:?.*)$") or "") end

function ns.Scrub(text, names)
    text = tostring(text or "")
    for _, p in ipairs(INVISIBLE) do text = text:gsub(p, "") end
    -- A path ends at Interface/AddOns, whatever drive or folder the game sits in
    text = text:gsub("%a:[\\/][^%[%]\"'\n]-[\\/][Ii]nterface[\\/][Aa]dd[Oo]ns[\\/]", "Interface/AddOns/")
    text = text:gsub("Interface[\\/]AddOns[\\/][^%]%s\"']*", function(p) return (p:gsub("\\", "/")) end)
    for _, root in ipairs(HOME_ROOTS) do text = text:gsub(root .. "[^%[%]\"'\n]*", Path) end
    text = text:gsub("%f[%a][Ww][Tt][Ff][\\/][^%[%]\"'\n]*", "<wtf>")
    text = text:gsub("[%w%.%%%+%-_]+@[%w%-]+%.[%w%.%-]+", "<email>")
    for _, kind in ipairs(GUID_KINDS) do
        text = text:gsub(kind .. "%-%d+%-[%x%-]+", "<guid>")
    end
    text = text:gsub("[^%s#<>\"'=%[%]]+#%d%d%d%d+", "<tag>")
    text = text:gsub("%d+#%d+", "<tag>") -- an account folder, "12345678#1"
    for _, name in ipairs(names or {}) do text = ReplaceName(text, name) end
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
