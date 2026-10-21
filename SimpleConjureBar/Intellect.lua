-- SimpleConjureBar - Arcane Intellect tracking and targeting, armor highlight
-- One group scan delivers both the number of missing buffs and the best buff targets.
-- Solo the buffs always go on yourself; in a group the addon picks group members itself,
-- so the current target is never buffed by accident. Intellect is locked in combat.

local _, ns = ...
if not ns.enabled then return end

local D, L, API = ns.D, ns.L, ns.API
local ItemCount, GetSpellTex = API.ItemCount, API.GetSpellTex
local IsDemo, IsKnown, SetAttr = ns.IsDemo, ns.IsKnown, ns.SetAttr
local MANA_CLASSES = D.MANA_CLASSES
local UnitExists, UnitIsConnected, UnitIsDeadOrGhost, UnitClass = UnitExists, UnitIsConnected, UnitIsDeadOrGhost, UnitClass
local InCombatLockdown, IsInGroup, IsInRaid = InCombatLockdown, IsInGroup, IsInRaid

local intel, armor = ns.buttons.Intellect, ns.buttons.Armor

local db
ns.OnDBReady(function(d) db = d end)

-- Unit tokens are built once instead of concatenating strings on every scan
local RAID_UNITS, PARTY_UNITS = {}, {}
for i = 1, 40 do RAID_UNITS[i] = "raid" .. i end
for i = 1, 4 do PARTY_UNITS[i] = "party" .. i end

---------------------------------------------------------------------------
-- Buff checks (by name, so every rank of Intellect and Brilliance counts)
---------------------------------------------------------------------------
local GetAuraByName = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
local function HasBuff(unit, name)
    if not name then return false end
    if GetAuraByName then
        local ok, aura = pcall(GetAuraByName, unit, name, "HELPFUL")
        return ok and aura ~= nil
    end
    for i = 1, 40 do
        local n = UnitBuff(unit, i)
        if not n then return false end
        if n == name then return true end
    end
    return false
end

-- Intellect value of the strongest known Intellect buff on the unit, found by spell ID.
-- Covers buffs from other sources (higher ranks of other mages, scrolls) and names that differ
-- from the spell name of our own rank.
local GetAuraByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
local function StrongestIntellectBuff(unit)
    local best = 0
    for i = 1, 40 do
        local spellId
        if GetAuraByIndex then
            local ok, aura = pcall(GetAuraByIndex, unit, i, "HELPFUL")
            if not ok or not aura then break end
            spellId = aura.spellId
        else
            local name, _, _, _, _, _, _, _, _, id = UnitBuff(unit, i)
            if not name then break end
            spellId = id
        end
        -- pcall: in restricted contexts the ID may be a protected value that cannot be used as a key
        local ok, value = pcall(rawget, D.INTELLECT_BUFFS, spellId)
        if ok and value and value > best then best = value end
    end
    return best
end

-- Highest Intellect rank a player of this level accepts (no level: highest known rank)
local function IntellectSpell(level)
    local best
    for _, r in ipairs(D.INTELLECT_RANKS) do
        if IsKnown(r.id) then
            best = best or r.id
            if not level or r.level - 10 <= level then return r.id end
        end
    end
    return best
end

local function InSpellRange(spell, unit)
    if UnitIsUnit(unit, "player") then return true end
    if not UnitIsVisible(unit) then return false end
    local r
    if C_Spell and C_Spell.IsSpellInRange then
        r = C_Spell.IsSpellInRange(spell, unit)
    elseif IsSpellInRange then
        local v = IsSpellInRange(ns.SpellName(spell), unit)
        if v == 1 then r = true elseif v == 0 then r = false end
    end
    if r == nil then r = UnitInRange(unit) end
    return r and true or false
end

-- True when the unit can still get a buff from us: it has neither Arcane Intellect nor Arcane
-- Brilliance (any rank, by name) nor another Intellect buff at least as strong as our rank.
local function NeedsIntellect(unit, aiName, abName)
    if HasBuff(unit, aiName) or HasBuff(unit, abName) then return false end
    local level = UnitLevel(unit)
    local ours = IntellectSpell(level and level > 0 and level or nil)
    local oursValue = ours and D.INTELLECT_BUFFS[ours] or 0
    return StrongestIntellectBuff(unit) < oursValue
end

---------------------------------------------------------------------------
-- Group scan
---------------------------------------------------------------------------
-- Reused between scans (no allocations per scan)
local missingBySub, firstInRangeBySub, missingInRangeBySub = {}, {}, {}

-- Returns: number of mana users without the buff (range ignored, offline/dead excluded),
-- the best single target and the best Brilliance target.
--   Single:     next mana user without the buff, members in range first
--   Brilliance: in a raid the subgroup with the most missing buffs that has a member in range,
--               in a party yourself (Brilliance covers the target's party)
local function ScanGroup(probe)
    local aiName = ns.SpellName(D.SPELL_ARCANE_INTELLECT)
    local abName = ns.SpellName(D.SPELL_ARCANE_BRILLIANCE)
    local inRaid = IsInRaid()
    local grouped = IsInGroup()
    local count
    if inRaid then count = GetNumGroupMembers() else count = grouped and GetNumSubgroupMembers() + 1 or 1 end

    wipe(missingBySub); wipe(firstInRangeBySub); wipe(missingInRangeBySub)
    local missing, single, singleFar = 0, nil, nil
    for i = 1, count do
        local unit, sub
        if inRaid then
            unit = RAID_UNITS[i]
            sub = select(3, GetRaidRosterInfo(i)) or 1
        else
            unit = (i == 1) and "player" or PARTY_UNITS[i - 1]
            sub = 1
        end
        if UnitExists(unit) and UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) then
            local inRange = grouped and probe and InSpellRange(probe, unit)
            local _, classFile = UnitClass(unit)
            if MANA_CLASSES[classFile] and NeedsIntellect(unit, aiName, abName) then
                missing = missing + 1
                missingBySub[sub] = (missingBySub[sub] or 0) + 1
                if inRange then
                    single = single or unit
                    missingInRangeBySub[sub] = missingInRangeBySub[sub] or unit
                else
                    singleFar = singleFar or unit
                end
            end
            if inRange then firstInRangeBySub[sub] = firstInRangeBySub[sub] or unit end
        end
    end

    if not grouped then return missing, "player", "player" end
    single = single or singleFar or "player"
    local group = "player"
    if inRaid then
        local bestSub, bestCount = nil, 0
        for sub, n in pairs(missingBySub) do
            if n > bestCount and firstInRangeBySub[sub] then bestSub, bestCount = sub, n end
        end
        if bestSub then group = missingInRangeBySub[bestSub] or firstInRangeBySub[bestSub] end
    end
    return missing, single, group
end

---------------------------------------------------------------------------
-- Button setup
---------------------------------------------------------------------------
local function UnitShortName(unit)
    return (UnitName(unit)) or unit
end

-- Whom a click's spell reaches, for its tooltip line: Brilliance covers the target's group -
-- in a raid its subgroup, by number - a single buff the member. Solo there is nobody to name.
local function TargetText(spell, unit)
    if not IsInGroup() then return ns.SpellName(spell) or "?" end
    local whom
    if spell == D.SPELL_ARCANE_BRILLIANCE then
        whom = L.TARGET_GROUP
        if IsInRaid() then
            local index = tonumber(unit:match("^raid(%d+)$"))
            if not index then
                for i = 1, GetNumGroupMembers() do
                    if UnitIsUnit(RAID_UNITS[i], unit) then index = i break end
                end
            end
            local sub = index and select(3, GetRaidRosterInfo(index))
            if sub then whom = L.TARGET_SUBGROUP:format(sub) end
        end
    else
        whom = UnitShortName(unit)
    end
    return (ns.SpellName(spell) or "?") .. " > " .. whom
end

-- Sets spells, fixed target units and the tooltip hint (out of combat only)
local function ApplyTargets(b, singleUnit, groupUnit)
    -- Rank fitting the chosen player's level
    local level = (singleUnit ~= "player") and UnitLevel(singleUnit) or nil
    if level and level <= 0 then level = nil end
    local single = IntellectSpell(level)

    -- Group buff only when learned and Arcane Powder is in the bags
    local group
    if IsKnown(D.SPELL_ARCANE_BRILLIANCE) and (IsDemo() or (ItemCount(D.ITEM_ARCANE_POWDER) or 0) > 0) then
        group = D.SPELL_ARCANE_BRILLIANCE
    end

    -- Left = default (solo: single, group: Brilliance), right = the other one
    local grouped = IsInGroup()
    local left, right
    if grouped then
        left, right = group or single, single
    else
        left, right = single, group or single
    end
    local leftUnit = (left == group) and groupUnit or singleUnit
    local rightUnit = (right == group and right ~= single) and groupUnit or singleUnit

    if b.leftSpell ~= left then b.icon:SetTexture(GetSpellTex(left)) end
    b.leftSpell, b.rightSpell, b.spellId = left, right, left
    b.leftItem = nil
    b.hintLeft = L.HINT_LEFT:format(TargetText(left, leftUnit))
    b.hint = L.HINT_RIGHT:format(TargetText(right, rightUnit))

    if IsDemo() then
        SetAttr(b, "type1", nil)
        SetAttr(b, "type2", nil)
    else
        -- Always cast on a fixed unit, so the current target is never buffed
        SetAttr(b, "type1", "spell")
        SetAttr(b, "spell1", left)
        SetAttr(b, "unit1", leftUnit)
        SetAttr(b, "type2", "spell")
        SetAttr(b, "spell2", right)
        SetAttr(b, "unit2", rightUnit)
    end
end

-- Called by Rebuild; spells and targets follow right after in UpdateBuffState
function ns.SetupIntellect(b)
    if not IntellectSpell() then b:Hide() return false end
    b:Show()
    return true
end

local function ShowBuffCount(count)
    intel.count:SetText(count > 0 and count or "") -- only shown when greater than 0
    ns.SetAnts(intel, count > 0)
    intel.hint2 = count > 0 and L.BUFF_MISSING:format(ns.LocalName(ns.SpellName(D.SPELL_ARCANE_INTELLECT), "BTN_INTELLECT"), count) or nil
end

-- Armor: highlight while none of the mage armors is active
local function UpdateArmorHighlight()
    if not armor:IsShown() then return end
    local missing = true
    if not IsDemo() then
        for _, id in ipairs(D.ARMOR_BUFF_IDS) do
            if HasBuff("player", ns.SpellName(id)) then missing = false break end
        end
    end
    ns.SetAnts(armor, missing)
end

---------------------------------------------------------------------------
-- Update cycle
---------------------------------------------------------------------------
local groupDirty = false -- auras changed during combat; re-check afterwards
local inCombat = false   -- PLAYER_REGEN_DISABLED fires before InCombatLockdown() turns true
local ticker

-- Range changes fire no event: in a group the targets are re-chosen every second.
-- The ticker only runs while it is needed (in a group, out of combat, button shown).
local function UpdateTicker()
    local wanted = db and intel:IsShown() and IsInGroup() and not (inCombat or InCombatLockdown())
        and not IsDemo()
    if wanted and not ticker then
        ticker = C_Timer.NewTicker(1, ns.UpdateBuffState)
    elseif not wanted and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

-- Count, targets and armor highlight. In combat everything stays frozen at the state of combat
-- start: the client restricts aura data in combat (every buff would look missing), and
-- Intellect cannot be cast then anyway. Everything is re-checked once combat ends.
function ns.UpdateBuffState()
    if not db then return end
    if inCombat or InCombatLockdown() then
        groupDirty = true
        UpdateTicker()
        return
    end
    UpdateArmorHighlight()
    if intel:IsShown() then
        if IsDemo() then
            ShowBuffCount(IsInGroup() and 3 or 1)
            ApplyTargets(intel, "player", "player")
        else
            local probe = IntellectSpell()
            local missing, singleUnit, groupUnit = ScanGroup(probe)
            ShowBuffCount(missing)
            ApplyTargets(intel, singleUnit, groupUnit)
        end
    end
    UpdateTicker()
    -- A new Intellect target changes no glow, but the buff key casts on it (Buttons.lua)
    ns.UpdateBuffKey()
end
local UpdateBuffState = ns.UpdateBuffState

-- Aura changes often arrive in bursts: collect them briefly, then update once
local queued = false
local function RunQueued()
    queued = false
    UpdateBuffState()
end
local function QueueUpdate()
    if queued then return end
    queued = true
    C_Timer.After(0.3, RunQueued)
end

local function IsGroupUnit(unit)
    return unit:match("^party%d$") or unit:match("^raid%d+$")
end

local events = CreateFrame("Frame")
events:RegisterEvent("UNIT_AURA")
events:RegisterEvent("UNIT_CONNECTION")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_DEAD")
events:RegisterEvent("PLAYER_ALIVE")
events:RegisterEvent("PLAYER_UNGHOST")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, unit)
    if not db then return end
    if event == "UNIT_AURA" then
        if unit == "player" then
            QueueUpdate()
        elseif unit and IsGroupUnit(unit) then -- pets, nameplates and others are ignored
            if InCombatLockdown() then groupDirty = true else QueueUpdate() end
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        UpdateTicker()
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        if groupDirty then
            groupDirty = false
            QueueUpdate()
        end
        UpdateTicker()
    else
        QueueUpdate()
    end
end)
