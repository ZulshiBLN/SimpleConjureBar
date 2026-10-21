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
-- The unit's aura of that name: its data table, true where only presence is known, or nil
local function FindBuff(unit, name)
    if not name then return nil end
    if GetAuraByName then
        local ok, aura = pcall(GetAuraByName, unit, name, "HELPFUL")
        return ok and aura or nil
    end
    for i = 1, 40 do
        local n = UnitBuff(unit, i)
        if not n then return nil end
        if n == name then return true end
    end
    return nil
end

-- When the aura runs out (GetTime() scale), or nil for one that does not, or whose time cannot
-- be read: aura values may be secret, and arithmetic on a secret errors
local function ExpiresAt(aura)
    if type(aura) ~= "table" then return nil end
    local ok, at = pcall(function()
        local e = aura.expirationTime
        if type(e) == "number" and e > 0 then return e + 0 end
    end)
    return ok and at or nil
end

-- The moment a buff running out at `at` is due again with `minutes` of renew time; a buff that
-- does not run out never is (ruleset plan 2026-10-21-buff-renew)
local function RenewAt(at, minutes)
    return at and at - minutes * 60 or nil
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

-- Whether the unit needs a buff from us: "missing" without Arcane Intellect or Brilliance (any
-- rank, by name) and without another Intellect buff at least as strong as our rank; "expiring"
-- when its Intellect or Brilliance has at most the renew time left - unless it is stronger
-- than our rank, which the client would refuse to overwrite. nil otherwise, then also the
-- moment it falls due (nil when it never does).
local function NeedsIntellect(unit, aiName, abName)
    local level = UnitLevel(unit)
    local ours = IntellectSpell(level and level > 0 and level or nil)
    local oursValue = ours and D.INTELLECT_BUFFS[ours] or 0
    local found, latest = false, nil
    for _, name in ipairs({ aiName, abName }) do
        local aura = FindBuff(unit, name)
        if aura then
            local ok, value = pcall(rawget, D.INTELLECT_BUFFS, type(aura) == "table" and aura.spellId or nil)
            local at = ExpiresAt(aura)
            if (ok and value and value > oursValue) or not at then return nil end
            found, latest = true, math.max(latest or at, at)
        end
    end
    if found then
        local due = RenewAt(latest, db.intellectRenewMinutes)
        if due <= GetTime() then return "expiring" end
        return nil, due
    end
    if StrongestIntellectBuff(unit) < oursValue then return "missing" end
    return nil
end

---------------------------------------------------------------------------
-- Group scan
---------------------------------------------------------------------------
-- Reused between scans (no allocations per scan)
local missingBySub, expiringBySub, firstInRangeBySub = {}, {}, {}
local missingInRangeBySub, expiringInRangeBySub = {}, {}
local pick = {} -- single-target candidates: missing/expiring, in range/out of range

-- Returns: the number of mana users in need - missing or expiring (range ignored, offline/dead
-- excluded) -, the best single target, the best Brilliance target, each nil when nobody needs
-- it, and the earliest moment a buff falls due (nil if none will).
--   Single:     missing in range, missing out of range, expiring in range, expiring out of range
--   Brilliance: in a raid the subgroup in need with a member in range - most missing, then most
--               expiring, then the lowest number; in a party yourself (it covers your party)
local function ScanGroup(probe)
    local aiName = ns.SpellName(D.SPELL_ARCANE_INTELLECT)
    local abName = ns.SpellName(D.SPELL_ARCANE_BRILLIANCE)
    local inRaid = IsInRaid()
    local grouped = IsInGroup()
    local count
    if inRaid then count = GetNumGroupMembers() else count = grouped and GetNumSubgroupMembers() + 1 or 1 end

    wipe(missingBySub); wipe(expiringBySub); wipe(firstInRangeBySub)
    wipe(missingInRangeBySub); wipe(expiringInRangeBySub); wipe(pick)
    local needing, nextDue = 0, nil
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
            local inRange = not grouped or (probe and InSpellRange(probe, unit))
            local _, classFile = UnitClass(unit)
            if MANA_CLASSES[classFile] then
                local need, due = NeedsIntellect(unit, aiName, abName)
                if need then
                    needing = needing + 1
                    local bySub, inRangeBySub = missingBySub, missingInRangeBySub
                    if need == "expiring" then bySub, inRangeBySub = expiringBySub, expiringInRangeBySub end
                    bySub[sub] = (bySub[sub] or 0) + 1
                    local slot = need .. (inRange and "In" or "Far")
                    pick[slot] = pick[slot] or unit
                    if inRange then inRangeBySub[sub] = inRangeBySub[sub] or unit end
                elseif due and (not nextDue or due < nextDue) then
                    nextDue = due
                end
            end
            if inRange then firstInRangeBySub[sub] = firstInRangeBySub[sub] or unit end
        end
    end

    local single = pick.missingIn or pick.missingFar or pick.expiringIn or pick.expiringFar
    if not grouped or not inRaid then
        -- Solo and in a party both buffs go on yourself or reach you: only your own need counts
        -- solo, anyone's in a party
        local group = (needing > 0) and "player" or nil
        return needing, grouped and single or group, group, nextDue
    end
    local bestSub, bestMissing, bestExpiring
    for sub, unit in pairs(firstInRangeBySub) do
        local m, e = missingBySub[sub] or 0, expiringBySub[sub] or 0
        if unit and m + e > 0 and (not bestSub or m > bestMissing
            or (m == bestMissing and (e > bestExpiring or (e == bestExpiring and sub < bestSub)))) then
            bestSub, bestMissing, bestExpiring = sub, m, e
        end
    end
    local group = bestSub and (missingInRangeBySub[bestSub] or expiringInRangeBySub[bestSub]
        or firstInRangeBySub[bestSub]) or nil
    return needing, single, group, nextDue
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
-- A click whose unit is nil has nothing to do: it gets no action type, so it casts nothing, and
-- its line says everyone has the buff (ruleset plan 2026-10-21-buff-renew).
local function ClickText(spell, unit)
    if not unit then return (ns.SpellName(spell) or "?") .. " > " .. L.EVERYONE_BUFFED end
    return TargetText(spell, unit)
end

local function ApplyTargets(b, singleUnit, groupUnit)
    -- Rank fitting the chosen player's level; without a target the highest, for the icon
    local level = singleUnit and singleUnit ~= "player" and UnitLevel(singleUnit) or nil
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
    -- Not "a and b or c": a nil groupUnit (nobody in need in reach) must stay nil
    local leftUnit, rightUnit = singleUnit, singleUnit
    if left == group then leftUnit = groupUnit end
    if right == group and right ~= single then rightUnit = groupUnit end

    if b.leftSpell ~= left then b.icon:SetTexture(GetSpellTex(left)) end
    b.leftSpell, b.rightSpell, b.spellId = left, right, left
    b.leftItem = nil
    b.hintLeft = L.HINT_LEFT:format(ClickText(left, leftUnit))
    b.hint = L.HINT_RIGHT:format(ClickText(right, rightUnit))

    if IsDemo() then
        SetAttr(b, "type1", nil)
        SetAttr(b, "type2", nil)
    else
        -- Always cast on a fixed unit, so the current target is never buffed
        SetAttr(b, "type1", leftUnit and "spell" or nil)
        SetAttr(b, "spell1", left)
        SetAttr(b, "unit1", leftUnit)
        SetAttr(b, "type2", rightUnit and "spell" or nil)
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

-- Armor: highlight while none of the mage armors is active, or the active one has at most its
-- renew time left. Returns the moment it falls due, if it will.
local function UpdateArmorHighlight()
    if not armor:IsShown() then return end
    local needed, due = true, nil
    if not IsDemo() then
        for _, id in ipairs(D.ARMOR_BUFF_IDS) do
            local aura = FindBuff("player", ns.SpellName(id))
            if aura then
                due = RenewAt(ExpiresAt(aura), db.armorRenewMinutes)
                needed = due ~= nil and due <= GetTime()
                break
            end
        end
    end
    ns.SetAnts(armor, needed)
    if not needed then return due end
end

---------------------------------------------------------------------------
-- Buff & Run (ruleset plan 2026-10-21-buff-and-run): the middle click casts Arcane Intellect
-- on the current target, then targets the next friendly player - one macro, as the client lets
-- an addon pick neither spell nor target during a click. The cast goes through a hidden button
-- holding the rank's ID, chosen in the PreClick; "LeftButton 1" clicks it on key down, which
-- works with ActionButtonUseKeyDown on and off (SmartBlessingBar). In combat the Intellect
-- button's snippet drops every click (Bar.lua), this one too.
---------------------------------------------------------------------------
local buffRun = CreateFrame("Button", "SimpleConjureBarBuffRun", UIParent, "SecureActionButtonTemplate")
buffRun:RegisterForClicks("AnyUp", "AnyDown")
local BUFF_RUN_MACRO = "/click SimpleConjureBarBuffRun LeftButton 1\n/targetfriendplayer"

-- The Arcane Intellect rank for the unit - never Brilliance: nil unless it is a friendly
-- player of a mana class, alive, online, in range, still in need, and not flagged for PvP
-- unless allowed (buffing him would flag the mage too). Nothing while auras are secret: a
-- buff could not be seen, and every target would look in need.
function ns.BuffRunSpell(unit)
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then return end
    if not (UnitExists(unit) and UnitIsPlayer(unit) and UnitCanAssist("player", unit)) then return end
    if not UnitIsConnected(unit) or UnitIsDeadOrGhost(unit) then return end
    if not MANA_CLASSES[select(2, UnitClass(unit))] then return end
    if not db.pvpBuff and UnitIsPVP(unit) then return end
    local level = UnitLevel(unit)
    if level and level <= 0 then level = nil end -- "??": unknown, not rank 1
    local spell = IntellectSpell(level)
    if not spell then return end
    if not NeedsIntellect(unit, ns.SpellName(D.SPELL_ARCANE_INTELLECT), ns.SpellName(D.SPELL_ARCANE_BRILLIANCE)) then return end
    if not InSpellRange(spell, unit) then return end
    return spell
end

-- The middle click's attributes as every out-of-combat update leaves them, whether the button
-- is shown or not - its key works with the button hidden (Michel). Never at load: after a
-- /reload in combat the files load in the lockdown.
local function ArmBuffRun()
    local on = db.buffRun
    intel.hintMiddleKey = on and "HINT_BUFF_RUN" or nil
    SetAttr(intel, "type3", on and "macro" or nil)
    SetAttr(intel, "macrotext3", on and BUFF_RUN_MACRO or nil)
    SetAttr(buffRun, "type", "spell")
    SetAttr(buffRun, "unit", "target")
    SetAttr(buffRun, "spell", nil)
end
ns.ArmBuffRun = ArmBuffRun

-- Just before a middle click, out of combat: the rank for the current target. While the chosen
-- spell is on cooldown the click does nothing at all, so no player is passed by. Demo mode
-- casts nothing, targets on, and says on the press what it would cast.
intel:SetScript("PreClick", function(_, button, down)
    if button ~= "MiddleButton" or InCombatLockdown() or not db or not db.buffRun then return end
    SetAttr(buffRun, "spell", nil)
    local spell = ns.BuffRunSpell("target")
    if spell and C_Spell.GetSpellCooldown(spell).startTime > 0 then
        SetAttr(intel, "type3", nil)
        return
    end
    SetAttr(intel, "type3", "macro")
    if IsDemo() then
        if spell and down then ns.DemoPrint(L.DEMO_CAST, ns.SpellName(spell) or "?") end
        return
    end
    SetAttr(buffRun, "spell", spell)
end)

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

-- No event fires when a buff crosses its renew time: one timer waits for the earliest crossing
-- and runs the update then. It is replaced only when that moment moves, so the group ticker's
-- updates every second do not pile timers up.
local renewTimer, renewAt
local function ScheduleRenew(at)
    if at == renewAt then return end
    if renewTimer then renewTimer:Cancel() end
    renewTimer, renewAt = nil, at
    if at then
        renewTimer = C_Timer.NewTimer(at - GetTime(), function()
            renewTimer, renewAt = nil, nil
            ns.UpdateBuffState()
        end)
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
    local due = UpdateArmorHighlight()
    if intel:IsShown() then
        if IsDemo() then
            ShowBuffCount(IsInGroup() and 3 or 1)
            ApplyTargets(intel, "player", "player")
        else
            local probe = IntellectSpell()
            local missing, singleUnit, groupUnit, intellectDue = ScanGroup(probe)
            ShowBuffCount(missing)
            ApplyTargets(intel, singleUnit, groupUnit)
            if intellectDue and (not due or intellectDue < due) then due = intellectDue end
        end
    end
    ScheduleRenew(due)
    UpdateTicker()
    ArmBuffRun()
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
