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
local function ReadExpiry(aura)
    local e = aura.expirationTime
    if type(e) == "number" and e > 0 then return e + 0 end
end
local function ExpiresAt(aura)
    if type(aura) ~= "table" then return nil end
    local ok, at = pcall(ReadExpiry, aura) -- no closure per aura: this runs every second in a group
    return ok and at or nil
end

-- The moment a buff running out at `at` is due again with `minutes` of renew time; a buff that
-- does not run out never is (ruleset plan 2026-10-21-buff-renew)
local function RenewAt(at, minutes)
    return at and at - minutes * 60 or nil
end

-- Intellect value of the strongest known Intellect buff on the unit, found by spell ID.
-- Covers buffs from other sources (higher ranks of other mages, scrolls) and names that differ
-- from the spell name of our own rank. Stops at one at least as strong as `enough`.
local GetAuraByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
local function StrongestIntellectBuff(unit, enough)
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
        if ok and value and value > best then
            best = value
            if best >= enough then break end
        end
    end
    return best
end

-- The Intellect ranks known, read once per update: a scan asks for every member's rank
-- (code review 1.1.0, F-14)
local knownRanks = {}
local function ReadKnownRanks()
    wipe(knownRanks)
    for _, r in ipairs(D.INTELLECT_RANKS) do
        if IsKnown(r.id) then knownRanks[#knownRanks + 1] = r end
    end
    return knownRanks
end

-- Highest Intellect rank a player of this level accepts (no level: highest known rank).
-- `known`: the ranks just read by ReadKnownRanks, else each is checked here.
local function IntellectSpell(level, known)
    local best
    for _, r in ipairs(known or D.INTELLECT_RANKS) do
        if known or IsKnown(r.id) then
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
    -- no answer counts as out of range: UnitInRange answers true at any distance (in game,
    -- 2026-10-23), so it is no fallback. The client gives no answer either for a rank not
    -- learned, which demo mode counts as known: there it counts as in range, so demo mode names
    -- what it would cast (SmartBlessingBar 022d74d).
    if r == nil and IsDemo() then return true end
    return r == true
end

-- Whether the unit needs a buff from us (ruleset plan 2026-10-23-intellect-range):
--   "missing"  - no Arcane Intellect or Brilliance (any rank, by name, any caster) and no other
--                Intellect buff at least as strong as our rank;
--   "weaker"   - only a known lower rank than ours for its level, with a readable expiry;
--   "expiring" - our strength (or an ID that cannot be read) with at most the renew time left.
-- nil for a stronger buff (the client would refuse ours) or one without a readable expiry, then
-- also the moment it falls due (nil when it never does). With both buffs the stronger decides.
local function NeedsIntellect(unit, aiName, abName, known)
    local level = UnitLevel(unit)
    local ours = IntellectSpell(level and level > 0 and level or nil, known)
    local oursValue = ours and D.INTELLECT_BUFFS[ours] or 0
    local found, latest, weaker = false, nil, false
    for i = 1, 2 do -- Intellect, then Brilliance; no table per unit and scan
        local aura = FindBuff(unit, i == 1 and aiName or abName)
        if aura then
            local ok, value = pcall(rawget, D.INTELLECT_BUFFS, type(aura) == "table" and aura.spellId or nil)
            local at = ExpiresAt(aura)
            if (ok and value and value > oursValue) or not at then return nil end
            if ok and value and value < oursValue then
                weaker = true
            else
                found, latest = true, math.max(latest or at, at)
            end
        end
    end
    if weaker and not found then
        if StrongestIntellectBuff(unit, oursValue) >= oursValue then return nil end
        return "weaker"
    end
    if found then
        local due = RenewAt(latest, db.intellectRenewMinutes)
        if due <= GetTime() then return "expiring" end
        return nil, due
    end
    if StrongestIntellectBuff(unit, oursValue) < oursValue then return "missing" end
    return nil
end

---------------------------------------------------------------------------
-- Group scan
---------------------------------------------------------------------------
-- Reused between scans (no allocations per scan): counts of members in range per subgroup,
-- and the first such member, for the raid's Brilliance
local missingIn, weakerIn, expiringIn = {}, {}, {}
local missingUnit, weakerUnit = {}, {}
local pick = {} -- single-target candidates in range: missing / weaker / expiring

-- Returns (ruleset plan 2026-10-23-intellect-range):
--   needing  - mana users in need: missing, weaker or expiring (offline and dead excluded)
--   needIn   - those of them in range (the player always is)
--   single   - the first in range: missing, then weaker, then expiring
--   group    - the Brilliance target, nil unless it reaches `threshold` (nil: no Brilliance):
--              in a party the player while needIn reaches it; in a raid the subgroup with at
--              least that many missing or weaker in range - most missing, then weaker, then
--              expiring, then the lowest number - on its first missing, else weaker member
--   nextDue  - the earliest moment a buff falls due (nil if none will)
--   selfNeed - the player's own need
local function ScanGroup(probe, known, threshold)
    local aiName = ns.SpellName(D.SPELL_ARCANE_INTELLECT)
    local abName = ns.SpellName(D.SPELL_ARCANE_BRILLIANCE)
    local inRaid = IsInRaid()
    local grouped = IsInGroup()
    local count
    if inRaid then count = GetNumGroupMembers() else count = grouped and GetNumSubgroupMembers() + 1 or 1 end

    wipe(missingIn); wipe(weakerIn); wipe(expiringIn); wipe(missingUnit); wipe(weakerUnit); wipe(pick)
    local needing, needIn, nextDue, selfNeed = 0, 0, nil, nil
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
            local _, classFile = UnitClass(unit)
            if MANA_CLASSES[classFile] then
                local need, due = NeedsIntellect(unit, aiName, abName, known)
                if need then
                    needing = needing + 1
                    if unit == "player" then selfNeed = need end
                    if not grouped or (probe and InSpellRange(probe, unit)) then
                        needIn = needIn + 1
                        pick[need] = pick[need] or unit
                        if need == "missing" then
                            missingIn[sub] = (missingIn[sub] or 0) + 1
                            missingUnit[sub] = missingUnit[sub] or unit
                        elseif need == "weaker" then
                            weakerIn[sub] = (weakerIn[sub] or 0) + 1
                            weakerUnit[sub] = weakerUnit[sub] or unit
                        else
                            expiringIn[sub] = (expiringIn[sub] or 0) + 1
                        end
                    end
                elseif due and (not nextDue or due < nextDue) then
                    nextDue = due
                end
            end
        end
    end

    local single = pick.missing or pick.weaker or pick.expiring
    local group
    if threshold and grouped and not inRaid then
        if needIn >= threshold then group = "player" end
    elseif threshold and inRaid then
        local best, bestM, bestW, bestE
        for sub = 1, 8 do
            local m, w, e = missingIn[sub] or 0, weakerIn[sub] or 0, expiringIn[sub] or 0
            if m + w >= threshold and (not best or m > bestM or (m == bestM and (w > bestW
                or (w == bestW and e > bestE)))) then
                best, bestM, bestW, bestE = sub, m, w, e
            end
        end
        group = best and (missingUnit[best] or weakerUnit[best]) or nil
    end
    return needing, needIn, single, group, nextDue, selfNeed
end

---------------------------------------------------------------------------
-- Button setup
---------------------------------------------------------------------------
-- A secret name cannot be shown: the unit token stands in
local function UnitShortName(unit)
    local name = UnitName(unit)
    if ns.IsSecret(name) then return unit end
    return name or unit
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

-- A click whose unit is nil has nothing to do: it gets no action type, so it casts nothing, and
-- its line says the buff is active - or, while members need it, that they are out of range.
local function ClickText(spell, unit, needing)
    if not unit then
        return (ns.SpellName(spell) or "?") .. " > " .. (needing > 0 and L.NONE_IN_RANGE or L.EVERYONE_BUFFED)
    end
    return TargetText(spell, unit)
end

-- The left click casts the one recommendation (out of combat only): Brilliance on groupUnit when
-- it reached the threshold, else the single buff on singleUnit. The right click casts nothing:
-- in a group it opens the threshold slider (OnClick below), solo it has no line.
local function ApplyTargets(b, singleUnit, groupUnit, needing, known)
    -- Rank fitting the chosen player's level; without a target the highest, for the icon
    local level = singleUnit and singleUnit ~= "player" and UnitLevel(singleUnit) or nil
    if level and level <= 0 then level = nil end
    local left, leftUnit = IntellectSpell(level, known), singleUnit
    if groupUnit then left, leftUnit = D.SPELL_ARCANE_BRILLIANCE, groupUnit end

    if b.leftSpell ~= left then b.icon:SetTexture(GetSpellTex(left)) end
    b.leftSpell, b.rightSpell, b.spellId = left, nil, left
    b.leftItem = nil
    b.hintLeft = L.HINT_LEFT:format(ClickText(left, leftUnit, needing))
    b.hint = nil
    b.hintKey = IsInGroup() and "HINT_THRESHOLD" or nil

    if IsDemo() then
        SetAttr(b, "type1", nil)
    else
        -- Always cast on a fixed unit, so the current target is never buffed
        SetAttr(b, "type1", leftUnit and "spell" or nil)
        SetAttr(b, "spell1", left)
        SetAttr(b, "unit1", leftUnit)
    end
    SetAttr(b, "type2", nil)
end

-- In a group the right click opens the settings on the threshold slider's tab; on the release
-- only, as the button gets down and up. In combat the snippet drops the click (Bar.lua).
intel:HookScript("OnClick", function(_, button, down)
    if button == "RightButton" and not down and IsInGroup() then ns.OpenSettings(nil, "TAB_TRACKING") end
end)

-- Called by Rebuild; spells and targets follow right after in UpdateBuffState
function ns.SetupIntellect(b)
    if not IntellectSpell() then b:Hide() return false end
    b:Show()
    return true
end

-- The count is those in need in range; the line names all in need and those out of range, or
-- solo the player's own need without a number. asGroup: demo mode shows the group lines.
local SELF_LINE = { missing = "SELF_MISSING", weaker = "SELF_WEAKER", expiring = "SELF_EXPIRING" }
local function ShowBuffCount(count, needing, selfNeed, asGroup)
    intel.count:SetText(count > 0 and count or "") -- only shown when greater than 0
    ns.SetAnts(intel, count > 0)
    local name = ns.LocalName(ns.SpellName(D.SPELL_ARCANE_INTELLECT), "BTN_INTELLECT")
    if needing <= 0 then
        intel.hint2 = nil
    elseif not asGroup and not IsInGroup() then
        intel.hint2 = L[SELF_LINE[selfNeed] or "SELF_MISSING"]:format(name)
    elseif needing > count then
        intel.hint2 = L.BUFF_MISSING_FAR:format(name, needing, needing - count)
    else
        intel.hint2 = L.BUFF_MISSING:format(name, needing)
    end
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
ns.LogClicks(buffRun, buffRun:GetName(), true) -- clicked only by the macro's "/click ... 1"
local BUFF_RUN_MACRO = "/click SimpleConjureBarBuffRun LeftButton 1\n/targetfriendplayer"

-- The mage is flagged for good - by /pvp, the portrait menu, a battleground, an arena or a
-- PvP zone - when the flag has no timer; one that runs out came by accident, from buffing a
-- flagged player, say (ruleset plan 2026-10-22-pvp-self-flag)
local function FlaggedForGood()
    return UnitIsPVP("player") and not IsPVPTimerRunning()
end

-- The Arcane Intellect rank for the unit - never Brilliance: nil unless it is a friendly
-- player of a mana class, alive, online, in range and still in need. A player flagged for PvP
-- is passed - buffing him would flag the mage - unless allowed, or the mage is flagged for
-- good and loses nothing. Nothing while auras are secret: a buff could not be seen, and every
-- target would look in need. Without a spell the second value says why, for the bug report's
-- action log.
function ns.BuffRunSpell(unit)
    if not ns.AurasReadable() then return nil, "auras secret" end
    if not (UnitExists(unit) and UnitIsPlayer(unit) and UnitCanAssist("player", unit)) then
        return nil, "no friendly player"
    end
    if not UnitIsConnected(unit) or UnitIsDeadOrGhost(unit) then return nil, "offline or dead" end
    if not MANA_CLASSES[select(2, UnitClass(unit))] then return nil, "no mana user" end
    -- buffing yourself flags nothing (code review 1.1.0, F-05)
    if UnitIsPVP(unit) and not UnitIsUnit(unit, "player") and not db.pvpBuff and not FlaggedForGood() then
        return nil, "flagged for PvP"
    end
    local level = UnitLevel(unit)
    if level and level <= 0 then level = nil end -- "??": unknown, not rank 1
    local spell = IntellectSpell(level)
    if not spell then return nil, "no rank known" end
    if not NeedsIntellect(unit, ns.SpellName(D.SPELL_ARCANE_INTELLECT), ns.SpellName(D.SPELL_ARCANE_BRILLIANCE)) then
        return nil, "has it"
    end
    if not InSpellRange(spell, unit) then return nil, "out of range" end
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
    local spell, why = ns.BuffRunSpell("target")
    -- nil for a spell the client does not know - demo mode treats every rank as known
    local cd = spell and C_Spell.GetSpellCooldown(spell)
    local cooling = cd and cd.startTime > 0
    if down then -- the PreClick sees down and up; one entry per press
        ns.Log("buffrun " .. (cooling and "wait: cooldown" or spell and tostring(spell) or ("none: " .. why)))
    end
    if cooling then
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
local inCombat = false   -- PLAYER_REGEN_DISABLED fires before InCombatLockdown() turns true

-- Auras are unreadable in combat, so a glowing armor would glow through the fight after it was
-- cast. A cast of any mage armor of any rank turns the glow off then; when the client keeps the
-- cast's spell ID secret, a cast after a press on the Armor button or on the key - which holds
-- only the armor in combat - counts (ruleset plan 2026-10-25-combat-locks). After combat the
-- aura decides again.
local ARMOR_SPELLS = {}
for _, family in ipairs(D.ARMOR_FAMILIES) do
    for _, id in ipairs(family) do ARMOR_SPELLS[id] = true end
end
-- The same holds while the client keeps auras secret out of combat (ruleset plan
-- 2026-10-25-secret-auras); a press counts for the next judged cast only.
local function Frozen() return inCombat or not ns.AurasReadable() end
local armorPressed = false
local function Pressed() if Frozen() then armorPressed = true end end
armor:HookScript("OnClick", function(_, button) if button == "LeftButton" then Pressed() end end)
ns.buffKey:HookScript("OnClick", Pressed)

local function ArmorCast(spellID)
    if not (Frozen() and armor.antsShown) then return end
    local secret = ns.IsSecret(spellID)
    if (secret and armorPressed) or (not secret and ARMOR_SPELLS[spellID]) then ns.SetAnts(armor, false) end
    armorPressed = false
end
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
-- Intellect cannot be cast then anyway - its count and glow are hidden (Bar.lua
-- ApplyCombatLook). Everything is checked again once combat ends.
function ns.UpdateBuffState()
    if not db then return end
    if inCombat or InCombatLockdown() then
        UpdateTicker()
        return
    end
    -- While the client keeps auras secret out of combat, a read would see every buff missing:
    -- the armor and Intellect keep what they showed; settings, Buff & Run and the key follow
    -- (ruleset plan 2026-10-25-secret-auras). Demo mode reads no auras.
    if not IsDemo() and not ns.AurasReadable() then
        if intel:IsShown() and not intel.leftSpell then
            -- never read (a login inside an instance): the icon, no click, no line
            local spell = IntellectSpell(nil, ReadKnownRanks())
            intel.icon:SetTexture(GetSpellTex(spell))
            intel.leftSpell, intel.rightSpell, intel.spellId = spell, nil, spell
            intel.hintLeft, intel.hint, intel.hintKey = nil, nil, nil
            SetAttr(intel, "type1", nil)
        end
        UpdateTicker()
        ArmBuffRun()
        ns.UpdateBuffKey()
        return
    end
    armorPressed = false
    local due = UpdateArmorHighlight()
    if intel:IsShown() then
        -- Brilliance once it is learned, Arcane Powder is in the bags and the threshold is not never
        local t = db.brillianceThreshold
        local brilliance = IsKnown(D.SPELL_ARCANE_BRILLIANCE) and t < D.BRILLIANCE_NEVER
            and (IsDemo() or (ItemCount(D.ITEM_ARCANE_POWDER) or 0) > 0)
        if IsDemo() then
            -- Always the group as it looks at the threshold; never: the single buff on yourself
            local n = brilliance and t or 1
            ShowBuffCount(n, n, "missing", true)
            ApplyTargets(intel, "player", brilliance and "player" or nil, n, ReadKnownRanks())
            local spell = brilliance and D.SPELL_ARCANE_BRILLIANCE or IntellectSpell(nil, ReadKnownRanks())
            local whom = brilliance and L.TARGET_GROUP or UnitShortName("player")
            intel.hintLeft = L.HINT_LEFT:format((ns.SpellName(spell) or "?") .. " > " .. whom)
        else
            local known = ReadKnownRanks()
            local probe = IntellectSpell(nil, known)
            local needing, needIn, singleUnit, groupUnit, intellectDue, selfNeed =
                ScanGroup(probe, known, brilliance and t or nil)
            ShowBuffCount(needIn, needing, selfNeed)
            ApplyTargets(intel, singleUnit, groupUnit, needing, known)
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
events:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
events:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if not db then return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit == "player" then ArmorCast(spellID) end
    elseif event == "UNIT_AURA" then
        if unit == "player" then
            QueueUpdate()
        elseif unit and IsGroupUnit(unit) and not InCombatLockdown() then -- pets and others are ignored
            QueueUpdate()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat, armorPressed = true, false
        UpdateTicker()
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat, armorPressed = false, false
        UpdateBuffState() -- the count and glow hidden in combat, and what changed there
    else
        QueueUpdate()
    end
end)
