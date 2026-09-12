MainTank Project Legacy v1.2.69-PL13 LAYEREDSTOP3
===================================================

- Fixed the remaining Main RAW vs Pie divergence on Full Block fights.
- Root cause was not the new dual-wield solver: PL12 Timeline data proved the
  Full Block was initially normalized correctly, but an older RC6q display path
  later mutated the already-finalized event.
- RC6q still called RC6_SumEventDR(), and that legacy helper still called the
  first-generation RC6_EnsureEventAttribution().  For non-DAMAGE outcomes that
  old routine restores rc6BaseRaw and clears Flat/%DR, bypassing LAYEREDSTOP2.
- The PL12 Dragonmaw Raider DB showed the exact fingerprint twice: Timeline had
  the 19.25 OH Full Block estimate, while the persisted event later became
  28.875 RAW / 0 Flat DR and was marked layeredOutcomeIntegrityFailed.
- RC6_SumEventDR now calls the final RC6B_EnsureEventAttribution gate.
- The first-generation RC6 helper is additionally guarded against finalized
  layered outcomes and, at the end of the file, all remaining legacy callers are
  redirected to the final outcome-aware RC6v gate.
- This retires the stale mutation path documented all the way back in the RC6r
  README note (RC6q used an older attribution helper) instead of merely
  overwriting the totals after the event had already been damaged.
- No change to the desired model: Dodge/Parry/Miss = 100% Avoidance; Full Block
  keeps Flat/%DR -> Armor -> terminal Block; Partial Block remains landed math.
- Existing malformed PL12 saved fights are preserved as historical evidence;
  validate with a NEW fight under PL13.

MainTank Project Legacy v1.2.68-PL12 LAYEREDSTOP2
====================================================

FULL BLOCK / PIE ACCOUNTING REPAIR
----------------------------------
- Fixes the PL11 Dragonmaw Raider case where Main showed 606 stopped but the
  RAW/Physical Pie summed to only 560.
- Root cause: finalized Full Block events could be run through the older RC6
  stack again after Pass-2A removed transient math fields. That restored base
  RAW/zero Flat DR before the late LAYEREDSTOP1 marker blocked re-normalization.
- LAYEREDSTOP2 checks the durable finalized-outcome marker BEFORE the older RC6
  stack can mutate a saved event. New finalized outcome events use marker v2 and
  must satisfy RAW = Taken + Flat/%DR + Armor + Block/Resist + Absorb + Avoidance.
- Outcome events are now normalized before RecordEvent writes Timeline and
  Overall buckets, so Timeline, Details, Pie, Main and FINALAGG1 share one split.
- Dual-wield Full Block now tests the captured MH and OH UnitDamage ranges as
  separate ranges. If only one hand can mathematically fit under event-time
  Block Value after DR + Armor, that hand is used instead of averaging across
  the impossible gap between MH and OH ranges.
- Example from the supplied DB: MH 34-43, OH 17-21.5, Sanctuary 10, Armor ~35.2%,
  Block Value 13. The MH cannot full-block; the OH can, so Full Block RAW uses
  the OH midpoint 19.25 rather than the generic dual-wield 28.875 estimate.
- Pure Dodge/Parry/Miss remain 100% Avoidance with zero Armor/DR/Block credit.
- Partial Block remains the normal landed layered path.
- Existing PL10/PL11 marker-v1 fights are left historical; test a NEW fight for
  the corrected v2 outcome math.
- MainTank, MainTank_Archive and MainTank_History report 1.2.68-PL12.

MainTank Project Legacy v1.2.67-PL11 SHIELDSPEC1
===================================================

PROJECT LEGACY SHIELD SPECIALIZATION FIX
-----------------------------------------
- Fixes Block Analysis inheriting the old VanillaPlus Shield Specialization
  fallback of 15% / 30%.
- Project Legacy Shield Specialization is three ranks: 10% / 20% / 30%.
- The authoritative bounded BlockAnalysis calculator now maps learned rank
  directly to 10/20/30%.
- The older Core/Engine fallback is hardened to the same Project Legacy mapping
  and ignores the tooltip's "Next rank" value when determining the active bonus.
- This corrects both the player-facing Block Analysis tooltip and the calculated
  fallback Block Value used when the client API is unavailable.
- GetShieldBlock() remains authoritative when exposed by the client.
- No mitigation ordering, Sanctuary, avoidance, Full Block, partial block,
  FINALAGG1, persistence, or LAYEREDSTOP1 combat math changed in PL11.
- MainTank, MainTank_Archive and MainTank_History report 1.2.67-PL11.

Example at Rank 1/3:
  Talent bonus: +10%   (not +15%)

MainTank Project Legacy v1.2.66-PL10 LAYEREDSTOP1
====================================================

OUTCOME-AWARE MITIGATION FOUNDATION
-----------------------------------
- Replaces PL9's too-broad "complete outcome owns all RAW" rule with the
  final accounting model agreed for MainTank.
- Dodge, Parry, Miss: 100% of estimated pre-mitigation RAW is credited to
  Avoidance. Armor, Flat DR, percentage DR, Block, Resist and Absorb receive
  zero credit because the attack never landed.
- Partial Block: unchanged landed DAMAGE path. Earlier Flat/%DR and Armor keep
  their shares, observed partial Block keeps its share, and the rest is Taken.
- Full Block: now uses the SAME passive layer order as a partial block; Flat/%DR
  and Armor keep the mitigation they actually contributed, and Full Block gets
  only the remainder that reaches the block stage.
- Full Resist: follows the same principle. Earlier applicable Flat/%DR and
  physical Armor (if relevant) keep their shares; Full Resist gets the terminal
  remainder instead of blindly receiving the entire RAW estimate.
- Absorb on normal DAMAGE events remains on the existing landed-event path, so
  it continues to receive only the amount that reaches the absorb stage.

FULL BLOCK ESTIMATION IMPROVEMENTS
----------------------------------
- Every outcome event now snapshots the event-time armor rate and its estimated
  pre-terminal amount; Full Block additionally snapshots event-time Block Value.
- White Full Blocks use the independently captured UnitDamage(target) raw range.
  When Block Value is known, the observed Full Block narrows that range to rolls
  that could actually fit under Block Value after DR + Armor. MainTank uses the
  midpoint of that admissible range instead of an impossible generic average.
- If the raw range and captured Block Value contradict the observed Full Block,
  MainTank preserves the hard raw lower bound and records a math diagnostic
  rather than fabricating a value.
- Matching-context avoidance estimates are now reversed through the DR + Armor
  model to recover pre-mitigation RAW before assigning Dodge/Parry/Miss 100% of
  that RAW. This avoids understating avoidance while Sanctuary/other DR is active.

PERSISTENCE / CONSISTENCY
-------------------------
- `layeredOutcomeVersion = 1` marks finalized outcome attribution as authoritative
  so Pass-2A/Archive/reload cannot recalculate it after diagnostic inputs are
  stripped.
- New diagnostic transport fields are stripped from completed persisted fights
  to preserve SavedVariables size; the finalized category amounts remain.
- FINALAGG1 remains intact, so completed fight.data is rebuilt from the exact
  finalized event stream before Compare/Boss/Archive/History consume it.
- Main, Pie, Timeline, Events, Compare, Boss, Archive and History therefore share
  one outcome-aware event accounting model.
- MainTank, MainTank_Archive and MainTank_History report 1.2.66-PL10.

PLAYER-FACING EXAMPLES
----------------------
Pure avoidance:
  RAW 50 -> Dodge 50 -> Taken 0

Layered Full Block:
  RAW 50 -> Flat DR 10 -> Armor 15 -> Full Block 25 -> Taken 0

Partial Block:
  RAW 50 -> Flat DR 10 -> Armor 15 -> Partial Block 8 -> Taken 17

PL9 NOTE
--------
- PL9 FULLSTOP1 correctly fixed Dodge/Parry/Miss receiving Armor credit, but it
  also gave Full Block/Full Resist 100% of RAW. PL10 supersedes that part: those
  are landed terminal outcomes and now preserve their earlier mitigation layers.

MainTank Project Legacy v1.2.65-PL9 FULLSTOP1
================================================

COMPLETE AVOIDANCE / FULL BLOCK ATTRIBUTION FIX
-----------------------------------------------
- Dodge, Parry, Miss, and Full Block now receive 100% of the estimated RAW
  attack as their own stopped-damage category. Armor receives 0 on these
  complete outcomes because the attack never reaches the armor stage.
- Full Resist follows the same complete-outcome rule for consistency: its
  entire hypothetical RAW amount belongs to Resist, not Armor.
- Partial Block is intentionally unchanged. It remains a landed DAMAGE event,
  so MainTank can continue reconstructing Armor + the observed partial block.
- Example regression: an avoided Raw 39 attack previously displayed Armor 15 +
  Avoid 24. FULLSTOP1 displays Raw 39 / Armor 0 / Avoid 39 / Taken 0.
- The legacy hot-path aggregate and the authoritative RC6 event path were both
  corrected so Main, Pie, Timeline, Details, Compare, Boss, Archive and History
  all consume the same category attribution for newly recorded fights.
- A final RC6 complete-outcome sanitizer also corrects PL8-era recent detailed
  events in RAM when viewed, without re-running historical DAMAGE/DR math.
- FINALAGG1 remains intact: finalized fight.data is still rebuilt from the
  authoritative event stream at EndCombat.
- MainTank, MainTank_Archive, and MainTank_History self-report 1.2.65-PL9.

MainTank Project Legacy v1.2.64-PL8 FINALAGG1
===============================================

FINALIZED AGGREGATE CONSISTENCY FIX
-----------------------------------
- Fixes completed Current/saved fights showing less RAW/Stopped damage than the
  RAW Pie when Flat DR or percentage DR was active.
- Root cause: the combat hot-path `self.data` aggregate does not model RC6 DR,
  while the authoritative event stream does. EndCombat previously copied that
  legacy aggregate into `fight.data`, creating a split between Main and Pie.
- EndCombat now rebuilds one final aggregate from the already-attributed RC6
  events BEFORE later Compare/Boss/Archive/History wrappers can consume it.
- This restores the core invariant: RAW - Taken equals the sum of stopped damage
  categories represented by the finalized event stream.
- Live combat parsing is unchanged; the rebuild runs once at combat finalization.
- New fights are marked `finalAggregateVersion = 1` for diagnostics.
- MainTank, MainTank_Archive, and MainTank_History self-report 1.2.64-PL8.

BLACK OOZE REGRESSION CASE
--------------------------
The PL7 screenshot exposed 314 RAW / 191 Taken / 123 Stopped on Main while the
RAW Pie showed 101 Armor + 110 Flat DR + 22 Blocks = 233 Prevented. The missing
110 exactly matched eleven Rank-1 Sanctuary applications. FINALAGG1 makes the
completed fight consume the same RC6 event aggregate as the Pie/Timeline so the
headline can no longer drop that DR at EndCombat.

MainTank v1.2.63 BOSSGUARD2
==========================

WHAT BOSSGUARD2 FIXES
---------------------
- Multi-phase/add-heavy Boss encounters no longer require the skull Boss to be
  the largest incoming RAW source (primaryEnemy) in order to receive BOSS
  retention/classification.
- primaryEnemy remains the truthful largest incoming-damage source.  Boss name
  and Boss classification are stored separately.
- The secondary-Boss path is conservative: it requires an authoritative Boss
  Profile from the exact same fightID, the same analytical primaryEnemy,
  positive Boss RAW, and at least 3 actual Boss incoming events.
- This preserves BOSSGUARD1 protection against a trash pull becoming BOSS just
  because a nearby skull mob was targeted or briefly touched.
- Existing Recent, Archive, and History records are repaired only through exact
  BossProfile.fightID == fight.id/summary.id identity.  RAW, Taken, mitigation,
  DR, events, timelines, counts, and durations are never recalculated.
- History summaries that have already discarded detailed Events remain summaries;
  BOSSGUARD2 repairs their identity/classification only.

REAL SAVEDVARIABLE REGRESSION CASES USED
----------------------------------------
1. Razorgore the Untamed
   fightID 23 | 509.57s | 53 Boss events | Boss RAW 54,479.77
   analytical primaryEnemy: Death Talon Dragonspawn
   old result: MAJOR Death Talon Dragonspawn +15
   BOSSGUARD2 result: BOSS Razorgore the Untamed +15

2. Elementium Decapitator Mk III
   fightID 24 | 310.65s | 9 Boss events | Boss RAW 8,480.56
   analytical primaryEnemy: Oil Fires
   BOSSGUARD2 recognizes the same exact add-heavy Boss pattern.

VERSION LOCK
------------
MainTank, MainTank_Archive, and MainTank_History all report package version
1.2.63.

MainTank v1.2.62 FINALHOTFIX2 - Highlights Readability Fix

- Keeps Combat Highlights at the established 300x231 size while increasing
  vertical leading inside all seven two-line highlight cards so labels and the
  timestamp/source line no longer visually touch on Vanilla's outlined font.
- Repositions only the existing View Event Details/inspector area to make room;
  combat data, Crit/Crush filtering, Export, Boss Profiles, and persistence are
  unchanged.
- MainTank, MainTank_Archive, and MainTank_History all report package version
  1.2.62, including the companion live self-report values introduced in 1.2.61.

MainTank v1.2.61 FINALHOTFIX1 - Companion Version Self-Report Fix

- MainTank_Archive and MainTank_History once again self-report their own package
  version from their own Lua files.
- Companion health checks prefer this live self-report before TOC metadata.
- Fixes false old-version warnings after replacing addon folders and using
  /reload on Vanilla clients that keep addon TOC metadata cached.
- No combat, mitigation, persistence, Boss, Compare, Export, Archive retention,
  History, or UI behavior changed from v1.2.60 FINAL.

MainTank v1.2.60 FINAL - Public Release
=========================================
- Final public-release package built directly from the tested v1.2.58 EXPORTFLOW1
  code line. No combat, mitigation, persistence, Sync, Boss, Archive/History,
  parser, Export, Highlights, or UI behavior was changed for the final cut.
- Includes the CRUSHFIX1 authoritative Vanilla crushing-blow parser fix, the
  CRITCRUSH1 Critical/Crushing Highlights review path, and EXPORTFLOW1's fixed
  300x231 wrapped/paged technical export viewer.
- Keeps the proven three-XML architecture only: MainFrame.xml,
  AnalysisFrames.xml, and FightBrowser.xml. The discarded XML experiment is not
  part of this release.
- Distribution contains exactly three required addon folders: MainTank,
  MainTank_Archive, and MainTank_History. All three are version-locked to 1.2.60.
- Persistence remains bounded at 8 Recent detailed + 8 Archive detailed + 64
  History summaries, with Archive priority Boss > Major > Minor > PvP.
- Release policy: future changes after this build should ship as a new version
  rather than modifying this final package in place.

MainTank v1.2.58 EXPORTFLOW1 - Fixed-size Export flow + Highlights empty-state cleanup
-------------------------------------------------------------------------------------
- Export remains exactly 300x231. Detailed and Boss/Profile reports are wrapped into
  a display-only 44-character layout and paged ten visible lines at a time so long
  technical reports stay inside the existing window instead of rendering past its
  right/bottom edges. No combat or mitigation values are recalculated.
- Detailed/Boss paging uses the otherwise-unused bottom chat strip. Summary keeps its
  existing Party/Raid/Guild/Say buttons and compact presentation.
- Select All still exposes and highlights the complete wrapped report for Ctrl+C; it
  never copies only the currently visible page. Losing focus restores the clean page.
- Combat Highlights now keeps all seven category cards in a continuous stack. Empty
  categories display an explicit zero and a non-clickable "No ... recorded" line
  instead of disappearing and leaving broken-looking holes.
- Highlights also clears a selected event when the user changes to another fight,
  preventing stale Inspector/View Event Details text from the previous encounter.
- Built directly on v1.2.57 CRITCRUSH1. CRUSHFIX1 parser authority, Boss Profiles,
  Compare Sync, persistence, Archive/History, RC6 math and PvP safety are unchanged.

MainTank v1.2.57 CRITCRUSH1 - Highlights Critical/Crushing review
-----------------------------------------------------------------------
- Adds a seventh Combat Highlights row, `Largest Crit / Crush Hit`, using the
  same authoritative saved event stream as the existing Highlights metrics.
  The two values are the largest actual damage Taken by Critical and Crushing
  hits respectively; no separate combat counters or inferred damage logic are
  introduced.
- Selecting that combined row changes `View Event Details` into an encounter-
  wide Critical/Crushing gateway. Events opens filtered to every saved event
  whose authoritative `event.critical` or `event.crushing` flag is true.
- The special Events filter begins with no enemy selected so the replay list is
  genuinely fight-wide; selecting an enemy narrows the same filter normally.
  Show All clears it using the existing Details filter path.
- Normal Highlights rows retain their exact-event `View Event Details` behavior
  and Back still returns to Combat Highlights.
- Combat Highlights remains the established 300x231 managed window. Seven rows
  are fit by compacting row spacing only; no Main/Export/Boss window is enlarged.
- Built directly on v1.2.56 CRUSHFIX1. Parser authority, Boss Profile counting,
  Compare Sync, persistence, Archive/History, mitigation math and PvP safety are
  unchanged.

MainTank v1.2.56 CRUSHFIX1 - Crushing-blow parser + Export tab fit
-------------------------------------------------------------------
- Fixed Vanilla 1.12 white crushing blows reported as ordinary
  "<mob> hits you for <amount>. (crushing)" combat text. The generic hit
  parser previously returned before the later dedicated crush pattern, leaving
  event.crushing=false. Crushing is now identified at the authoritative combat
  parser before RecordDamage, so Events/Inspector, Highlights, Boss Profiles
  and Boss/Profile Export all consume the same corrected event flag.
- Retains support for the alternate explicit "<mob> crushes you for <amount>"
  wording. Critical/"critically hits" forms are now matched before generic hits
  so greedy Lua captures cannot contaminate the mob/ability name.
- Export window remains exactly the established 300x231 size. Summary, Detailed
  and Boss/Profile tab widths/spacing were rebalanced so the longer labels fit
  cleanly; Select All was tightened slightly to make room.
- Existing detailed fights created before CRUSHFIX1 cannot be automatically
  reclassified from SavedVariables alone when their event.crushing flag was
  already saved false; MainTank deliberately does not guess crushes from damage
  magnitude.
- Based directly on v1.2.55 RELEASECLEAN1. No persistence, Archive/History,
  Compare Sync, mitigation math, Boss classification, PvP safety or restore
  architecture changes.

MainTank v1.2.55 RELEASECLEAN1 - Pristine release cleanup
----------------------------------------------------------------
- Built directly from the proven v1.2.52 MAINCRISP1 baseline; the discarded
  v1.2.53/v1.2.54 XML experiment is not included.
- Keeps exactly the three proven XML files: MainFrame.xml, AnalysisFrames.xml,
  and FightBrowser.xml. No UI creation timing is changed.
- Removes only provably unused code: the dead Fight Browser show helper/history
  constant, unused block-refresh shim, unused Pie getter capture, unused analysis
  close local, and the abandoned RC5 Compare row-count bridge.
- Removes unused runtime/public aliases that had no packaged readers: legacy
  timeline/biggest initializers plus unused command-help, companion-list, school
  canonical, context-prune, and close-window exports. Their live local logic
  remains intact wherever it is actually used.
- Removes seven abandoned mitigation-wrapper capture globals that were assigned
  but never read by any packaged layer. Active RC5-RC6 wrapper captures remain
  untouched.
- Removes the now comment-only root MainTank.lua bootstrap entirely; Core/Engine.lua
  remains the authoritative namespace/bootstrap as it already was at runtime.
- Removes stale companion package-version globals. Current companion
  versions come from TOC metadata; old globals remain readable only as a
  compatibility fallback for older installed companions.
- Combat parser, RC6 mitigation math, Compare Sync, SI2/DC2 restore ordering,
  Archive/History retention, Boss Profile persistence, PvP quarantine, and the
  MAINCRISP1 UI are intentionally unchanged.

MainTank v1.2.52 MAINCRISP1

MAINCRISP1
- Main-page RAW / PHYSICAL / MAGIC selectors reduced from 78x18 to 70x16.
- Secondary selector group recentered for a cleaner hierarchy beneath the larger Current / Overall controls.
- No combat, mitigation, Sync, Export, persistence, Archive, History, or Boss logic changed.

--------------------------------
- Reworks Export into three release-facing modes without creating parallel combat logic: Summary delegates to the proven RC2/RC3 export builder, Detailed reads the authoritative GetDisplayData aggregate, and Boss/Profile reads the selected BuildBossBreakdown profile.
- Adds Summary | Detailed | Boss/Profile tabs plus a one-click Select All action inside the established managed Export window. Selected export mode is UI state only and is not persisted.
- Summary remains compact and gains the modern RC6 Flat/Physical/Magic DR totals. Detailed extends that same summary with authoritative event/hit counts, avoidance counts, partial/full block and resist values, absorb count, physical/magic Flat DR, and physical/magic RAW/Taken totals.
- Boss/Profile export copies the full selected persistent Boss Profile: encounter metadata, RAW/Taken/Stopped/Mitigation, Boss RAW Share, Other Enemies RAW, RC6-complete mitigation, every recorded damage school, and every recorded boss ability. It never rebuilds the Boss Profile from events.
- Party/Raid/Guild/Say sharing is intentionally Summary-only to avoid accidental multi-line technical spam; Detailed and Boss/Profile modes are copy-oriented and show their generated line count.
- Keeps /mt export and /mt report compatible; optional /mt export summary|detailed|boss shortcuts are power-user conveniences only. Compare Sync/MTANK1/MTANK2, Boss persistence, combat math, Archive/History, and PvP safety are unchanged.

MainTank v1.2.50 COMPARE2
- Fixes Compare presentation/selection integration without touching RC4/RC5 Sync authority.
- Delta UI now attaches after the authoritative synced-encounter updater completes instead of wrapping Compare frame creation.
- Rebinds tank-row clicks at the final UI layer so selecting a synced tank always refreshes the Delta panel.
- Keeps MTANK1/MTANK2 sync, encounter grouping, history paging, and SavedVariables behavior unchanged.

MainTank v1.2.49 COMPARE1
--------------------------------
- Reworks Tank Compare as a compact synced-encounter comparison instead of a raw summary dump. The authoritative RC5 encounter grouping, fight pager, tank selection, Sync Now behavior, and bounded comparison-history persistence remain intact.
- Keeps the existing synced-tank table, then adds a neutral fixed-column Delta panel comparing the selected tank against your own synced summary for the same encounter. Deltas are shown as plain +/- values rather than green/red judgement because tank assignments and workloads may differ.
- Delta metrics page independently through Core (RAW/Taken/Stopped/Mitigation/Duration), Mitigation (Armor/Avoidance/Block/Resist/Absorb), and DR/Damage (Flat DR/Physical DR/Magic DR/Physical RAW/Magic RAW) without enlarging the established 300x231 analysis window.
- Restores fightID/endedAt metadata after the later RC6 summary rebuild so manual Sync history can match encounters by authoritative fight identity instead of receipt time alone.
- Preserves the proven MTANK1 v1/v2 addon-message protocol for backward compatibility. RC6-only DR totals travel in a second tiny MTANK2 extension message and merge into the same summary; older clients simply ignore it, while newer clients display `--` when a remote summary did not provide RC6 extension data.
- Carries forward the BOSSPROFILE3 pager-width polish: Boss Damage Schools / Top Boss Abilities page counters have enough width for values such as 1/3 and 1/4 without wrapping.

MainTank v1.2.47 BOSSPROFILE2
--------------------------------
- Adds independent paging to Boss Profile `Damage Schools` and `Top Boss Abilities` while keeping the established compact 300x231 window. Each section still shows three fixed-column rows at a time, with its own `< 1/2 >` controls only when more rows exist.
- School and ability paging are UI-only encounter-local state: changing Boss encounters resets both sections to page 1, and no paging state is written to SavedVariables.
- RAW/TAKEN fixed-column alignment, RC6 mitigation totals, Boss persistence/recovery, Boss > Major > Minor classification, and the bounded Boss Profile store are unchanged.

MainTank v1.2.46 BOSSPROFILE1
--------------------------------
- Fixes Boss Profiles disappearing after logout/login or /reload. The final persistence coordinator now seeds the saved `bossHistory` / selected index before entering the historical Restore chain, so nested restore-time Sync calls cannot overwrite valid Boss data with an empty table.
- Adds bounded self-recovery from authoritative detailed BOSS fights. If an older build already lost the standalone Boss Profile table, retained Recent/Archive encounters can rebuild the missing profile from finalized event data; restoring an archived Boss encounter can therefore repopulate the Boss browser immediately.
- Recovery obeys BOSSGUARD: only a persisted/live UnitLevel == -1 boss whose name is also the detailed fight's `primaryEnemy` may rebuild a profile. A stale Primordial/adjacent-trash BOSS stamp cannot authenticate itself.
- New legitimate Boss fights also carry a tiny fight-local `bossSkull` identity marker written only from live UnitLevel == -1 evidence. This lets retained detailed Boss fights remain self-authenticating even if target memory/profile history is later unavailable, while old plain `isBoss` flags from the v1.2.44 bug are never trusted by themselves.
- New Boss Profiles are RC6-complete: Absorb, Flat DR, Physical DR, and Magic DR are accumulated directly from authoritative finalized event fields in addition to Armor/Avoidance/Block/Resist. Matching older profiles are enriched from their retained detailed encounter when possible.
- Boss Profile UI remains the compact 300x231 page but now uses fixed RAW/TAKEN columns for Damage Schools and Top Boss Abilities, clearer Encounter x/y + saved time metadata, proper duration/event/crit/crush context, explicit Boss RAW Share/Adds RAW, and a two-line full mitigation breakdown.
- New profiles carry the finalized fight ID for exact recovery/deduplication; older profiles are matched conservatively by boss name + finalized RAW/Taken (+ duration when available). The existing bounded `bossHistory` persistence architecture and 30-profile cap are retained.

MainTank v1.2.45 BOSSGUARD1
--------------------------------
- Fixes a v1.2.44 Boss false-positive: merely targeting/briefly touching a known skull boss during an adjacent trash pull can no longer promote that trash fight to BOSS.
- Boss retention identity is now fight-local and exact: BOSS requires the known skull boss to be the finalized fight's `primaryEnemy`; target selection or incidental boss presence elsewhere in the event stream is not enough.
- Repairs already-saved Recent/Archive false positives on restore/PLAYER_ENTERING_WORLD. A stale BOSS record whose stored boss identity does not match its primary enemy is safely downgraded to MAJOR (50K+ RAW) or MINOR without changing combat totals/events.
- History summary repair follows the same exact-primary rule when enough identity metadata is available.
- The intended retention order remains BOSS > MAJOR > MINOR > PvP; this patch tightens only what qualifies as a BOSS encounter.
- Boss Profile capture itself remains available for true skull targets and no combat/mitigation arithmetic changed.

MainTank v1.2.44 BOSSPRIORITY1
--------------------------------
- Fixes authoritative Boss classification for real skull-level (`??` / `??B`) encounters: a boss fight now stays BOSS regardless of whether RAW is above the 50K Major threshold.
- Boss Profile capture and detailed-fight retention now share the same per-encounter `UnitLevel == -1` evidence; the newly finalized fight is stamped `isBoss` / `bossName` / priority 4 before Archive rollover can classify it.
- Adds a persisted Boss Profile fallback for older detailed fights and repairs already-saved Recent fights on restore when their event source matches a known skull-level Boss Profile.
- Player-facing retention categories are now BOSS / MAJOR / MINOR / PvP. MAJOR means a non-boss PvE fight with at least 50K RAW. Internal priority numbers and the legacy `archiveKind = "50k"` identifier remain unchanged for compatibility.
- Retention authority is now explicitly: BOSS > MAJOR (50K+ RAW non-boss) > MINOR (under 50K RAW non-boss) > PvP.
- No combat arithmetic, RC6 mitigation math, SI2/DC2 restore order, History aggregate math, or PvP quarantine behavior changed.

MainTank v1.2.43 EVENTSNAMING1
--------------------------------
- Renames the player-facing Main-page `Details` analysis to `Events`; the proven internal `DETAILS` page identity and function chain remain unchanged.
- The analysis title now reads `Events - [Fight]`, while the single-record action remains `View Event Details`.
- `/mt events` now opens Events. Legacy `/mt details`, `/mt enemies`, and `/mt abilities` remain compatibility aliases; the old event-count diagnostic is retained as hidden `/mt eventcount`.
- No combat parsing, mitigation math, persistence, Archive/History retention, Compare, Export, or Boss Profile behavior changed.

MainTank v1.2.42 RELEASEPOLISH1
--------------------------------
- Release packaging cleanup: MainTank_Archive and MainTank_History are now normal required enabled companions, not LoadOnDemand addons.
- Both companion TOCs explicitly declare `## Dependencies: MainTank`; the core remains the only combat/UI addon and the companions remain tiny SavedVariables backends.
- MainTank warns once per login/reload when Archive or History is missing, installed but not loaded, fails to initialize, or is from a mismatched package version.
- /mt releasecheck and storage diagnostics now fail when required companions are unavailable instead of mistaking missing stores for empty healthy stores.
- Current Archive/History access no longer tries to force-load disabled companions. LoadAddOn remains only for the one-time importer for retired General/Boss archive folders.
- Hardens the old single-folder -> three-folder migration: legacy Archive/History payloads are retained and retried if a required companion is unavailable, rather than being cleared before transfer succeeds.
- Removes the active RC3b Bloodsail Raider test-boss override. New Boss Profiles are true skull-level (??) encounters only; legacy stored test profiles remain readable.
- Refreshes release-facing TOC descriptions, command help (Highlights), current architecture documentation, and companion source headers.
- Removes 35 stale RC/FR-era runtime `MT.version` assignments; `Core/Release.lua` is now the only runtime owner of the public build version while historical section comments remain intact.
- Combat parsing, mitigation arithmetic, SI2/DC2 restore order, Archive priority, History summary math, PvP quarantine, and the v1.2.40 Main-page geometry are otherwise unchanged.

CURRENT PACKAGE / INSTALLATION
------------------------------
Install and enable all three folders together:

  MainTank
  MainTank_Archive
  MainTank_History

MainTank is the interactive addon. MainTank_Archive owns up to 8 priority detailed archived fights, and MainTank_History owns up to 64 lightweight long-term summaries. The companions depend on MainTank and contain no combat parser or UI. Keeping them separate gives each persistence tier its own physical SavedVariables failure domain.

WHAT MAINTANK ACTUALLY TRACKS
-----------------------------
MainTank is a deep incoming-damage and tank-mitigation analyzer for WoW 1.12.1 / VanillaPlus. It reconstructs and separates damage taken from damage prevented through armor, Flat DR, Physical/Spell DR, avoidance, full and partial blocks, partial/full resists, absorbs, and school-specific damage. It retains event-level detail for Recent/Archive fights and summary-only long-term History.

Player-facing analysis includes the Main RAW/PHYSICAL/MAGIC summaries, Timeline, Pie Chart, Combat Highlights, Events / Event Details, Boss Profiles, Tank Compare, exports, DR inspection, and the unified Fights browser for Recent / Archive / History. The persistence contract is intentionally bounded at 8 Recent detailed + 8 priority Archive detailed + 64 History summaries.

The historical development log below is intentionally retained as a forensic reference. Older entries mention retired LoadOnDemand/Data Vault/General-Boss archive designs; those descriptions are historical and are not the current v1.2.50 package architecture.

MainTank v1.2.40 NAVPOLISH5
--------------------------------
- Refines the Main-page selector hierarchy without increasing the 300px window footprint.
- Current / Overall are now a restrained 92x20 (previously 88x18) with an 8px center gap, making the primary fight-view selector slightly more prominent.
- RAW / PHYSICAL / MAGIC are now a restrained 78x18 (previously 82x20) while preserving their existing centers and selected-grey behavior.
- No font-size change is used for the hierarchy; typography remains uniform and only button geometry changes.
- Summary rows, combat math, mitigation, persistence, Archive/History, and PvP safety are unchanged.

MainTank v1.2.39 NAVPOLISH4
--------------------------------
- Fixes Timeline and Pie Chart View: RAW / PHYSICAL / MAGIC text turning gold/yellow after cycling modes.
- Root cause was the historical RC6P selector refresh helper explicitly repainting the mode button gold after interaction.
- The legacy helper now uses white text, and the final NavigationPolish layer reasserts white after every Timeline/Pie update as defense-in-depth.
- The View selector remains a neutral cycling action button; unlike true tab groups, it never uses selected-grey or gold text.
- Combat parsing, mitigation math, persistence, Archive/History retention, and PvP safety are unchanged.

MainTank v1.2.38 NAVPOLISH3
--------------------------------
- Standardizes the Main-page mode selector to RAW / PHYSICAL / MAGIC in full caps, matching Timeline and Pie Chart.
- This is visible-text-only; internal page keys and all selector behavior remain unchanged.
- Keeps the selected-tab rule from NAVPOLISH2: active selector grey, inactive selectors white.
- Combat parsing, mitigation, persistence, Archive/History retention, and PvP safety are unchanged.

MainTank v1.2.37 NAVPOLISH2
--------------------------------
- Fixes the remaining Main-page typography mismatch where the Lua-created Compare, Fights, Export, and Boss buttons could appear larger and grey while XML-era buttons were smaller/white.
- Uses the Current button's live font as the canonical MainTank button typography and clones that exact font family, size, and flags onto every text-bearing button.
- Restores Current/Overall as a true selector pair: the selected view is grey and the unselected view is white, matching RAW/Physical/Magic and Fights tabs.
- Navigation/action buttons remain white; selected tabs/selectors alone use the grey selected state.
- Reasserts typography after Main-window mode reconciliation so login, /reload, and Mini/Full transitions cannot expose the older legacy font/color.
- Combat parsing, mitigation, persistence, Archive/History retention, and PvP safety are unchanged.

MainTank v1.2.36 NAVPOLISH1
--------------------------------
- Normalizes release-facing button text: navigation/action buttons are white; only the active tab in true tab groups is grey.
- Applies the rule consistently to Main navigation, Current/Overall, MT Main, Back, analysis pages, and the Fights browser.
- Renames Biggest to Highlights; the page title is now Combat Highlights because it includes armor, block, resist, and avoidance records as well as damage hits.
- Adds extra vertical breathing room between each highlight category and its event line.
- Replaces the plain Selected Event heading with a View Event Details button. It opens the exact selected combat event in the existing Details/Event Viewer, and Back returns to Combat Highlights.
- Combat parsing, mitigation math, persistence, Archive/History retention, and PvP safety are unchanged.

MainTank v1.2.35 FIGHTBROWSER2
--------------------------------
- Polishes the unified Fights browser so Recent, Archive, and History rows use true fixed pixel columns instead of padded proportional-font strings.
- R/A/H index, priority tag, fight name, and RAW now stay vertically aligned regardless of MINOR, BOSS, PvP, MAJOR, label length, or digit count.
- History keeps mitigation percentage in its own right-aligned column.
- Archive is converted too so mixed priority types remain as neat as the original all-Major screenshot.
- This is presentation-only: fight selection, Archive Restore, History paging/detail reports, combat math, persistence, and retention behavior are unchanged.

MainTank v1.2.34 FIGHTBROWSER1
--------------------------------
- Replaces the standalone History entry point with one player-facing Fights browser.
- Fights has Recent 8/8, Archive 8/8, and History 64/64 tabs with live counts.
- Recent rows open the existing detailed saved-fight view; a temporary Back button returns to Fights.
- Archive rows expose an explicit Restore action backed by the existing archive restore path.
- History Summary and More Info now live under the History tab without changing their aggregate calculations.
- /mt fights, /mt archive, and /mt history remain as shortcuts to the corresponding UI tabs.
- No combat parsing, mitigation math, retention priority, or PvP persistence-safety behavior changed.

MainTank v1.2.33 REFACXML2_UIFIX3 - authoritative Mini Mode registration
--------------------------------------------------------------------------
- Fixes the reproducible login/reload-only Mini Mode leak confirmed by video:
  Compare, History, Export, Boss, and Reset could appear over/outside Mini Mode.
- Root pattern: those five controls are created by historical CreateUI wrappers
  after the base Summary layer has already restored saved Mini Mode.
- Adds RegisterFullControl() as the single registration gate for every full-mode
  control. A control created while Mini Mode is active is hidden immediately, so
  correctness no longer depends on a later wrapper-chain cleanup pass.
- Strengthens final reconciliation to scan all registered controls plus the five
  named late controls, and reasserts the invariant after Initialize,
  PLAYER_ENTERING_WORLD, SetMiniMode, and pfUI re-skin.
- No combat parsing, mitigation math, persistence, Archive/History retention,
  restore ordering, or PvP safety behavior is changed.

MainTank v1.2.32 REFACXML2_UIFIX2 - Mini Mode reload lifecycle fix
----------------------------------------------------------------
- Fixes full-size Main controls leaking into Mini Mode after /reload or login
  when Mini Mode was already saved.
- The leaked controls included Reset Data and, depending on wrapper order,
  Compare, History, Export, and Boss.
- Adds UI/Lifecycle.lua as the final UI reconciliation layer after every
  historical CreateUI wrapper has finished creating controls.
- Reapplies the Full/Mini visibility invariant after CreateUI and after every
  SetMiniMode transition, including RC1i header/stat divider visibility.
- Does not change frame geometry, combat parsing, mitigation math, persistence,
  Archive/History behavior, restore ordering, or PvP safety logic.

MainTank v1.2.31 REFACXML2_UIFIX1 - XML summary parity fix
----------------------------------------------------------------
- Fixes the Main summary UI regression identified by before/after video review.
- Removes eight unused XML row-divider textures that became visible after the
  Lua-to-XML conversion, restoring the clean text-only RAW/Physical/Magic rows.
- Fixes the same divider textures extending outside the frame in Mini Mode.
- The other reviewed pages (Timeline, Compare, History, Biggest, Export, Boss,
  Details, Pie, History Summary, and History More Info) remain structurally
  unchanged from REFACXML1 and visually match the pre-refactor recording.
- No combat parsing, mitigation math, persistence, Archive/History, restore
  ordering, navigation logic, or PvP safety behavior is changed.

MainTank v1.2.30 REFACXML1 - Engine modularization + XML UI foundation
----------------------------------------------------------------
- Refactors the historical 12,647-line Core/Engine.lua into explicit source
  layers while preserving the existing combat/parser and compatibility behavior.
- Core/Engine.lua is now about 1,038 lines and owns the true combat core: data
  primitives, block/raw estimation, combat memory, event construction/accounting,
  and the Vanilla 1.12 combat-message parser.
- Extracts presentation, session/persistence foundation, summary controller, base
  commands, runtime event routing, analysis core, navigation, analysis features,
  mitigation compatibility, and Back navigation into focused Lua modules.
- Keeps the complete RC5-RC6t mitigation stack together intentionally because
  later RC6 layers mutate lexical classifiers captured by earlier closures.
- Adds UI/MainFrame.xml for the static Main summary hierarchy/geometry and
  UI/AnalysisFrames.xml for the shared Timeline/Pie/Details/Biggest page shell.
  Dynamic event rows, graphs, live values, runtime state, and combat logic remain
  in Lua.
- Uses a runtime-only MainTank._engine bridge for the small set of original local
  helpers needed across extracted files; nothing in that bridge is persisted.
- Preserves the historical style-override semantics through a private dispatch
  slot so RC6o still changes buttons created by earlier layers.
- Repairs two malformed Runtime-health diagnostic Print calls accidentally
  introduced during RELEASECLEANUP2; the v1.2.27 known-safe baseline did not
  contain that syntax defect.
- Static validation: all Lua files parse, both XML files are well-formed, every
  TOC path resolves, the final MainTank method-definition inventory is unchanged
  (163 distinct methods / 391 historical definitions), and a stubbed TOC-load +
  Initialize/CreateUI integration smoke test completes.
- This is a refactor test checkpoint. Combat math, Archive/History retention,
  SI2/DC2/Pass-2B restore ordering, and PvP context-quarantine policy are not
  intentionally changed.

MainTank v1.2.29 RELEASECLEANUP2 - Command/debug surface cleanup
----------------------------------------------------------------
- Simplifies `/mt help` to the commands normal users are expected to use.
- Keeps deep diagnostics available for troubleshooting without advertising them
  as ordinary release features (releasecheck, dbhealth, startup, parser/debug,
  DR scans/math audits, raw item scans, event/memory health, storage checks).
- Removes obsolete `stresscheck` aliases; `/mt releasecheck` remains the single
  authoritative release-safety audit command.
- Removes a dead older RC6j `/mt itemdr` implementation that was already fully
  shadowed by the later authoritative DR scanner; `/mt itemraw` remains intact.
- Cleans legacy FR1P/FR1d labels from diagnostic chat output.
- No combat accounting, mitigation math, persistence, Archive/History retention,
  PvP quarantine, restore ordering, or UI behavior was changed.

MainTank v1.2.28 RELEASECLEANUP1 - Release metadata/documentation cleanup
----------------------------------------------------------------
- Begins the release-hardening cleanup line without changing runtime behavior.
- Synchronizes MainTank, MainTank_Archive, and MainTank_History package versions.
- Updates ARCHITECTURE.txt to the actual final bounded storage contract:
  8 Recent detailed + 8 Archive detailed + 64 History summaries = 80 records max,
  with only 16 detailed/event-bearing fights.
- Corrects stale pre-HISTORY64 release-check documentation that still referenced
  8 History / 24 total records.
- Parser, mitigation math, RC6 attribution, Archive/History retention behavior,
  PvP quarantine, SI2/DC2/Pass-2B restore ordering, and UI behavior are unchanged.

MainTank v1.2.27 HIST64UI14 - History DR mitigation + grid alignment
-------------------------------------------------------------------------------
- History More Info adds DR mitigation as DR / (Taken + DR), using the same
  one-decimal percentage formatting as Overall / Physical / Magic mitigation.
- DR is the same combined retained total shown on History Summary: Physical DR
  + Physical Flat DR + Magic DR + Magic Flat DR.
- A zero denominator is explicitly guarded; zero/empty DR summaries display
  0.0% and cannot divide by zero.
- Rebuilt the History More Info guide/grid geometry for four Mitigation rows and
  four Attacks/Casts rows so the lower Avoidance/Misc sections align cleanly.
- Rebuilt the History Summary guide/grid geometry around the true Overall /
  Physical and EST. / Magic section breaks.  Guides no longer run through or
  visually offset section headers and the More Info button cell.
- Physical Landed attempts remain: landed + Dodge + Parry + Miss + Full Block.
  Partial Blocks remain landed and are not double-counted.
- UI-only pass: no combat math, RC6, persistence format, Archive/History
  retention, DC2, or Pass-2B behavior changed.

MainTank v1.2.26 HIST64UI13 - Attacks/Casts + Events
----------------------------------------------------------------
- History More Info renames ATTACKS to ATTACKS/CASTS.
- Adds retained History eventCount as Events at the top of ATTACKS/CASTS.
- MISC. remains intentionally sparse and shows only the retained Absorbed amount.
- Existing Absorbs, Physical Landed, Magic Landed, Mitigation, and Avoidance
  calculations/presentation are unchanged.
- UI-only History pass; no parser, mitigation math, persistence, Archive/History
  retention, DC2, or Pass-2B changes.

MainTank v1.2.25 HIST64UI12 - Summary EST + More Info Absorbs
----------------------------------------------------------------
- Restores the gold EST. section header on History Summary and removes Absorbs
  from that page. Summary keeps RAW, Taken, Prevented, combined DR, then the
  EST. Armor/Avoidance/Full Block/Full Resist block.
- More Info now uses a compact 2x2 layout: Mitigation + Attacks on top,
  Avoidance + Absorbed below.
- Attacks shows Absorbs as absorb-event count / total physical+magic attempts.
- Absorbed shows the total absorbed amount separately.
- Physical attempts include landed + Dodge + Parry + Miss + Full Block; Partial
  Blocks remain landed. Magic attempts remain landed + Full Resist.
- UI-only History pass; no parser, mitigation math, persistence, Archive/History
  retention, DC2, or Pass-2B changes.

MainTank v1.2.24 HIST64UI11 - More Info Fit + Physical Attempts
----------------------------------------------------------------
- Reflows History More Info into a compact two-column Vanilla 1.12 layout so
  Mitigation and Avoidance sit side-by-side and Attacks fits underneath without
  clipping outside the 300x231 MainTank window.
- Physical Landed denominator now includes Full Block together with Dodge,
  Parry, and Miss. Partial Blocks remain landed and are not double-counted.
- Magic Landed remains landed / (landed + Full Resist); partial resists remain
  landed.
- UI-only/count presentation pass. No combat parser, mitigation math,
  persistence, Archive/History retention, or DC2/Pass-2B changes.

MainTank v1.2.23 HIST64UI10 - History More Info
-------------------------------------------------------------------------------
- History Summary no longer shows Mitigation %, keeping the Overall and
  Physical/Magic columns visually balanced.
- Event Counts is renamed More Info.
- More Info shows Overall, Physical, and Magic mitigation percentages derived
  from the already-retained History RAW/Taken aggregates.
- Avoidance breakdown shows estimated prevented amount plus retained count for
  Dodge, Parry, and Miss.
- Attacks shows Physical Landed as meleeHitCount / (meleeHitCount + Dodge +
  Parry + Miss), and Magic Landed as magicHitCount / (magicHitCount + full
  resists). Partial resists remain landed magic events and are not double-counted.
- No combat math, persistence format, Archive/History retention, RC6, or
  DC2/Pass-2B behavior changed in this UI-only pass.

-------------------------------------------------------------------------------

MainTank v1.2.22 HIST64UI9 - History event counts
-------------------------------------------------------------------------------
- Avoidance is no longer a clickable/erased summary row; it remains a normal
  History Summary value.
- Added an Event Counts button at the bottom-right of the Magic column.
- Event Counts opens a focused History Counts page showing only retained
  Dodge, Parry, Miss, Melee Hits, and Magic Hits counters.
- Back from History Counts returns to that fight's History Summary.
- Overall "Flat DR" is renamed to "DR" and now equals the combined retained
  Physical DR + Physical Flat DR + Magic DR + Magic Flat DR total.
- Existing Physical DR and Magic DR rows remain their school-specific combined
  DR totals.
- No combat math, persistence, Archive/History retention, or DC2/Pass-2B logic
  changed in this UI-only pass.


-------------------------------------------------------------------------------

MainTank v1.2.21 HIST64UI8 - History drill-down
-------------------------------------------------------------------------------
- History Summary keeps Overall / Physical / Magic compact and removes the
  old EST. heading plus the D/P/M tuple footer.
- Flat DR and Absorbs now sit directly below the Overall totals.
- Avoidance is clickable on enriched History summaries.  Its drill-down page
  shows Dodge, Parry, and Miss estimated prevented values with retained counts.
- The drill-down also surfaces retained Melee/Magic hit counts, Absorbs, Full
  and Partial Blocks, and Full/Partial Resists without restoring event history.
- Back from History Details returns to that fight's History Summary; Back from
  History Summary returns to the History list.
- No combat math, RC6, DC2/Pass-2B, Archive retention, or persistence format
  was changed by this UI-only pass.

-------------------------------------------------------------------------------

MainTank v1.2.20 HIST64UI7 - History Summary retained counters
----------------------------------------------------------------
- Keeps the proven 300x231 four-section History Summary layout.
- Parenthetical counters are now shown beside countable retained aggregates:
    Full Block = estimated amount (full-block count)
    Full Resist = estimated amount (full-resist count)
    Partial Block = blocked amount (partial-block count)
    Partial Resists = resisted amount (partial-resist count)
- Avoidance is labeled Avoidance (D,P,M), with the retained Dodge, Parry, Miss
  tuple shown as (DodgeCount,ParryCount,MissCount) beneath the EST. block.
- Adds a tiny footer for retained Flat DR and Absorbs, with Absorb count in
  parentheses when the enriched History record contains it.
- Older sparse pre-SVH3 History summaries remain honest: missing counters are
  left blank rather than being fabricated from unavailable detailed events.
- No combat parser, RC6 math, persistence payload, History retention, Archive
  retention, SI2/DC2 restore, PvP safety, or storage behavior changes.

MainTank v1.2.19 HIST64UI6 - History Summary four-section cleanup
----------------------------------------------------------------
- Keeps History Summary at the standard MainTank 300x231 page size.
- Uses a balanced 4 + header + 4 layout on both sides:
    Overall: RAW, Taken, Prevented, Mitigation
    EST.: Armor, Avoidance, Full Block, Full Resist
    Physical: Physical RAW, Physical Taken, Physical DR, Partial Block
    Magic: Magic RAW, Magic Taken, Magic DR, Partial Resists
- Physical DR includes retained Physical Flat DR.
- Magic DR includes retained Magic Flat DR.
- Full Block uses the History fullBlockedEstimated aggregate.
- Full Resist uses resistedFullEstimated.
- Partial Block uses the retained partial-block aggregate.
- Partial Resists uses resistedPartial.
- No combat parser, RC6 math, persistence schema, History payload, Archive
  retention, SI2/DC2 restore, PvP safety, or storage behavior changes.

MainTank v1.2.18 HIST64UI4 - standard-size History Summary
----------------------------------------------------------------
- History Summary now uses the exact standard MainTank page size: 300x231.
- Removes the "Summary only - detailed Events and Timeline were discarded."
  footer to recover vertical room.
- Tightens History detail row spacing so all retained rows fit inside 300x231.
- Removes label/value vertical grid dividers; rows now read naturally with
  labels on the left and consistently right-aligned values on the same row.
- Keeps only the subtle center divider and faint horizontal row guides.
- Mini Mode remains the only intentional MainTank window-size exception.
- No combat, RC6 math, persistence, History data, Archive, SI2/DC2 restore,
  PvP safety, or storage changes.

MainTank v1.2.17 HIST64UI3 - History Summary alignment polish
----------------------------------------------------------------
- History Summary remains exactly 300x258; the window was not enlarged.
- Moves the summary report upward slightly so the final Resists row has clear
  separation from the footer.
- Adds subtle gold grid guides and dedicated right-aligned numeric columns.
- Keeps labels in their existing left positions while numbers now line up on
  clean right edges for easier scanning.
- Footer remains inside the current frame with more breathing room.
- No combat, RC6 math, persistence, retention, History payload, Archive,
  SI2/DC2 restore, PvP safety, or storage changes.

MainTank v1.2.16 HIST64UI2 - History/UI consistency cleanup
----------------------------------------------------------------
- Final release-facing storage model is strictly:
    8 MainTank detailed -> 8 Archive detailed -> 64 History summaries.
- History and History Summary now use MainTank's established UI styling pipeline:
  native pfUI styling when pfUI is present; sleek grey Blizzard-compatible
  styling for Blizzard UI and every non-pfUI setup.
- History Summary uses a standard Back button instead of the old arrow-label
  control, with BACK4-style title positioning after Back visibility is finalized.
- History Summary uses a slightly taller 300x258 detail page and reorganized
  two-column content so all retained fields stay inside the window.
- All styled MainTank close controls now use the same red X as the Main page and
  close the entire MainTank UI instead of navigating to another page.
- History participates in the same safe dragging/lock system as other pages.
- No combat parser, RC6 math, History payload, persistence schema, retention
  rules, SI2/DC2 restore, PvP safety, or Archive behavior changed.

HIST64UI1 - HISTORY 64 SUMMARY BROWSER - 2026-08-24
--------------------------------------------------
- Revives the useful HIST2 History Browser concept without reviving the old MT+BA+GA+HA+HL storage architecture.
- Final browser scope is History summaries only: Recent and Archive are not duplicated in this page.
- Main navigation is now Timeline | Compare | History | Pie Chart and Biggest | Export | Boss | Details.
- History shows up to 64 summary-only records with BOSS / 50K+ / MINOR / PvP tags, RAW and mitigation percent.
- Clicking a History row opens a read-only aggregate summary with RAW, Taken, Prevented, Armor, Avoidance, Flat DR, Full/Partial Block, Absorbs, Physical and Magic breakdown totals, and Resists when present.
- /mt history opens the browser; /mt history N opens summary N directly.
- History never reconstructs Events, Timeline, Pie, Details, or Restore data. It honestly displays only what the lightweight summary retained.
- No new persistence tier. Storage remains 8 Recent detailed + 8 Archive detailed + 64 History summaries.
- No combat capture/math, RC6 attribution, PvP quarantine, SVH persistence format, or SI2/DC2/Pass-2B restore changes.

SVH3 / HISTORY64 - 2026-08-24
--------------------------------
- Stress-test checkpoint validated the three-file conveyor at 8 Recent + 8 Archive + 2 History after 18 heavy 11-mob Scarlet pulls.
- Increased MainTank_History retention from 8 to 64 summary-only combats. Recent and Archive detailed caps remain frozen at 8 each.
- Enriched each NEW History summary with final aggregate mitigation totals: armor reduction, avoidance estimates, blocks/full-block estimate, flat DR, physical/magic DR, absorbs, partial/full resists, physical/magic RAW and taken, school-specific flat DR/block/absorb totals, and key event counters.
- History remains summary-only: no event arrays, timelines, context pools, aura graphs, or per-second data are persisted.
- Existing older sparse History summaries remain valid; they cannot be retroactively enriched after their detailed fight payload has already been evicted.
- Storage/release diagnostics now validate 8 Recent + 8 Archive + 64 History = 80 bounded records.
- Combat math, RC6 attribution, PvP quarantine, SI2/DC2/Pass-2B restore ordering, and the proven SVH2 detailed Archive format are unchanged.

MainTank v1.2.13 SVH2 - THREE-FILE STORAGE + BOSS PROFILE PERSISTENCE
- Restores the proven physical SavedVariables isolation lesson from MitigationTracker FR1P while keeping the current MainTank codebase and 8/8/8 policy.
- Distribution is again three addon folders: MainTank, MainTank_Archive, and MainTank_History. The companions are tiny LoadOnDemand storage backends; MainTank remains the only interactive UI addon.
- Physical data ownership: MainTank.lua = newest 8 detailed Recent fights; MainTank_Archive.lua = 8 priority detailed Archive fights; MainTank_History.lua = 8 lightweight summaries.
- Archive priority remains Boss > 50K+ RAW > Minor > PvP. Within equal priority, newer fights win.
- Fixes the v1.2.x single-folder regression where archived detailed fights remained inside MainTankDB and caused the core SavedVariables file to jump sharply after Recent reached 8/8.
- Fixes the second archive-size regression: the consolidated Archive path expanded SVH1 numeric contexts back into old fight.contextSnapshots graphs. SVH2 keeps archive contexts fight-local, numeric, mitigation-only, and deduplicated. Pure PvP archive fights persist no RC6 context graph.
- One-time migration moves existing profile.archiveFights and profile.historySummaries out of MainTankDB into their new physical companion files, then deletes those detailed aliases from the core profile.
- Boss Profile persistence is hardened by a final late SyncPersistentData/RestorePersistentData coordinator. bossHistory and bossProfileIndex are explicitly preserved across the historical wrapper chain/profile rebinds so saved ?? boss profiles do not disappear across logout/login.
- This build intentionally does NOT change combat parsing, RC6 mitigation math, SI2/DC2/Pass-2B Current/Overall restore ordering, or the proven PvP accounting rules.

Historical persistence lesson confirmed by FR1P
-----------------------------------------------
- MitigationTracker FR1P already documented that multiple SavedVariables globals inside one addon still serialize into one physical WTF file. Separate LoadOnDemand companion addons were introduced specifically to isolate old detailed fights into separate files and reduce the chance that a damaged archive blocks the core addon.
- Later MainTank single-folder consolidation improved installation presentation but reunited Recent + Archive + History inside MainTankDB. Once SVH1 made Recent compact, the older archive serializer became visible as the new dominant bloat source.
- Architectural rule going forward: keep storage policy and combat math modular, but avoid stacking persistence wrappers that silently change ownership/serialization formats. A late persistence coordinator must protect durable side stores such as Boss Profiles across profile rebinding.

MainTank v1.2.12 - SVH1 SAVEDVARIABLES HARDENING (2026-08-23)

Scarlet 11-mob stress testing exposed two separate facts: the active MainTank
SavedVariables file was still growing by roughly 1.2 MB per detailed fight, and
a 3-fight specimen later suffered a real binary overwrite in the middle of the
Lua file. SVH1 addresses the MainTank-controlled part of that risk: disk size and
persistence redundancy. It does not claim that addon Lua can prevent an external
filesystem/storage overwrite.

SVH1 disk contract:
- Finalized fight raw/taken/armor/block/resist/absorb/Flat DR/%DR values remain
  authoritative and unchanged.
- Before PLAYER_LOGOUT serialization, every persisted event is re-dieted. This
  is necessary because Pass-2B display guards intentionally restore
  rc6MathVersion in RAM after the one-time EndCombat diet; the marker remains
  runtime-only and must not leak back onto disk.
- Long RC6 contextID strings are no longer repeated on every finalized event.
  Persisted events use a small numeric event.context index.
- profile.compactContextPool stores one deduplicated mitigation-relevant snapshot
  per unique historical mitigation state. Irrelevant unknown/context-only aura
  entries, texture paths, tooltip scaffolding, and per-aura slot indexes are not
  persisted in historical snapshots.
- profile.contextSnapshotPool and profile.mitigationContexts are cleared at the
  final disk-preparation boundary after their required contexts have been copied
  into compactContextPool. They are rebuilt naturally for live runtime contexts
  after login.
- On load, numeric compact snapshots are reattached BEFORE the existing Core
  restore chain. The frozen SI2/DC2 rule is preserved: pre-Core restore only
  reattaches historical context data; Current/Overall runtime reconstruction
  remains in the proven later Pass-2B path.
- Pure-PvP PVPSAFETY6/7 behavior remains intact. Mixed PvE fights retain the
  mitigation-relevant snapshots required for boss/trash mechanics and historical
  DR attribution.

SVH1 intentionally does NOT change combat parsing, mitigation equations, fight
limits, Current/Overall authority, archive/history limits, or DC2 startup order.


-------------------------------------------------------------------------------

MainTank v1.2.12 SVH1
- Extends the proven Pass-2B HF5 authoritative-finalized-fight contract from completed Current to every numbered saved-fight view (/mt fight N).
- Fixes repeated /mt fight N selections changing RAW/Physical RAW merely by viewing the same finalized fight.
- Fixes /mt fight 1 disagreeing with completed Current when both refer to the same newest finalized fight.
- Numbered fight headline data now starts from authoritative fight.data and never rebuilds RAW/Taken/Armor/Avoidance/Block/Resist/Absorb totals through the legacy RC6 display path.
- Numbered fight Timeline uses the saved authoritative fight.timeline.
- Numbered fight Details/Pie event readers receive runtime frozen event copies so legacy display helpers cannot mutate authoritative fight.events.
- Live combat parsing/math, Overall authoritative restore, SI2/DC2 startup ordering, PvP safety/quarantine, persistence limits, and Pie layout are unchanged.

MainTank v1.2.10 PIEBREAKDOWNPP2
- PixelPerfect Pie footer follow-up to PIEBREAKDOWNPP1.
- Pie footer position is BOTTOMLEFT 15,44 in both layout paths.
- Footer display text shortened from "Total Prevented:" to "Prevented:".
- No combat parser, mitigation math, persistence, SI2/DC2 restore, or PvP safety changes.

MainTank v1.2.9 PIEBREAKDOWNPP1 (PixelPerfect1)
- Pixel-perfect Pie legend geometry pass.
- RAW, PHYSICAL, and MAGIC all use identical 14px legend rows and 14px spacing.
- All Pie legends start at TOPLEFT 134, -54; no compact/non-compact row-height switch remains.
- Removes the 1px visual shift caused by 13px MAGIC rows vs 15px RAW/PHYSICAL rows.
- Keeps the existing pie-disc and footer positions.
- No combat parser, RC6 math, persistence, SI2/DC2 restore, or PvP safety changes.

MainTank v1.2.8 PIEBREAKDOWN5
- Pie layout-only follow-up to PIEBREAKDOWN4.
- RAW, PHYSICAL, and MAGIC use the same legend start below the View selector.
- MAGIC retains compact spacing for its legitimate 11-row worst case.
- Keeps the PIEBREAKDOWN4 pie-disc position and fixed footer.
- No combat parser, RC6 math, persistence, SI2/DC2 restore, or PvP safety changes.

MainTank v1.2.7 PIEBREAKDOWN4 - PIE VERTICAL LAYOUT HARDENING

PIEBREAKDOWN4 (v1.2.7)
------------------------
- Pie presentation/layout-only patch on top of PIEBREAKDOWN3.
- Moves every RAW / PHYSICAL / MAGIC legend stack upward by 24px so the
  legitimate worst-case 11-row Magic legend remains clear of Total Prevented
  and the Details hint at the bottom of the fixed-size page.
- Nudges the pie disc upward by 8px, which is the safe amount available below
  the unchanged View selector without visual overlap.
- Header/title, View selector, footer, combat parser, RC6 mitigation math,
  persistence, SI2/DC2 restore ordering, and SavedVariables behavior unchanged.


- Fixes Physical/Magic Absorb slices disappearing after /reload or relog when
  compact persisted aggregates retain total Absorbs but not the helper school split.
- Recovers only the Physical/Magic Absorb presentation split from authoritative
  saved events (event.absorb + event.school); combat parsing and totals are unchanged.
- Keeps Physical Absorb Details limited to Physical-school events and Magic Absorb
  Details limited to non-Physical schools.
- Dynamically compacts the Pie legend only for 10-11 row views so the worst-case
  Magic Pie fits inside the existing 231px MainTank page without cropping.
- Normal 1-9 row Pie views retain the roomier existing spacing.

v1.2.5 PIEBREAKDOWN2 - SPECIALIZED PIE RESTORE / ABSORB FILTER FIX
===============================================================================

Release-finalization UI fix only. Combat parsing, mitigation equations, RC6 event
attribution, SI2/DC2 restore ordering and persistence limits are unchanged.

PHYSICAL FULL BLOCK RESTORE
---------------------------
Historical/Overall data can retain the authoritative aggregate Full Blocks total
while the optional school-split physicalFullBlockedEstimated helper is absent or
zero after compact restore. This reproduced the older FR1N class of bug where the
main Physical page correctly showed Full Blocks but the Physical Pie omitted the
slice.

PIEBREAKDOWN2 does not recalculate combat. If the Physical Pie is missing a Full
Block entry, UI/Pie.lua sums only already-saved events with:

    kind == FullBlock
    school == Physical
    event.block > 0

and inserts that exact value before Partial Block. The authoritative aggregate
totals are not modified.

SCHOOL-SCOPED ABSORB DETAILS
----------------------------
RC6 already stores absorbs on the consuming incoming event, so the Pie totals were
already correct by school. Example from Scarlet stress testing:

    RAW Absorbs      891
    Physical Absorbs 309
    Magic Absorbs    582

    309 + 582 = 891

The remaining bug was only Details filtering: both specialized Absorb slices used
the generic ABSORB filter, so clicking Physical Absorbs could still list Arcane
Bolt events and clicking Magic Absorbs could list Melee events. PIEBREAKDOWN2 adds
PHYSICAL_ABSORB and MAGIC_ABSORB filters. Classification follows event.school, not
the enemy's class/type: a Scarlet Enchanter's Melee is Physical, while its Arcane
Bolt is Magic/Arcane.

FR1N HISTORY CONFIRMED
----------------------
The earlier README documents the same important release lesson: a correct main-page
Full Block value can exist while Pie presentation hides it. PIEBREAKDOWN2 keeps the
creation-order-independent legend-capacity protection and fixes the restored-data
source mismatch without touching the parser.

MainTank v1.2.4 PIEBREAKDOWN1
===============================

Release hardening UI fix only; combat parsing and mitigation math are unchanged.

- Restores RC6's intended Physical Pie categories: Full Block, Partial Block,
  and Physical Absorbs can all appear together.
- Restores Magic Absorbs to the Magic Pie.
- RAW Absorbs remains the combined absorbed total.
- Specialized absorb attribution comes from the saved incoming event school, so
  existing detailed fights can be reopened after upgrading and viewed with the
  corrected Physical/Magic breakdown.
- Expands the late-loaded pie legend to 11 rows so the largest legitimate Magic
  view cannot lose a category.
- Does not modify Engine combat parsing, RC6 mitigation calculations, SI2/DC2
  restore ordering, or persistence limits.

MainTank v1.2.3 RELEASEGUARD1
================================

Release-hardening / stress-test candidate built directly from v1.2.2 PVPSAFETY6.

Safety changes only:
- Keeps the proven SI2/DC2 / Pass-2B Current/Overall restore architecture unchanged.
- Keeps all mitigation/combat math unchanged.
- Extends PVPSAFETY6 context quarantine to every MainTankDB character profile and to detailed Archive fights, so stale pure-PvP RC6 context graphs cannot remain hidden in the shared SavedVariables file.
- Pure-PvP finalized events retain their authoritative mitigation totals but persist no contextID/context/rc6ContextSnapshot/contextSnapshots graphs.
- PvE and mixed-PvE fights retain contexts they actually reference, including player-attributed PvE mechanics.
- Adds /mt releasecheck (alias /mt stresscheck), a read-only release diagnostic for 8/8/8 bounds, detailed event counts, context-pool counts, and pure-PvP persistence quarantine.

Release test recommendation:
- Run /mt releasecheck before testing.
- Perform repeated large multi-mob pulls and normal boss/trash fights.
- Log out completely and record MainTank.lua SavedVariables file size.
- Log back in and run /mt releasecheck again.
- Perform a controlled PvP retaliation test, log out, log back in, then run /mt releasecheck again.
- Do not ship if the command reports any pure-PvP context references or bounded-storage failure.

PVPSAFETY6 (2026-08-22)
- New evidence: Khanvict still froze with a fully coherent pure-PvP DB (Overall 1404 RAW/39 hits exactly matched finalized fights 1404 RAW/39 hits).
- Therefore Overall-vs-fight mismatch is not required for the 50% freeze.
- Pure PvP finalized events now discard contextID/rc6ContextSnapshot persistence; their finalized mitigation numbers remain authoritative.
- contextSnapshotPool/mitigationContexts are pruned to IDs still referenced by PvE fights only.
- The quarantine runs at ADDON_LOADED even when accounting totals are coherent.
- Mixed PvE fights keep PvE context snapshots, preserving boss mechanics/Mind Control handling.
- SI2/DC2/Pass-2B restore ordering is unchanged.


===============================================================================

MainTank v1.2.2 PVPSAFETY6
===============================

PvP reflect persistence follow-up:
- Fixes the repeat-freeze case where PVPSAFETY4 could recover Khanvict once, but a NEW Blessing of Sanctuary retaliation test could poison the next login again.
- The preflight consistency repair now runs on every login; its version marker is diagnostic only and no longer disables future scans.
- If a synthetic PvP retaliation/proc tail is still open when SavedVariables sync begins (including PLAYER_LOGOUT), MainTank finalizes that tail before writing the profile.
- This prevents late reflect/proc hits from being written into Current/Overall without a corresponding finalized fight.
- Confirmed PvP remains excluded from learning caches.
- SI2/DC2 / Pass-2B restore architecture is unchanged.

v1.2.2 PVPSAFETY4 - EARLY PREFLIGHT / REFLECT DB HARDENING
-----------------------------------------------------------
- Re-runs the bounded pure-PvP reflect recovery at ADDON_LOADED, before
  VARIABLES_LOADED invokes MainTank Initialize/Migrate/Restore.
- For the exact all-PvP, no-archive, Overall>finalized-fights mismatch shape,
  quarantines transient/runtime learning/context fields and rebuilds Current
  shell from the newest finalized fight before the mature restore chain sees it.
- Finalized fights remain authoritative and are preserved.
- SI2/DC2 Pass-2B restore architecture is unchanged.

MainTank v1.2.2 - PVPSAFETY3
----------------------------
Khanvict Blessing of Sanctuary reflect / 50% loading-screen hardening.

Observed failure specimen
-------------------------
A pure PvP test against a Paladin produced repeated 36 Holy Blessing of Sanctuary
retaliation hits.  PvP classification worked, but four retaliation hits landed
after a combat boundary and were recorded into Overall without belonging to a
finalized fight.  The same specimen also proved that PvP could still leak into
contextMemory and globalAbilitySchoolMemory even though session/weapon learning
had already been isolated.

PVPSAFETY3 rules
----------------
- Confirmed PvP still remains fully recordable and remains the lowest retention
  priority: Boss > 50K+ RAW PvE > under-50K RAW PvE > PvP.
- [PvP] / [PvE] fight labeling remains unchanged.  Mixed boss/trash + player
  encounters stay [PvE] for Mind Control, Conflagration-style propagation and
  similar encounter mechanics.
- Confirmed PvP cannot learn contextMemory, encounter/session hit ranges,
  target UnitDamage weapon ranges, per-source ability schools, or the global
  cross-source ability-school cache.
- Historical/display school repair also refuses to seed global school memory
  from events explicitly stamped sourceType=PVP.
- PvP retaliation/proc damage that arrives while PLAYER_REGEN says the player is
  out of combat now opens a short synthetic PvP combat.  Nearby ticks coalesce
  and are finalized after 2 seconds of inactivity instead of mutating Overall
  as orphan, non-fight data.
- If real combat begins during that short synthetic window, MainTank converts
  the synthetic tail into the real combat without resetting the captured hits.
- Normal logout explicitly finalizes any open synthetic PvP tail before FR1K
  prepares SavedVariables, so a clean logout cannot strand those events.
- A narrow pre-Initialize recovery recognizes the exact affected shape from the
  PVPSAFETY2 specimen: only finalized PvP fights, no Archive/History records,
  and Overall RAW greater than finalized-fight RAW.  It rebuilds only that pure
  PvP Overall aggregate/timeline from the preserved finalized fights before the
  normal migration/restore chain runs.
- The recovery also scrubs already-persisted PvP-only learning entries while
  preserving the finalized PvP fights themselves.
- SI2/DC2 pre-Core restore and Pass-2B Current/Overall architecture is unchanged.
  PVPSAFETY3 does not move normal Current/Overall rebuilding into early restore.

Recommended regression test
---------------------------
1. Login on the previously affected Khanvict SavedVariables with PVPSAFETY3.
2. Confirm the character reaches the world and MainTank prints the one-time
   PVPSAFETY3 reconciliation notice if the bad pure-PvP profile was detected.
3. Shoot a Paladin with Blessing of Sanctuary repeatedly, including pauses long
   enough to cross combat boundaries.
4. /mt fights should retain [PvP] fights; /mt memory must not learn the player.
5. Logout/relogin.  No 50% loading-screen stall should occur.
6. Re-test ordinary PvE, mixed PvE + player-attributed mechanics, and Arcane Shot
   magic+Block accounting from MAGICBLOCK1.

MainTank v1.2.2 - MAGICBLOCK1
--------------------------------
- Magic-school damage can now retain observed shield Block as an independent mitigation component.
- A blocked Arcane/Fire/Frost/Nature/Shadow/Holy hit remains Magic; Block no longer implies Physical.
- Magic Pie now includes Block alongside Flat DR, Magic DR, and resistance-school prevention.
- Physical Pie Block values are restricted to Physical events, preventing magic blocks from inflating Physical prevention.
- Magic Prevented / mitigation percentage now includes observed magic Block.
- Pie Block detail filters are school-aware.
- Existing event math already avoided armor reconstruction for non-Physical schools; this patch preserves that rule.
- No changes to SI2/DC2 startup restore architecture or PvP classification/learning safety.

PvP/PvE classification safety (v1.2.1 PVPSAFETY2)
---------------------------------------------------
- MainTank retains PvP fights instead of deleting them.
- /mt fights labels pure player/player-pet encounters [PvP].
- Mixed encounters containing confirmed NPC/boss damage remain [PvE], so boss mechanics involving player attribution (Mind Control, Conflagration-style splash/propagation, etc.) remain part of the PvE fight.
- Archive retention order is Boss > 50K+ RAW PvE > under-50K RAW PvE > PvP. PvP remains lowest priority regardless of RAW total.
- Confirmed PvP sources never populate UnitDamage target weapon-range memory, encounter/session hit-range learning, pending avoidance estimates, or learned ability-school memory.
- Targeted hostile player-controlled pets/guardians are remembered as PvP sources when the 1.12 client exposes UnitPlayerControlled. Unknown sources are kept conservatively rather than discarded.
- SI2/DC2 RestorePersistentData and Pass-2B Current/Overall startup architecture is unchanged.

MAIN TANK v1.2.0 - SINGLE-FOLDER CONSOLIDATION / FINALIZATION
================================================================================

Canonical baseline
------------------
This release is built directly from MainTank_v1.1.0_FR2_SI2, before the later
History experiments. The proven SI2/DC2 startup and Pass-2B Current/Overall
restore architecture is preserved.

One-folder rule
---------------
MainTank now ships as exactly one addon folder:

  MainTank/

Multiple Lua modules remain inside that folder, but the old
MainTank_GeneralArchiveData and MainTank_BossArchiveData companion addon folders
are no longer part of the release.

Vanilla 1.12.1 LoadOnDemand SavedVariables isolation requires separate addon
folders, so a true one-folder release necessarily stores all persistent MainTank
records under MainTankDB. To keep that sustainable, persistence is hard-bounded
and only 16 fights retain full event detail.

Frozen 24-combat persistence model
----------------------------------
Exactly three logical layers are retained:

  Recent   8 detailed fights
  Archive  8 detailed fights
  History  64 enriched lightweight summaries

Maximum combat records per character: 24.
Maximum detailed event-bearing fights: 16.

Archive retention priority is:

  Boss > 50K+ RAW > Minor

When Archive is full, a higher/equal-priority newer fight can replace the
oldest fight at the lowest available priority. A displaced or non-admitted
fight is reduced to a lightweight History summary. History keeps only its eight
newest summaries.

No BA/GA/HA/HL multi-tier storage architecture is used. Do not add more
persistence layers unless future real raid testing clearly proves a need.

DC2 / SI2 safety boundary
-------------------------
The consolidation module deliberately overrides archive/storage plumbing only.
It does NOT rebuild Current or Overall during early restore.

The DC2 rule remains frozen:
  - pre-Core restore may reattach persistent snapshot/context data;
  - it must not rebuild or alias live Current/Overall runtime state;
  - the later Pass-2B chain remains authoritative for Current/Overall binding.

Legacy archive migration
------------------------
The v1.2.0 release itself contains only MainTank. For users upgrading from the
old three-folder FR2 layout, the new module can perform a one-time import if the
old MainTank_GeneralArchiveData and MainTank_BossArchiveData folders are still
installed for the first login after upgrading. Imported fights are immediately
re-ranked into the bounded 8 Archive + 8 History model. After the import message
appears, the old companion folders can be deleted permanently.

If those old companion folders are deleted before the first v1.2.0 login, WoW
1.12.1 cannot read their separate SavedVariables files from inside MainTank;
that is a client/addon-loading limitation rather than a MainTank data-format
limitation.

Storage diagnostics
-------------------
  /mt archive
      Shows Recent / Archive / History counts and Archive retention classes.

  /mt archive check
      Validates the one-folder 8/8/8 bounds and archived context references.

  /mt archive restore N
      Moves Archive fight N back into Recent without duplicating the fight,
      preserving the hard 24-record ceiling.

  /mt cleararchives confirm
      Clears Archive and History for the active character.

Finalization rule
-----------------
Treat MainTank v1.2.0 as the single canonical successor to SI2. Do not create
parallel user-facing MainTank branches. Temporary debug builds are acceptable
only for isolating a real bug and must be merged back into the canonical line.

FR2 STARTUP CLEANUP HOTFIX - NIL-SAFE FORMAT MARKERS
----------------------------------------------------
Startup-cleanup guards must treat missing per-profile format markers as legacy
state, not compare nil numerically. This matters for alternate characters,
fresh profiles, and profiles that have not yet received archiveFormatVersion.

Fixed both startup guards to use:
  (tonumber(profile.archiveFormatVersion) or 0) >= 5

Affected guards:
- Core/Engine.lua RC6 snapshot-backfill fast path.
- Core/SchoolMemory.lua historical school-repair fast path.

Rule: optimization/version fast paths must always fail safely back to the
legacy/correctness path when an optional persisted marker is missing.


================================================================================

FR2 STARTUP/RESTORE PERFORMANCE CLEANUP - AUGUST 15 2026
================================================================================

Benchmark basis
---------------
The controlled heavy-pull benchmark used for this pass is:
  MainTank: 8 large ~11-enemy fights
  General Archive: 2 additional large fights
  Total: 10 fights

Phone stopwatch progression before this cleanup:
  8 heavy live fights                 4.65s
  General Archive beginning to fill   4.76s
  8 live + 2 General archived         4.86s

The near-flat result as General Archive grows is evidence that LoadOnDemand
archive isolation is working. This pass therefore targets redundant work inside
the 8-fight MainTank startup/restore path.

Safety boundary
---------------
DC2 ordering is NOT changed.

FR1K pre-Core restore still only reattaches compact context snapshots.
It does NOT rebuild/alias Current or Overall there. Pass-2B remains the later
authoritative Current/Overall restore phase.

Safe startup work removed
-------------------------
1. MigrateDatabase returns immediately when MainTankDB is already schema 11.
   Legacy/future schema changes still use the original migration path.

2. Saved-fight metadata is regenerated from events only when label,
   primaryEnemy or enemyCount is actually missing.

3. RC6s snapshot backfill is skipped for archiveFormatVersion >= 5 profiles,
   because FR1K already rehydrated the compact contextSnapshotPool before Core.

4. FR1L Unknown-school historical repair is treated as a migration rather than
   an every-login scan. Existing format-5 FR2 profiles are marked complete.

5. Pass-2B does not repeat idempotent DR repair across every saved fight after
   pass2BTimelineDRVersion confirms the authoritative events were already fixed.

6. CURRENT's historical Pie/headline data binds directly to the finalized
   saved fight.data aggregate. Compact event freezing for Details/Inspector is
   deferred until GetDisplayEvents is actually requested.

Not changed in this pass
------------------------
- Overall event reconstruction architecture
- Overall authoritative aggregate/timeline rules
- DC2 pre-Core restore ordering
- combat parser
- mitigation equations
- archive data format
- General/Boss routing
- eight-fight live cap

This is intentional. First measure the low-risk redundant-pass cleanup. If the
remaining startup time is already ~2-3 seconds, stop rather than destabilize
Current/Overall for marginal gains.

Diagnostic command
------------------
  /mt startup

Example:
  MainTank: FR2 startup - migrate 0.001s | restore 2.100s | UI 0.300s |
            measured addon work 2.401s.

The phone stopwatch still matters because it captures the visible freeze.
The command isolates MainTank's own Initialize phases so future work can target
the correct subsystem.

Test procedure
--------------
1. Preserve the current 10-fight MT + GA benchmark files.
2. Install this complete FR2 release over the prior FR2 folders.
3. Cold login using the SAME SavedVariables.
4. Verify Current/Overall/Pie/Timeline before timing conclusions.
5. Run /mt startup and record the phase numbers.
6. Cold login a second time and time with the phone.
7. Target: ~2-3 seconds visible freeze.
8. If already in that range, STOP optimization before touching the fragile
   Current/Overall restore architecture.

MAINTANK v1.1.0 FR2 - ONE CANONICAL BUILD / ARCHIVE STARTUP CLEANUP
================================================================================

FR2 is the single canonical successor to:
  MainTank v1.0.0 FR1X-HF5-BACK4-DC2-GA2

ONE-BUILD PROJECT RULE
----------------------
MainTank has ONE canonical user-facing build line. Patch labels such as DC2,
GA2, BACK4 and FR2 describe checkpoints in that one lineage; they are not
parallel versions for the player to maintain.

Temporary experimental forks are acceptable only while isolating a deep bug
(such as the preserved 2.9 MB / ~50% login-freeze investigation). As soon as
the root cause is known, the proven fix must be merged back into the canonical
MainTank build. User-facing releases must not leave competing MainTank versions.

FR2 LOAD-ON-DEMAND ARCHIVE CONTRACT
-----------------------------------
The distributed release contains exactly these coordinated addon folders:

  MainTank
  MainTank_GeneralArchiveData
  MainTank_BossArchiveData

Both archive data addons declare:

  ## LoadOnDemand: 1

They remain installed/enabled so MainTank can call LoadAddOn() when needed, but
their SavedVariables are NOT loaded as part of ordinary MainTank startup.

MainTank's archive loader is invoked only by explicit archive work:
- a live fight actually rolls beyond the 8-fight Core window;
- the user opens/restores an archived fight;
- the user explicitly clears archive data;
- the user explicitly runs an archive diagnostic.

Merely logging in, restoring Current/Overall, or printing the manifest does not
require either archive SavedVariables file.

DC2 STARTUP RULE - PERMANENT
----------------------------
The successful DC2 fix is intentionally preserved unchanged in FR2.

FR1K pre-Core restore has ONE job:
  reattach compacted context snapshots to authoritative persisted event streams.

It MUST NOT:
- alias a completed fight into live Current before Core restore;
- rebuild Overall events before Core restore;
- load General Archive;
- load Boss Archive;
- scan/repair archived fights;
- run archive migrations merely because the addon starts.

Current and Overall runtime reconstruction belongs to the later proven Pass-2B
restore chain after Core restoration has safely completed.

GENERAL / BOSS ARCHIVE PARITY
-----------------------------
FR2 confirms that General and Boss are NOT separate archive implementations.

Both destinations use the SAME Archive.lua flow:

  ArchiveFight()
    -> classify boss/general
    -> SelectArchive(kind)
    -> FR1K_CompactFight()
         -> FR1X_GA_CopyContexts()
         -> FR1X_GA2_FinalizeArchiveDR()
    -> assign archiveKind/archiveID
    -> insert into the selected archive DB

Therefore Boss Archive automatically receives the same:
- self-contained contextSnapshots handoff;
- persisted event flatDR;
- persisted event physicalDR;
- persisted event magicDR;
- aggregate flatDR;
- aggregate physicalDR;
- aggregate magicDR;
- aggregate physicalFlatDR;
- aggregate magicFlatDR;
- archive DR generation marker;
- rehydrate behavior.

Only routing/destination policy differs. Do not create a separate Boss compacting
or DR-finalization implementation later; that would reintroduce schema drift.

HISTORICAL DR RULE
------------------
Archived DR attribution is historical data. Opening an archive must never
recalculate old DR from the player's CURRENT talents, buffs or gear.

GA2/FR2 persists finalized attribution at live -> archive rollover. Legacy
pre-GA2 archive records that lacked DR are intentionally left legacy rather than
being silently rewritten just because the archive was opened.

MANUAL ARCHIVE PARITY CHECK
---------------------------
FR2 adds:

  /mt archive check
  /mt archive check all
  /mt archive check general
  /mt archive check boss

The checker is MANUAL ONLY. It does not run at login and does not load archives
until the user explicitly enters the command.

For GA2/FR2 archive records it validates:
- per-event flatDR / physicalDR / magicDR presence;
- aggregate flatDR / physicalDR / magicDR presence;
- aggregate physicalFlatDR / magicFlatDR presence;
- fight-local context references resolve inside contextSnapshots.

This is especially useful for the first real post-FR2 raid Boss Archive test.

FR2 RELEASE SAFETY / NO-TEST-DAY POLICY
---------------------------------------
Because FR2 was assembled while immediate in-game testing was unavailable, the
release deliberately avoids speculative changes to the proven combat parser,
mitigation equations, DC2 pre-Core restore ordering, Pass-2B Current/Overall
reconstruction, or GA2 DR math.

FR2 is a hardening/packaging release:
- preserve the known-good restored 2.9 MB data architecture;
- ship the missing companion archive addon folders in the same release;
- ensure both archives are LoadOnDemand;
- document and verify the already-shared General/Boss write path;
- add explicit/manual diagnostics rather than automatic startup scans.

FIRST FR2 TEST ORDER
--------------------
1. Back up WTF\Account\...\SavedVariables\MainTank.lua and both archive SV files.
2. Install all three FR2 addon folders together.
3. Cold-login with the preserved large MainTank DB.
4. Confirm login passes the former ~50% freeze point.
5. Confirm Current and Overall headline/Pie/Timeline values remain authoritative.
6. Confirm General/Boss archive addons remain dormant until archive access.
7. Run:
       /mt archive check general
   only when ready to explicitly load/audit General Archive.
8. On the next raid, after a real skull-level boss rolls into Boss Archive, run:
       /mt archive check boss
9. Compare Boss archived Pie/Timeline/Details DR against the live fight before
   making any further archive-format changes.



================================================================================

MainTank v1.1.0 FR2
=====================

MainTank (originally developed as MitigationTracker) is a Vanilla World of Warcraft 1.12.1 / VanillaPlus mitigation-analysis addon built to answer a deceptively difficult question:

    How much incoming damage did the tank actually stop, and how was it stopped?

The addon grew from a small incoming-damage meter into an event-based combat-analysis tool covering raw incoming damage, armor, avoidance, blocking, absorbs, spell resistance, flat damage reduction, percentage damage reduction, saved fights, timelines, pie charts, event inspection, boss analysis, and tank comparison/sync.

This file records the development path from the first v0.1.0 build through v1.0.0 FR1a. Some experimental letter builds were short-lived development checkpoints; where several existed only to diagnose one client-specific problem, they are grouped with the feature they ultimately produced.

FR1X-HF5-BACK4-DC2-GA2 — GENERAL ARCHIVE DR PERSISTENCE
---------------------------------------------------------
Live archive validation after DC2 proved that General Archive itself was working:
a ninth fight beyond MainTank's eight-fight Core window remained addressable after
a cold restart, with intact headline raw/taken/stopped totals, Armor/Avoidance/
Block/Resist Pie data, multi-page Timeline data, and enemy count/title metadata.

The remaining archive-specific regression was narrower: the archived fight lost
Flat DR, Physical DR and Magic DR in Pie/Timeline while Current and Overall still
showed those categories after the same cold restart.

Root cause / ordering lesson:
- Archive rollover may occur before later Pass-2B EndCombat wrappers refresh the
  completed fight's historical DR presentation fields.
- Therefore the copy transferred to General Archive can be made from authoritative
  raw/taken/armor/block/resist/absorb data while its per-event DR attribution is
  still zeroed/incomplete.
- Current/Overall later repair themselves in Core RAM, but the already-copied
  archive record never receives that later correction.

GA2 archive contract:
- At the live -> archive boundary, GA1-SAFE first copies every referenced context
  snapshot into fight.contextSnapshots so the outgoing fight is self-contained.
- GA2 then finalizes DR ONLY inside the outgoing archive copy. It preserves any
  already-nonzero Flat/Physical/Magic DR; otherwise it derives only the residual
  already proven by final event math:
      residual = raw - taken - armor - block - resist - absorb
- Flat DR is bounded by the saved context model, residual, and the one-damage
  floor. Any remaining residual is assigned to Physical DR or Magic DR only when
  the saved context actually contained percentage DR for that school.
- The five aggregate presentation fields are then persisted in fight.data:
  flatDR, physicalDR, magicDR, physicalFlatDR, magicFlatDR.
- Per-event attribution is persisted because Pie and Timeline DR are reconstructed
  from archived events; Timeline buckets themselves remain authoritative for
  raw/taken/armor/block/resist/absorb and do not need duplicate DR payloads.
- On archive rehydrate, events are marked rc6MathVersion=11 in RAM so display-time
  legacy estimators cannot erase the archived attribution. The marker is not
  persisted in the archive copy.

Backward-compatibility rule:
- NEVER synthesize DR merely because an old archive is opened. Existing pre-GA2
  archives with zero/nil DR stay zero/nil. This intentionally preserves the old
  archived Scarlet Enchanter +10 specimen as evidence of the previous format.
- Only fights archived after GA2 receive the new DR persistence contract.

GA2 regression test:
1. Keep the existing old archived Fight #9 unchanged; it may correctly remain
   without DR attribution.
2. Create a new DR-bearing fight while Core contains eight fights, forcing one
   finalized fight through General Archive rollover under GA2.
3. Before/after rollover, verify the same fight's raw/taken/stopped totals do not
   move and enemy count/title remain identical.
4. Cold restart (not just /reload), open the newly archived fight, and require
   RAW/PHYSICAL/MAGIC Pie to retain relevant Flat/Physical/Magic DR.
5. Hover Timeline bars across both time pages and require matching DR attribution.
6. Verify Current and Overall totals/DR remain unchanged by the archive patch.
7. After General is proven, audit Boss Archive against this same contract rather
   than implementing a separate DR persistence scheme.


================================================================================

FR1X-HF5-BACK4-DC2 — FR1K startup restore-order fix
----------------------------------------------------
Cold-start diagnostics against the preserved 2.975 MB disconnect/crash specimen
bracketed the ~50% loading hang to the first Archive RestorePersistentData layer:
Core alone (BASE -> RC3B -> RC5 -> RC6S -> RC6T) passed, while Core + FR1K
rehydration froze.  The FR1K helper had been doing three jobs before the Core
restore chain: reattaching compacted context snapshots, aliasing profile.events to
fights[1].events for completed Current, and rebuilding profile.overallEvents.

DC2 makes the pre-Core FR1K hook deliberately minimal.  It ONLY reattaches
contextSnapshotPool entries to persisted p.events/fight.events.  It no longer
creates the completed-Current alias or the runtime Overall event stream before
Core restoration.  Current and Overall are reconstructed later by the already
existing Pass-2B restore wrappers after the Core chain has safely completed.
This preserves Pass-2B context-pool compaction and authoritative fight data while
removing the startup ordering interaction exposed by a disconnect.

Diagnostic rule retained: never mutate/overwrite a suspect SavedVariables specimen
while isolating startup corruption.  Use cold starts and a RAM shadow; no /reload
progression.

DC1 + GA1SAFE - INTERRUPTED COMBAT RECOVERY + GENERAL ARCHIVE CONTEXT CONTRACT
-------------------------------------------------------------------------------
Why DC1 exists:
- During the first real 8 -> 9 fight archive population test, the client
  disconnected and then repeatedly stalled on the loading screen.
- The stall persisted with MainTank_GeneralArchiveData and BossArchiveData
  disabled, proving archive companion execution was not required to reproduce
  the login failure. MainTank core therefore needs a safe interrupted-session
  boundary independent of archive availability.

DC1 persistence contract:
- ONLY entries successfully finalized into profile.fights[] are historical fights.
- StartCombat marks profile.sessionDirty=true BEFORE live combat begins.
- sessionDirty is cleared only after the complete EndCombat/finalization chain
  returns successfully.
- On the next cold load, recovery runs BEFORE MigrateDatabase. This ordering is
  intentional: a large/partial interrupted event stream must be discarded before
  migration or reconstruction can walk it.
- Recovery also recognizes legacy interrupted saves via currentEventsInProgress,
  currentEventOverallOffset, or a non-empty persisted profile.events stream.
- Recovery discards ONLY transient Current combat state (events, pending,
  encounterMemory and the partial Current shell). It preserves authoritative
  Overall totals/timeline, finalized fights[], learned memories and archiveManifest.
- The Current shell is rebound to fights[1]; HF5 then uses that same newest
  finalized fight as Current's authoritative historical representation.
- A one-time red chat notice reports how many unfinished events were abandoned.
- If finalization/archive code fails before EndCombat completes, sessionDirty is
  deliberately left set so the next login recovers instead of promoting partial data.

GA1SAFE General Archive context contract:
- Numeric Pass 2B event.context IDs reference profile.compactContextPool.
- String event.contextID values reference profile.contextSnapshotPool.
- When a finalized fight rolls out of MainTank's 8-fight live window, General
  Archive must copy ONLY the context entries actually referenced by that fight
  into fight.contextSnapshots BEFORE removing the live fight.
- Archived fights must therefore be self-contained: event references may never
  be stored without the dictionary entries needed to decode them.
- Archive restoration rehydrates either context/contextID representation from the
  fight-local contextSnapshots table.
- Existing broken General archives are repaired only by the explicit user command
  /mt archive contexts. No automatic archive repair/load is performed at startup.
- IMPORTANT FOR BOSS ARCHIVE: audit and port this exact context contract after
  General Archive is fully proven. Do not independently reinvent Boss handling.

Regression order after installing DC1-GA1SAFE:
1. Leave General/Boss archive addons disabled and verify the previously stuck DB
   can enter the world. Do not clear MainTankDB.
2. Verify Current newest finalized fight and authoritative Overall are unchanged.
3. Re-enable General Archive only; run /mt archive contexts manually and require
   missing refs = 0 before testing archived Details/Timeline/Pie.
4. Perform another tiny fight rollover and verify the newly archived fight carries
   its own referenced contextSnapshots and survives /reload.
5. Boss Archive remains unproven until the General checklist passes.

GA1-SAFE - GENERAL ARCHIVE CONTEXT HANDOFF (2026-08-12)
--------------------------------------------------------
Regression lesson: archive handoff must use the actual persisted Pass 2B
profile.contextSnapshotPool. Do not invent/check a differently named pool.
An archived fight that retains numeric event context/contextID references must
copy every referenced snapshot into fight.contextSnapshots before the fight is
removed from MainTank's live 8-fight window.

Safety rule: archive repair must NOT run automatically during addon startup or
archive page opening. Existing broken archives are repaired only by the explicit
/mt archive contexts command while General Archive is under test. This keeps a
large/corrupt archive from turning VARIABLES_LOADED into a loading-screen stall.
Apply this same contract to Boss Archive only after General Archive is proven.

-------------------------------------------------------------------------------

PASS 2B HF5 - CURRENT USES THE SAME AUTHORITATIVE RESTORE MODEL AS OVERALL
-------------------------------------------------------------------------------
Observed regression after Pass 2 compaction:
- Overall Pie/Timeline correctly retained Flat DR, Physical DR and Magic DR.
- Current Pie/Timeline lost those DR categories after reload, even though the
  Current title/11-mob metadata had already been restored to Scarlet Enchanter +10.
- HF4's rc6MathVersion marker alone was insufficient and is recorded as a failed
  approach so it is not repeated as the primary fix.

Root architectural issue:
- Completed Overall was already treated as an authoritative restored aggregate.
- Completed Current still travelled through the RC6 live-event rebuild path.
- That meant two views of the same saved combat were using different reconstruction
  contracts, allowing compact historical records to behave differently.

HF5 rule:
- For completed Current, fights[1] is the authoritative dataset.
- Current Pie/headline data starts from fights[1].data and NEVER recomputes or
  overwrites authoritative raw/taken/armor/avoidance/block/resist totals.
- Flat DR, Physical DR, Magic DR and their school-specific Flat DR splits are
  summed from HF2-repaired saved event attribution only.
- Current Timeline bars use fights[1].timeline directly.
- Current historical events are marked as final RC6t generation in RAM so older
  display helpers cannot destructively re-estimate compact events.
- These runtime aliases/snapshots are not persisted as another event payload;
  Pass 2A's disk compaction remains intact.

Regression test for the three-Scarlet dataset:
1. Current title remains Scarlet Enchanter +10.
2. Current RAW/PHYSICAL/MAGIC Pie show their relevant DR categories.
3. Current RAW/PHYSICAL/MAGIC Timeline tooltips show relevant DR attribution.
4. Overall remains 603,756 raw and retains Flat/Physical/Magic DR.
5. Repeat after /reload to verify both Current and Overall stay stable.

UI lesson retained from BACK4:
- Finalize Back-button visibility before positioning the Details title.
- When Back is visible, anchor Details directly to Back's right edge with 10px
  spacing; otherwise retain the normal centered title. BACK1-BACK3 failed because
  title layout occurred before Back became visible.

Pass 2B HF4 - Current finalized DR attribution guard
----------------------------------------------------
- Fixes Current RAW/PHYSICAL/MAGIC Pie and Timeline losing Flat/Physical/Magic DR after reload.
- Pass 2A correctly removes rc6MathVersion from compact saved events, but RC6t display helpers treated the missing marker as a request to recalculate historical DR. On dieted events that recalculation could erase valid saved/repaired attribution.
- HF4 marks valid/repaired historical attribution as RC6t generation 11 in RAM before Current display helpers consume it.
- The marker remains transient and is still excluded from finalized compact disk records, so the Pass 2A/2B storage reduction is preserved.
- No Raw/Taken/Armor/Block/Resist/Absorb totals or Overall authoritative aggregate math are recalculated.
- Includes HF3 Current newest-fight metadata reconstruction and BACK4 navigation/header fix.

-------------------------------------------------------------------------------

BACK1 - Stateful analysis Back button
- Adds Back beside MT Main only after a second-level analysis transition.
- Back restores the exact originating page state (Current/Overall, RAW/Physical/Magic, Timeline minute/page, Pie mode, and Details selection/filter state).
- MT Main still jumps directly to Main and clears analysis history.
- Shortens the Details header from Mitigation Details to Details to make room cleanly.

BACK2 UI polish: Details title now begins 11px after the Back button edge when Back is visible, preventing long Details headers from colliding with navigation controls while preserving full header wording.

BACK3 UI fix: when Back is visible, the Details title is now anchored directly from the Back button RIGHT edge with 10px spacing and left justification. This prevents long Details headers from rendering underneath Back. When Back is hidden, the original centered title layout is preserved.

BACK4 UI fix: corrected Details header layout ordering. The Details updater runs before navigation history makes Back visible, so BACK1-3 always evaluated the button as hidden and restored the centered title anchor. BACK4 applies the title anchor after UpdateBackButtonState finalizes Back visibility, anchoring Details 10px to the right of Back while preserving the normal centered title when Back is absent.

MainTank v1.0.0 FR1X - Pass 1 SavedVariables Structural De-duplication
---------------------------------------------------------------------
FR1X removes the two largest completed-combat event duplicates from the core
SavedVariables file without changing combat parsing or mitigation math.

- Completed combat events persist once: in the authoritative saved fight's
  `fight.events` table.
- `profile.events` is no longer serialized after a fight has completed. It is
  retained only for a genuinely unfinished combat crossing a save boundary.
- `profile.overallEvents` is no longer serialized. Overall totals and the Overall
  timeline remain authoritative persisted aggregates; the event-detail stream is
  rebuilt in memory from the live saved fights after reload.
- New fights store one tiny `overallOffset` value so rebuilt Overall event times
  preserve their session-relative position. Older fights use a duration-based
  fallback for display timestamps only.
- The old SavedVariables migration cycle is complete. MainTank.toc now declares
  only `MainTankDB`; the bootstrap no longer loads or copies the legacy database.
- Database schema advanced to 11.

This is deliberately a storage/persistence pass. Current/Overall aggregate math,
combat attribution, fight data, timelines, pie data and Details event payloads
inside the authoritative fight record are not recalculated or compacted here.

MainTank v1.0.0 FR1W - Slash Lock Controls + Engine Namespace Cleanup
--------------------------------------------------------------------
- Added `/mt lock` as a toggle: unlocked -> locked, locked -> unlocked.
- Added `/mt unlock` as an unconditional unlock command; it never locks.
- Both commands use the same persistent per-character lock state as the main-page lock icon.
- Removed the historical `/mitigationtracker` slash alias from Core/Engine.lua.
- Removed the historical MitigationTracker naming from Core/Engine.lua, including the migration-status message/flag reference.
- The legacy MitigationTrackerDB name remains only in the bootstrap/TOC migration shim so older SavedVariables can still be imported into MainTankDB.
- Safe FR1T+ drag-stop behavior is unchanged.

MainTank v1.0.0 FR1V - Persistent Window Lock

- The Main-page lock/unlock choice is now saved per character in that character's MainTank profile.
- If the current character locks MainTank, /reload and the next login restore it locked.
- If the current character leaves MainTank unlocked, /reload and the next login restore it unlocked.
- Existing FR1U users with no saved lock preference default to unlocked on the first FR1V load.
- The lock icon remains Main-page-only and still controls movement for all managed MainTank windows.
- FR1T/FR1U safe drag-stop behavior is unchanged: OnDragStop only stops movement and saves geometry; it does not ClearAllPoints/SetPoint during mouse release.

MainTank v1.0.0 FR1U - Main-Only Lock Icon / Red Close X
---------------------------------------------------------
- Keeps the FR1T Vanilla-1.12.1-safe drag-stop path: StopMovingOrSizing + save
  geometry only. No ClearAllPoints/SetPoint occurs inside OnDragStop.
- MainTank starts UNLOCKED after every login/reload; lock state is runtime-only.
- Removed visible lock controls from Timeline, Pie, Compare, Details, DR and other
  analysis windows. The only lock/unlock control now lives on the Main page.
- The Main-page lock button sits immediately to the left of the Close button.
- Added dedicated tiny open-lock and closed-lock artwork. Open shackle means the
  addon windows are movable; closed shackle means movement is locked.
- The single Main-page lock still controls movement for all managed MainTank
  windows, so analysis pages cannot accidentally be dragged while locked.
- Main-page Close X is now red to match MainTank's destructive/delete visual cue.
- No combat parsing, mitigation/DR math, fight storage, sync, Pie or Timeline
  calculations were changed.

MAINTANK v1.0.0 FR1S - NAMESPACE & SAVEDVARIABLES IDENTITY MIGRATION
================================================================================

FR1S completes the internal identity migration before further extraction from
Core\Engine.lua.  FR1Q/FR1R had already renamed the distributed addon folders
and user-facing branding to MainTank, but the live Lua namespace and primary
SavedVariables global still used their historical names.

FR1S changes the runtime contract to:

  Addon folder:        MainTank
  Lua namespace:       MainTank
  Primary database:    MainTankDB
  General archive:     MainTank_GeneralArchiveData / MainTankGeneralArchiveDB
  Boss archive:        MainTank_BossArchiveData / MainTankBossArchiveDataDB

All active Lua modules now bind to MainTank rather than MitigationTracker.  This
includes Engine, Archive, SchoolMemory, BlockAnalysis, Maintenance, Commands,
Pie and Style.  Named internal frames/tooltips were also moved to MainTank*
names so newly-created globals no longer extend the historical namespace.

SAVEDVARIABLE MIGRATION SAFETY
------------------------------
FR1Q and FR1R were already installed from the MainTank addon folder but declared
MitigationTrackerDB in MainTank.toc.  Therefore an existing FR1R MainTank.lua
SavedVariables file may still contain:

  MitigationTrackerDB = { ... }

FR1S temporarily declares BOTH globals in MainTank.toc:

  MainTankDB, MitigationTrackerDB

MainTank.lua runs a migration before Core\Engine.lua initializes.  If MainTankDB
does not yet exist but the historical MitigationTrackerDB does, the migration
moves the existing table by reference:

  MainTankDB = MitigationTrackerDB
  MitigationTrackerDB = nil

This is intentionally not a deep copy.  Fight/event/history tables are not
expanded, duplicated or rewritten merely to change the database name.  The
existing data structure becomes MainTankDB and the legacy global is cleared so
subsequent clean saves serialize the new name.

If both globals somehow exist (for example after an interrupted migration), an
existing MainTankDB wins.  FR1S will not overwrite it with a potentially stale
legacy table.

The legacy variable remains listed in the TOC for this migration release only so
WoW can deserialize FR1R-era MainTank SavedVariables.  Because the migration
sets MitigationTrackerDB to nil, normal logout/reload saves should contain only
MainTankDB.  A future release can remove the legacy TOC declaration after the
migration has had sufficient field testing.

SLASH COMMAND COMPATIBILITY
---------------------------
The command registry is now MAINTANK internally.  The supported aliases are:

  /mt
  /maintank
  /mitigationtracker   (legacy compatibility alias)

The legacy slash alias is harmless and does not keep the old Lua namespace or
old SavedVariables database alive.

WHY THIS PRECEDES MORE MODULARIZATION
-------------------------------------
FR1S intentionally avoids another broad subsystem extraction.  Renaming the
runtime namespace/database first gives every future module one stable identity:
MainTank + MainTankDB.  This prevents us from extracting a Timeline/Details/DR
module under MitigationTracker only to rename all of its interfaces again in a
later release.

No intentional changes were made to mitigation equations, Sanctuary/DR math,
block math, Pie/Timeline totals, combat parsing, the 8+8 Data Vault retention
policy, or reset semantics.  FR1S is an identity/migration release.

MAINTANK v1.0.0 FR1R - RENAME/UI REGRESSION HOTFIX
================================================================================

FR1R repairs three presentation regressions exposed immediately after the FR1Q
folder rename and modular UI extraction.  No mitigation, DR, block, archive,
combat-parser, or fight-retention equations were intentionally changed.

1. PIE RENDERER PATH AFTER RENAME
---------------------------------
The standalone Pie renderer still loaded wedge textures from:

  Interface\AddOns\MitigationTracker\GraphTextures\

after the distributed addon folder had been renamed to MainTank.  The graph
frame and legend therefore existed, but the pie wedges themselves could not be
loaded.  FR1R points the renderer at:

  Interface\AddOns\MainTank\GraphTextures\

2. GENERIC BUTTON PASS WAS USING SELECTOR-ONLY STYLING
------------------------------------------------------
UI/Style.lua's recursive styling pass accidentally called the old
RC6P_ForceBlackSelector helper on every button.  That helper is intentionally
specialized for the Pie/Timeline View selector: it removes template textures
and colors the font gold/yellow.  Applied globally it caused:

  * white controls on initial load, then gold/yellow controls after navigating;
  * Current/Overall and RAW/Physical/Magic selection state to become difficult
    to see because disabled/selected styling was overwritten;
  * the red Reset Data icon to lose its artwork and become a small black square.

FR1R separates ordinary button styling from selector styling.  Only the
Pie/Timeline View selector receives RC6P_ForceBlackSelector.  Normal buttons
keep their gray/disabled states, and icon-based Reset Data controls are excluded
from generic text-button skinning so their red Cancel/Pass artwork survives.

3. USER-FACING BRANDING
-----------------------
The historical internal Lua namespace remains MitigationTracker for compatibility
with the proven engine and existing SavedVariables, but the visible main-window
title, chat prefix, and export/report heading now say MainTank.

FR1R is intentionally a regression hotfix rather than another aggressive module
extraction.  The next modularization pass should continue only after these
first-render and selection-state behaviors are confirmed stable in-game.



================================================================================

MAIN TANK v1.0.0 FR1R - RENAME + TWO-FOLDER / 16-FIGHT SAFETY ARCHITECTURE
================================================================================

FR1Q renames the distributed addon from MitigationTracker to MainTank.

The installed addon is intentionally reduced to exactly two addon folders:

  MainTank
    - active addon, UI, parser/math, current/overall state
    - retains at most 8 completed detailed fights

  MainTank_GeneralArchiveData
  MainTank_BossArchiveData
    - LoadOnDemand historical storage
    - retains at most 8 additional completed detailed fights

TOTAL DETAILED FIGHT CAPACITY: 16 (8 live + 8 archive)

When the 17th retained detailed fight would exceed that limit, MainTank rotates
out/discards the oldest archived detailed fight. The archive is therefore a
bounded rolling history, not an ever-growing database. A red chat warning is
shown when the bounded history reaches capacity so the player knows old detail
is being rotated and can use /mt reset if they want a completely clean slate.

This design is intentionally defensive. Players should not need to remember to
clear months of combat history just to keep the addon safe. The active MainTank
SavedVariables file stays bounded to its eight-fight live window, while the
two independent archive SavedVariables files are bounded to eight detailed fights each: GeneralArchiveData for non-boss fights and BossData for skull-level boss fights.

The internal historical Lua namespace remains MitigationTracker in FR1Q. This is
intentional compatibility engineering: renaming hundreds of cross-file global
and method references at the same time as the addon/folder/database architecture
would add risk without reducing memory or disk usage. User-facing distribution,
addon folders, TOCs and archive architecture are MainTank now; internal namespace
migration can be done separately after the new two-folder build is field-tested.

================================================================================

MitigationTracker v1.0.0 FR1P - Modularization + Data Vault Guardrails
======================================================================

FR1P continues the safe modularization started by FR1O. File size by itself is
not a runtime bug, but a broken Lua 5.0 lexical dependency absolutely can be.
For that reason this release only extracts subsystems that can communicate with
the historical engine through explicit MitigationTracker methods.

Newly separated modules:
  * UI\Style.lua - common black/pfUI-style button treatment, first-render
    styling, Pie/Timeline lifecycle cleanup, and main-row hover surfaces.
  * Modules\BlockAnalysis.lua - bounded one-pass block-value reconstruction.
  * Modules\Maintenance.lua - reset/runtime/database hygiene, page show/hide
    repair, context pruning, and lightweight health diagnostics.
  * Core\Release.lua - authoritative build label loaded last.

Core\Engine.lua remains the home of the historical combat/parser compatibility
chain. FR1P reduces it further without moving parser/math locals across files.
UI and analysis code will continue to be peeled out only after dependencies are
made explicit.

DATA VAULT CAPACITY CHANGE
--------------------------
FR1P reduces Data Vault retention from four large archive banks to two small
banks. The detailed fight budget is now deliberately 20 fights total:

  Core/live: 8 detailed fights
  Archive 1: 6 detailed fights
  Archive 2: 6 detailed fights
  TOTAL:     20 detailed fights

This does not mean 20 individual combat-log events. A single fight can contain
hundreds or thousands of events. Context-snapshot pooling and the persisted
Overall-event ceiling continue to control those larger event arrays.

When the detailed history approaches the 20-fight safety ceiling MT prints a
RED warning in chat. Once full, MT prints:

  DATA VAULT FULL - detailed history is at its 20 fight safety limit.

The oldest archived detailed fight is then rotated out rather than allowing the
core database or archive files to grow without bound. /mt reset remains the same
confirmed full combat/history/learned-data reset as the red reset icon and also
clears both Data Vault banks.

Why two archive files? Separate LoadOnDemand archive addons still provide the
important failure isolation: corruption of an old archive SavedVariables file
does not have to block the core MitigationTracker addon during login. Reducing
four banks to two does not make the active core DB smaller by itself, but it
roughly halves the maximum archive retention footprint and keeps long-term disk
growth far more predictable.

================================================================================

v1.0.0 FR1O - ROOT MODULARIZATION / SOURCE LAYOUT CLEANUP
===============================================================================

FR1O continues the conservative modularization started by FR1k/FR1L/FR1M/FR1N.
The main addon-root MitigationTracker.lua had grown to roughly 584 KB because it
contained the entire historical implementation and many compatibility-generation
overrides accumulated during development.

The important constraint is Lua 5.0 lexical scope: locals declared in one .lua
file are not visible in another .lua file. A blind cut-and-paste split of the
historical implementation would therefore risk breaking subtle helper/upvalue
relationships even when every moved function looked syntactically valid.

FR1O solves the immediate organization problem without changing that proven
scope. The historical implementation is moved intact to:

    Core\Engine.lua

and the addon root now contains a very small MitigationTracker.lua bootstrap /
source-layout marker. The TOC explicitly loads the files in the required order.
The root source tree is now:

    MitigationTracker.lua          lightweight bootstrap / build marker
    Core\Engine.lua                historical core + combat/parser chain
    Core\Commands.lua              slash-command help/router extension
    Core\SchoolMemory.lua          learned spell-school recovery
    Modules\Archive.lua            Data Vault / SavedVariables safety
    UI\PieRenderer.lua             low-level pooled pie renderer
    UI\Pie.lua                     Pie presentation / legend policy
    Core\ARCHITECTURE.txt          maintainer architecture notes

The old standalone MTPie.lua is also moved to UI\PieRenderer.lua. Its code is
unchanged apart from location; the TOC loads it before Core\Engine.lua exactly
as the previous MTPie.lua was loaded before MitigationTracker.lua.

WHY NOT SPLIT Core\Engine.lua INTO TEN FILES NOW?
-------------------------------------------------
Because file size by itself is not a runtime bug, while broken lexical scope is.
FR1O deliberately isolates the monolith first, documents its dependency risk,
and establishes clean homes for future extractions. Subsequent releases can
move UI/analysis/scanner subsystems one at a time after their dependencies are
made explicit and tested.

Recommended extraction order is:

  1. shared UI styling / tooltip helpers
  2. Timeline controller
  3. Details / Biggest / Export / Boss / Compare controllers
  4. Block analysis scanner/reporting
  5. DR scanners/diagnostics
  6. remaining persistence/migrations
  7. combat parser/math LAST

No mitigation equations, Sanctuary/DR math, Block Value math, combat parsing,
Pie totals, Timeline totals, Data Vault limits, reset semantics, SavedVariables
schema, or fight-retention behavior are intentionally changed by FR1O.

This is an organizational release: the goal is to make future development safer
without paying for cleanliness by destabilizing already-validated gameplay math.


======================================================================

v1.0.0 FR1N - PIE LEGEND CREATION-ORDER FIX + RAW-ONLY ABSORBS
==============================================================

FR1N fixes the remaining Physical Pie legend issue seen after FR1M.

The underlying Partial Block value was not missing.  The main Physical page
could show, for example, both Full Blocks and 44 Partial Blocks while the Pie
legend still stopped after its seventh visible row.  FR1M correctly added code
to allocate nine rows, but the Pie frame can already be created by the main UI
before the late-loaded UI/Pie.lua module runs.  In that case wrapping only
CreatePieWindow() was too late: the already-existing frame kept its original
seven rows.

FR1N makes the capacity fix creation-order independent:

- UI/Pie.lua immediately expands an already-created MT.pieFrame when the module
  loads.
- CreatePieWindow() still expands newly-created Pie frames.
- UpdatePieWindow() verifies/repairs the nine-row legend before every redraw,
  including after /reload and live Pie updates.
- The compact 300x231 Pie page is retained; row spacing is tightened slightly
  rather than enlarging the window.

The maximum specialized Pie capacity is now deliberately nine rows.  Magic can
legitimately need all nine:

  Flat DR
  Magic DR
  Holy
  Fire
  Nature
  Frost
  Shadow
  Arcane
  Unknown

Physical can now display up to eight mitigation categories at once:

  Armor
  Flat DR
  Physical DR
  Dodge
  Parry
  Miss
  Full Block
  Partial Block

ABSORB POLICY CLEANUP
---------------------

Absorbs are intentionally RAW-only in FR1N.  An absorb shield is a special
cross-school prevention mechanic and can absorb physical or magical damage, so
it should not semantically belong to either specialized Pie.

  RAW      -> Absorbs included
  PHYSICAL -> Absorbs omitted
  MAGIC    -> Absorbs omitted

This is a Pie presentation/category change only.  Event absorb accounting,
RAW totals, Details, Timeline data and the validated mitigation equations are
not changed.

===============================================================================

v1.0.0 FR1M - PIE LEGEND CAPACITY + UI MODULARIZATION
================================================================================

FR1M fixes a presentation bug exposed by a fight containing both Full Blocks and
Partial Blocks.

The Physical Pie data model was already correct and already included Partial
Block.  GetPieData(PHYSICAL) can produce as many as nine categories:

  Armor
  Flat DR
  Physical DR
  Dodge
  Parry
  Miss
  Full Block
  Partial Block
  Absorbs

However, the compact v1 Pie page had only seven legend-row frames.  MTPie still
drew every wedge and Total Prevented still counted every category, but entries
8 and 9 had nowhere to display in the legend.  In the reported example the
visible legend totaled 199,241 prevented damage while the Pie total was 205,342.
The exact 6,101 difference was the 44 Partial Blocks shown on the Physical main
page.  The data was therefore not lost; the legend capacity hid it.

FR1M allocates nine Pie legend rows and tightens their spacing slightly so all
Physical mitigation categories fit inside the existing compact Pie window.  No
new mitigation category was invented and no block/combat math was changed.
Partial Block appears only when the selected data actually contains partial
block mitigation; Full Block and Partial Block remain separate categories.

FR1M also continues the gradual source-file modularization started in FR1k/FR1L:

  UI\Pie.lua
      Owns this Pie-page presentation/capacity patch without moving the proven
      combat parser or RC6 attribution math out of MitigationTracker.lua.

This is intentionally a UI-layer change.  Raw/taken reconstruction, Flat DR,
percentage DR, Armor, block attribution, SavedVariables/Data Vault behavior,
SchoolMemory, Timeline, and live Pie refresh behavior are unchanged.

v1.0.0 FR1L - MODULAR ORGANIZATION + COMPLETE COMMAND HELP + SCHOOL RECOVERY
===============================================================================

FR1L continues FR1k's conservative modularization instead of attempting a risky
one-shot split of the ~12,000-line combat engine. The core parser/math remains in
MitigationTracker.lua while two cleanly bounded systems move into dedicated files:

  Core\SchoolMemory.lua
    * cross-attacker spell-school learning;
    * conservative canonical fallbacks for unambiguous spell names;
    * full-resist Unknown-school repair;
    * authoritative rebuilding of magic-school resist buckets from events.

  Core\Commands.lua
    * central user-facing slash-command catalog;
    * detailed multi-line /mt help output;
    * /mt, /mt help, /mt ?, and /mt commands all show the same reference.

Existing command handlers deliberately remain in their already-tested wrapper
chain for FR1L. Moving every handler at once would create unnecessary risk because
many older RC compatibility layers capture the previous MT:HandleSlash function.
The new Commands module therefore becomes the authoritative HELP surface first;
future command migrations can move into it incrementally without changing combat
behavior.

Current load order:

  MTPie.lua
  MitigationTracker.lua
  Modules\Archive.lua
  Core\SchoolMemory.lua
  Core\Commands.lua

The combat parser remains the LAST major component planned for extraction. This
keeps the validated Flat DR -> %DR -> Armor / Block / Resist math stable while the
surrounding systems become easier to maintain.

FULL-RESIST SCHOOL RECOVERY
---------------------------
Vanilla combat messages for complete spell resists often omit the damage school.
MitigationTracker already remembered school by attacker + ability, but this meant
that a first full resist from a NEW attacker could still appear as Unknown. A
Scarlet Cleric Mind Blast was a real example: the event correctly recorded all
443 damage as resisted but the Magic Pie and Details page labeled the school
Unknown instead of Shadow.

FR1L resolves an omitted school in this order:

  1. exact attacker + ability school memory;
  2. cross-attacker learned ability school memory;
  3. a small conservative canonical map for unambiguous spells (Mind Blast,
     Shadow Bolt, Fireball, Frostbolt, etc.);
  4. Unknown only when MT still cannot establish the school safely.

The cross-attacker cache is persisted with the character profile. Existing
Unknown full-resist events are repaired when possible on load, and the displayed
magic-school buckets are rebuilt from the authoritative event stream so a repaired
Mind Blast moves from Unknown into Shadow immediately instead of leaving stale
aggregate data behind.

PHYSICAL PIE NOTE
-----------------
No additional Partial Block row was forced into the UI in FR1L. MitigationTracker
already has Partial Block support and only creates a Pie entry when that value is
non-zero. The current Physical legend has adequate room for Full Block and Partial
Block to coexist if a shield swap / incoming hit-size combination produces both.

COMMAND HELP
------------
The old one-line command dump had become incomplete and difficult to read. FR1L
replaces it with categorized help spanning Window, Fights & Data, Analysis,
Sharing/Sync, Damage Reduction, Block Analysis, Data Vault/Database, Diagnostics,
and Help. Primary commands are documented along with the most useful aliases.

Use any of:

  /mt
  /mt help
  /mt ?
  /mt commands

No mitigation equations, Sanctuary math, block formulas, archive retention limits,
live Pie refresh behavior, or reset semantics are intentionally changed by FR1L.

FR1L SLASH COMMAND QUICK REFERENCE
---------------------------------
WINDOW
  /mt show
  /mt hide
  /mt mini | /mt shrink
  /mt full | /mt expand
  /mt automini
  /mt automini on | /mt automini off

FIGHTS & DATA
  /mt current
  /mt overall
  /mt fights
  /mt fight N
  /mt resetfight | /mt resetcurrent
  /mt reset | /mt resetsession

ANALYSIS WINDOWS
  /mt timeline
  /mt pie | /mt chart
  /mt details | /mt enemies | /mt abilities
  /mt biggest | /mt hits
  /mt boss | /mt encounter
  /mt compare | /mt tanks
  /mt export | /mt report

SHARING & TANK SYNC
  /mt share party
  /mt share raid
  /mt share guild
  /mt share say
  /mt sync | /mt sync tank

DAMAGE REDUCTION
  /mt dr
  /mt context
  /mt itemdr
  /mt itemraw
  /mt drscan | /mt talentdr
  /mt activedr | /mt cooldowndr
  /mt sanc | /mt sanctuary
  /mt math | /mt drmath
  /mt mathrank

BLOCK ANALYSIS
  /mt blocks
  /mt blockrefresh

DATA VAULT / DATABASE
  /mt archive | /mt archives | /mt vault
  /mt archive now | /mt vault now
  /mt archive restore N
  /mt dbhealth | /mt db
  /mt cleararchives
  /mt cleararchives confirm

DIAGNOSTICS
  /mt events
  /mt memory
  /mt perf | /mt health
  /mt debug

HELP
  /mt
  /mt help
  /mt ?
  /mt commands

================================================================================

v1.0.0 FR1k - DATABASE ARCHITECTURE / SAFETY + FIRST MODULARIZATION PASS
===============================================================================

WHY THIS RELEASE EXISTS
-----------------------
MitigationTracker had reached the point where very long test/raid sessions could
produce extremely large SavedVariables.  The addon was storing detailed current
events, detailed overall events, completed fight event histories, timelines,
and per-event mitigation-context snapshots.  Some of those structures duplicate
information by design so the UI can reconstruct old fights after /reload.

That is useful analysis data, but it is a poor failure domain when all historical
data lives in one giant WTF\\...\\SavedVariables\\MitigationTracker.lua file.  If
that one file is interrupted or malformed, the entire core addon can fail before
the player is fully in the world.

FR1k changes the architecture rather than simply tolerating ever-larger files.

DATA VAULTS ARE SEPARATE ADDONS, NOT JUST EXTRA GLOBAL TABLES
------------------------------------------------------------
A critical Vanilla WoW limitation is that multiple SavedVariables declared by
ONE addon are still serialized into that addon's one SavedVariables file.  So
adding MitigationTrackerArchive1/2/3 as globals inside MitigationTracker.toc
would NOT isolate corruption.

FR1k instead ships four tiny LoadOnDemand companion addons:

  MitigationTracker_Archive1
  MitigationTracker_Archive2
  MitigationTracker_Archive3
  MitigationTracker_Archive4

Each companion addon has its own .toc and its own SavedVariables declaration.
That means each Data Vault gets an independent WTF SavedVariables file.

The archive addons are NOT loaded during normal initial login.  MitigationTracker
loads a vault only when an old completed fight actually needs to roll out of the
live window, or when the user explicitly asks to inspect/restore archive data.
Therefore a damaged old archive should not prevent the core MitigationTracker
addon from reaching the game world.

LIVE / ARCHIVE RETENTION
------------------------
FR1k keeps the newest 8 completed fights as full live-detail fights in the core
profile. Older completed fights roll into the Data Vaults automatically.

Each of the four vaults holds up to 25 archived fights per character profile.
When all vaults are full, the oldest archived record is rotated out. This keeps
historical storage bounded instead of growing forever.

Archived fights remain detailed, but repeated rc6ContextSnapshot tables are
compacted into one contextSnapshots pool per archived fight. Events keep their
contextID and are rehydrated if an archived fight is restored.

CORE SAVEDVARIABLES COMPACTION
------------------------------
Per-event RC6 mitigation snapshots were one of the largest repeated structures
in long sessions.  Before PLAYER_LOGOUT (including /reload), FR1k strips repeated
rc6ContextSnapshot copies from current/overall/live-fight events and saves one
profile-level contextSnapshotPool instead.

On the next load/reload those snapshots are reattached BEFORE the existing RC6
restore/migration chain runs, so the combat math still sees the same mitigation
context while the on-disk representation is much smaller.

FR1k also places a disk-safety ceiling on persisted detailed OVERALL events:
only the newest 4000 detailed overall events persist across reload/logout.
Runtime combat tracking is NOT capped by this number.  Aggregate overall totals
and timeline data remain intact, and completed fights remain available live or
through the Data Vaults.  The ceiling is intentionally conservative: detailed
historical fight data belongs in the isolated vault files, not in an endlessly
growing core login file.

COMMANDS
--------
  /mt archive
  /mt archives
  /mt vault
      Rolls excess live fights into Data Vaults and prints archive status.

  /mt archive restore N
      Restores archive-list entry N into the live detailed fight list.

  /mt dbhealth
  /mt db
      Prints core event counts, live/archive fight counts, and context-pool size.

  /mt cleararchives
      Safety prompt only. No data is deleted.

  /mt cleararchives confirm
      Permanently clears this character's MitigationTracker Data Vault history.

RESET BEHAVIOR
--------------
/mt reset and the red reset button still share the exact same ResetSession path.
They clear active/current/overall/saved-fight/timeline/learned analysis data AND
all readable Data Vault archive banks for this character, as requested by the
user-facing message: "All current, overall, saved-fight, timeline, and learned
data reset." UI/window preferences remain preserved.

/mt cleararchives confirm remains available when the user wants to clear only
Data Vault history without resetting the live session.

FIRST MODULARIZATION PASS
-------------------------
The original MitigationTracker.lua has grown very large because almost every
release historically appended compatible overrides into one Lua chunk.  A giant
single source file is not automatically a runtime problem, but it makes changes
harder to reason about and increases the blast radius of future refactors.

FR1k begins modularization conservatively:

  MTPie.lua                 pie renderer / texture pool
  MitigationTracker.lua     established combat/core/UI compatibility chain
  Modules\\Archive.lua       NEW: persistence policy, vaults, DB health commands

The large combat parser and UI are NOT split wholesale in FR1k. Doing that in
one release would change Lua local/upvalue scope and could subtly break the math
we spent many RC6/FR1 releases validating in live VanillaPlus combat.

Future safe extraction order should be incremental:

  1. Database / archive / migration helpers       (started in FR1k)
  2. UI styling / shared button helpers
  3. Pie / Timeline page controllers
  4. Details / Compare / Boss / Export pages
  5. DR scanners and diagnostic commands
  6. Combat parser/core LAST, after regression tests

The rule is simple: modularize by stable subsystem, one subsystem at a time,
while keeping public MT methods and SavedVariables schema compatible.

INSTALLATION NOTE
-----------------
FR1k's ZIP contains FIVE addon folders at the same level. Install all five into
Interface\\AddOns:

  MitigationTracker
  MitigationTracker_Archive1
  MitigationTracker_Archive2
  MitigationTracker_Archive3
  MitigationTracker_Archive4

The four Data Vault addons are LoadOnDemand; they should not add normal login
work. Do not merge their files into the main MitigationTracker folder, because
the separate-addon boundary is what gives the archives separate SavedVariables
files and therefore isolates archive corruption from core login.

No combat mitigation formula, Sanctuary rank math, percentage-DR stacking,
armor ordering, dual-wield constraint, block calculation, Pie math, or Timeline
math is intentionally changed by FR1k.
===============================================================================

===============================================================================

MitigationTracker v1.0.0 FR1j - Slash Command Navigation Repair
---------------------------------------------------------------
FR1j fixes a UI-navigation regression where `/mt show` could appear to do nothing.

Cause:
- The v1.0 single-window page manager tracks MAIN, Timeline, Pie, Details, Biggest, and other analysis pages as mutually exclusive managed pages.
- `/mt show` still used the old pre-v1 behavior: `self.frame:Show()`.
- If `currentManagedPage` still pointed at an analysis page, the manager's guard correctly hid the MAIN frame again on its next safety pass.
- The result was a slash command that technically showed the frame for an instant but appeared non-functional to the player.

Fix:
- `/mt show` now routes through `ShowManagedPage("MAIN")`, the same authoritative navigation path used by the in-addon MT Main controls.
- `/mt hide` now hides every managed MitigationTracker page and clears the active managed-page state instead of hiding only the summary frame.
- The two slash commands are therefore symmetrical and cannot fight the page manager.

No combat parsing, mitigation equations, DR attribution, block-value reconstruction, Pie/Timeline data, SavedVariables schema, or persistence behavior changed in FR1j.

===============================================================================

MitigationTracker v1.0.0 FR1i - Complete Block-Value Gear Reconstruction
--------------------------------------------------------------------------
FR1h/FR1g kept login stable, but live testing exposed a correctness problem in the
Block Analysis component breakdown: the safe FR1g fallback only inspected the
off-hand and accepted the first block-value line it found. VanillaPlus items can
carry more than one block-value contribution on the same item and can add block
value from non-shield slots.

Confirmed example:
- Aegis of the Blood God: 47 native Block plus Equip: +30 shield block value.
- Styleen's Impeding Scarab: Equip: +30 shield block value.
- Gear subtotal before Strength/talent: 107 block value.
- Shield Specialization 2/2 is then applied as +30% after the gear + Strength base.

FR1i changes:
- Scans every equipped item exactly once through the already-proven
  BetterCharacterStats/GameTooltip path.
- Sums EVERY matching block-value line on an item instead of stopping after the
  first match. This is required for shields that contain both a native `# Block`
  line and a separate `Equip: Increases the block value ... by #` line.
- Includes block-value bonuses from other equipment slots such as trinkets.
- Reads Shield Specialization directly from its learned rank (15% / 30%).
- Applies the talent multiplier after Shield/gear + Strength.
- When direct custom-item tooltip data is available, that reconstruction is used
  instead of allowing an incomplete GetShieldBlock() value to overwrite it. The
  client API remains a fallback/diagnostic only.
- The scan is bounded to one pass and NEVER self-schedules a retry, preserving the
  FR1g login-stability guarantee.

No mitigation/DR combat equations, Pie/Timeline data, SavedVariables reset logic,
or fight parsing were changed in FR1i.

MitigationTracker v1.0.0 FR1h - SavedVariables Reset Safety
------------------------------------------------------------
- /mt reset now invokes the exact same confirmation flow as the red reset button
  on the main page. There is no longer a separate silent/destructive slash path.
- Both paths ultimately use the same ResetSession implementation and therefore
  cannot drift apart as the addon gains new stored-data systems.
- Finished the meaning of "learned data reset" by clearing ability-school memory
  as well as session/context/target learning already cleared by prior reset hooks.
- A full reset also restarts nextFightID and clears timeline selection/current
  saved-view history state.
- UI placement, hidden/mini preferences, and other user-facing configuration are
  deliberately preserved. /mt reset is a data cleanup, not a settings wipe.
- The reset remains confirmation-gated to reduce accidental loss of raid history.
- This is intended as the supported way to aggressively shrink MitigationTracker's
  SavedVariables after long testing/raid sessions. It does not replace fixing a
  code-level login loop; FR1g already removed the runaway block scanner retry path.

MitigationTracker v1.0.0 FR1g - Block Scanner Stability Hotfix
============================================================
FR1f unified the Base Block Value breakdown with the BetterCharacterStats tooltip scanner, but the automatic CalculateBlockValue path could repeatedly scan all equipped items and talent tooltips while the block retry timer was active. On some Vanilla-derived clients that can effectively lock the login frame.

FR1g removes that feedback path. Shield Specialization is read directly from its learned talent rank (15/30%), GetShieldBlock is used as the authoritative final value when available, and Shield/gear is inferred from the final block value minus Strength before the talent multiplier. If the API is unavailable, only the off-hand tooltip is scanned once as a fallback. Automatic block scanning no longer schedules itself for retries.

The goal of FR1g is stability first: preserve the useful Block Analysis breakdown without allowing tooltip scanning to interfere with login or frame updates. No mitigation/DR/Pie/Timeline combat math was changed.

v1.0.0 FR1g - Block Value Scanner Unification
-----------------------------------------------
FR1f fixes the block breakdown exposed by the restored FR1e Base Block Value tooltip. Live testing showed the final Base Block Value itself could be correct through the client API while the component breakdown incorrectly reported Shield and gear = 0 and Talent bonus = 0%.

Root cause:
- The older block-value calculator still used MitigationTrackerScanTooltip, an early hidden tooltip implementation.
- Later RC6 gear work proved that this VanillaPlus/Octo-derived client can populate hidden tooltips incompletely or not at all. The equipped-DR scanner was therefore migrated to BetterCharacterStats' long-lived tooltip with GameTooltip fallback, but the much older block scanner was never migrated with it.
- Shield Specialization had the same issue: its text parser was correct for the current wording ("Increases the amount of damage absorbed by your shield by 30%."), but the legacy talent tooltip often exposed no readable text.

FR1f changes:
- Block-value equipment scanning now reuses the proven BetterCharacterStats / GameTooltip / MT-tooltip fallback path already validated by /mt itemdr.
- Added robust parsing for native/custom shield block-value lines such as Block 107, Block: 107, +107 Block, Block Value +107, and Equip text that increases shield block value.
- Shield Specialization is read from the same robust talent-tooltip path. Current VanillaPlus Shield Specialization also has a conservative exact-name rank fallback of 15/30% if the client fails to expose talent text.
- If an equipped shield's custom tooltip still omits its block line but GetShieldBlock() is available, FR1f can infer the shield/gear component from the authoritative client block value, Strength contribution, and talent multiplier. This fallback is only used when direct gear parsing returns zero.
- Hovering or clicking Base Block Value forces a fresh scan, so recent gear/talent changes are reflected immediately instead of waiting on a stale cache.
- The final client API value remains authoritative when available; the reconstructed parts exist to explain how that value is composed.

Expected example:
  Base Block Value        161
  Shield and gear        ~107
  Strength (10 = 1)        17
  Talent bonus            +30%

Exact Shield/gear may differ by rounding or additional block-value equipment, but it should no longer remain at zero merely because the legacy hidden tooltip failed.

No DR attribution, Sanctuary math, Pie/Timeline rendering, saved-fight persistence, Tank Compare, avoidance estimation, or combat-log parsing was changed in FR1f.


============================================================

v1.0.0 FR1e - Block Analysis Hover Surface Repair
--------------------------------------------------
FR1d correctly restored the visibility of the main-page row hit frames after
Mini Mode, but live testing showed that hovering or clicking "Base Block Value"
still did nothing.

Root cause:
- An older RC1d UI-layout compatibility wrapper had called ClearAllPoints() on
  every summary-row hit frame and then given it only a single RIGHT anchor to
  the value FontString.
- The original hit frames derived their width from LEFT + RIGHT anchors. After
  that layout rewrite they retained a height, but no meaningful horizontal
  span. They could therefore be technically visible while having essentially no
  mouse surface.
- FR1d fixed the hidden/shown state but did not repair this collapsed geometry.

FR1e fix:
- Every main-page row hit frame is now anchored directly from the visible row
  label to the visible row value.
- The hover surface therefore covers both "Base Block Value" and the displayed
  number on the right.
- The hit frame follows any later row repositioning automatically because its
  anchors reference the label/value regions instead of hard-coded coordinates.
- Row hit frames are explicitly mouse-enabled and placed above normal frame
  content so decorative regions cannot intercept hover/click events.
- The repair is applied after the full historical CreateUI wrapper chain and is
  reasserted whenever SetRow updates row visibility.

Expected Physical-page behavior:
- Hover either "Base Block Value" or its numeric value to open Block Analysis.
- Click anywhere across that row to print the detailed block report.
- Mini Mode still hides the row hit surfaces and full mode restores them.

No mitigation math, Base Block Value calculation, combat parsing, persistence,
Pie, Timeline, Tank Compare, or DR attribution was changed in FR1e.

v1.0.0 FR1d - Block Analysis Tooltip Restoration
--------------------------------------------------
FR1d restores the detailed Base Block Value hover/click analysis on the main Physical page after Mini Mode has been used.

Root cause:
- Each full-page data row owns an invisible mouse-enabled hit frame. Physical row 8 uses that hit frame for the Block Analysis tooltip and click-to-print block report.
- Mini Mode correctly hid those hit frames along with the full-page text.
- Returning to the full window restored the row labels and values, but SetRow did not re-show the hit frames. The visible Base Block Value row therefore looked normal while its hover/click surface remained permanently hidden for the session.

Changes:
- SetRow now re-shows a row's hit frame whenever that row contains visible data and Mini Mode is not active.
- Empty rows hide their hit frames as well as their text, preventing stale invisible mouse regions.
- Restores the Physical page Base Block Value hover tooltip: calculated shield/gear, Strength contribution, talent bonus, client API value when available, observed partial-block low/average/high/sample count, target-specific observed block data, and the VanillaPlus scaling note.
- Restores clicking Base Block Value to print the detailed block report.
- Updated public diagnostic/version labels to FR1d.
- No block calculations, DR calculations, combat event parsing, saved-fight data, Pie rendering, Timeline rendering, or Tank Compare behavior changed.

v1.0.0 FR1c - First-Render Graphical Homogeny
----------------------------------------------
FR1c closes the last reproducible first-render UI inconsistency found after FR1b. Live screenshots showed that Timeline and Pie could still open with the View: RAW selector using Blizzard's red/gold UIPanelButtonTemplate artwork. On Pie, the first chart could also remain empty until View: RAW was clicked.

Root cause:
FR1a wrapped ShowManagedPage for recursive black-button cleanup, but that wrapper accidentally accepted only pageName and did not forward ShowRCPage's updater callback. Pie and Timeline therefore opened without their normal first UpdatePieWindow/UpdateTimelineWindow call. Clicking the View selector later invoked the update manually, which simultaneously drew the Pie and applied the final selector styling. This made the problem look purely graphical even though the missing first refresh and red first-render button shared the same lifecycle cause.

Changes:
- Restored the full ShowManagedPage(pageName, updater) contract and forwards the updater callback exactly as the page manager originally intended.
- Pie now performs its normal data/render update immediately on first open; no View click is required to make the circle/legend appear.
- Timeline likewise receives its initial refresh immediately when opened.
- Pie and Timeline View: RAW / PHYSICAL / MAGIC selectors are explicitly given the final black/gray MitigationTracker skin immediately after creation, before their first visible frame.
- Timeline < / > paging arrows retain the FR1b black/gray treatment.
- No polling or permanent OnUpdate styling loop was added; this is a lifecycle/order correction, keeping the old 1.12 client lightweight.
- No mitigation formulas, DR attribution, event snapshots, reload persistence, live Pie refresh logic, Tank Compare, or combat parser behavior changed.

Why FR1b did not fully solve it:
FR1b correctly identified the late-created selector controls and fixed the Timeline paging arrows, but the deeper callback-loss issue meant the selector's normal update-time styling path still did not execute on first open. FR1c fixes both layers: immediate creation-time skinning and the missing first-page updater.

v1.0.0 FR1b - Graphical Homogeny
--------------------------------
FR1b is a deliberately small visual-maintenance release following the FR1a stability pass. In FR1a, the shared analysis page frame was finalized and recursively skinned before some page-specific controls were created. As a result, the Timeline and Pie "View: RAW" controls could display the original red/gold Blizzard UIPanelButtonTemplate artwork on their first render, then become the intended sleek black/gray MitigationTracker style only after interaction caused another UI styling/update path to run.

Changes:
- Pie Chart View: RAW / PHYSICAL / MAGIC button is now styled immediately when it is created, so the first visible state matches later states.
- Timeline View: RAW / PHYSICAL / MAGIC button receives the same immediate styling.
- Timeline previous/next (< / >) paging controls now use the same dark black/gray button treatment instead of Blizzard red/gold artwork.
- Public diagnostic labels and the authoritative addon version are updated to FR1b.
- No mitigation math, event classification, DR detection, saved-fight persistence, live Pie refresh, Timeline calculation, Tank Compare, or combat parsing behavior was changed.

Why this happened:
The common page constructor calls the legacy/pfUI styling finalizer while constructing the base window. Pie and Timeline then add their own mode/paging buttons afterward. Those late-created buttons therefore missed the initial recursive styling pass. Clicking/changing a view eventually passed them through later styling logic, which explains the distinctive "red until clicked, then black" behavior seen in FR1a. FR1b fixes the lifecycle ordering directly by styling those late controls at creation time rather than relying on a later refresh.

v1.0.0 FR1a - First Release 1a / Final RC Consolidation
--------------------------------------------------------
FR1a is the first build to move out of the Release Candidate naming used throughout the long v1.0 stabilization cycle.  The name means "First Release 1a": the feature set and combat model proven through RC6t are now being treated as a coherent release baseline, while the trailing letter leaves room for small first-release maintenance updates without pretending development is finished forever.

Why move from RC to FR here?
- The core physical pipeline has been repeatedly validated in live VanillaPlus combat: UnitDamage-anchored raw swings, Flat DR, stacked percentage DR, armor, block and the one-damage floor all reconcile per event.
- Blessing of Sanctuary ranks 1-4 plus Guardian's Favor were tested while changing ranks in the same fight and now persist correctly through /reload.
- Equipped DR from Amazing Halo and Onyx Egg is read through the BetterCharacterStats/GameTooltip-compatible path and participates in the same event model as talent DR.
- Physical and Magic DR channels are sanitized by the actual event school so physical melee cannot inflate Magic DR after persistence/re-attribution.
- RAW / Physical / Magic Pie views have distinct semantic colors and the Pie updates live during combat using pooled MTPie textures.
- Saved fights carry per-event mitigation snapshots, so historical analysis no longer changes merely because the player later changes gear, talents, buffs, mounts, or reloads the UI.
- Tank sync/Compare, Details, Biggest Hits, Timeline, Pie, Boss, Export and DR inspection are all part of one compact page-managed interface rather than experimental standalone windows.

FR1a finale cleanup / stability audit
------------------------------------
- Reviewed the complete addon rather than changing the already-validated mitigation formulas.
- Kept the existing fight-history cap (20 saved fights) and Tank Compare history cap (200 summaries), which prevent those persistent collections from growing forever.
- Confirmed MTPie.lua pools/reuses wedge textures. Live Pie refresh therefore updates existing textures instead of creating a new frame/texture set on every combat event.
- Kept live Pie redraw throttled rather than redrawing on every combat-log message; Timeline can remain event-driven while Pie batches the heavier wedge redraw.
- Added safe pruning for redundant mitigationContexts. Since RC6s makes modern events self-contained with rc6ContextSnapshot, old context-table entries are removed only when no unsnapshotted event still depends on them. This reduces long-session/SavedVariables bloat without touching the learned contextMemory used for avoidance estimates.
- contextMemory is deliberately NOT aggressively pruned in FR1a: those learned matching-context hit samples are useful mitigation data, not a leak. /mt reset remains the explicit full-data reset.
- Pie close now releases transient hover/tooltip references and pending Pie-refresh state while leaving pooled textures intact for reuse.
- Added recursive final black-button styling for lazily-created child controls so newly-opened analysis pages retain the same sleek UI instead of exposing old UIPanel artwork.
- Added /mt perf (alias /mt health) for a low-cost long-session diagnostic showing current event counts, overall event count, saved fights, retained mitigation contexts, learned context sets and allocated Pie textures.
- Updated the public diagnostic labels to FR1a and made the final version string authoritative after the compatibility layers.

Memory / performance notes
--------------------------
MitigationTracker intentionally stores substantial information because saved fights, event inspection and reload-safe mitigation reconstruction are core features.  Not every growing table is a memory leak. FR1a distinguishes persistent analysis data from accidental retention:

Persistent by design:
- combat events for the current/overall datasets;
- up to 20 saved fights;
- learned contextMemory used by avoidance estimation;
- up to 200 tank-comparison history summaries.

Reused / bounded:
- Pie textures are pooled by MTPie.lua;
- Pie redraw is throttled;
- analysis page frames are lazily created once and reused;
- stale redundant mitigation-context dictionary entries are pruned when events already contain their own snapshots;
- transient Pie hover/tooltip state is cleared when the page closes.

Recommended long-raid check:
    /mt perf

A growing event count during a long encounter is expected. A continuously growing Pie texture count while the same chart is merely updating would NOT be expected and should be reported.

FR1a release principle
----------------------
Do not trade proven combat accuracy for cosmetic refactors.  The release keeps the RC6t math intact and concentrates cleanup on ownership, persistence, UI reuse and diagnostic visibility.  Future math changes should continue to be driven by controlled VanillaPlus combat tests and should preserve the invariant:

    Raw Damage
      = Taken
      + Flat DR
      + Percentage DR
      + Armor
      + Block
      + Resist
      + Absorb

within the integer/rounding limits exposed by the 1.12 combat log.

CURRENT FR1a MITIGATION MODEL
=============================

For a landed event, MitigationTracker attempts to make one internally consistent accounting record:

    Raw Damage
      = Actual Damage Taken
      + Flat DR
      + Percentage DR
      + Armor
      + Block
      + Resist
      + Absorb

Percentage reductions are modeled multiplicatively when multiple independent effects are active.

Example:
    Unbreakability 15%
    Amazing Halo    3%
    Onyx Egg        1%

    Effective DR = 1 - (0.85 * 0.97 * 0.99)
                 ~= 18.37%

Blessing of Sanctuary is treated as a flat per-event cap and, with Guardian's Favor, uses the confirmed active rank. Rank 4's base 30 becomes 36 with Guardian's Favor 2/2.

Avoided attacks and full blocks/full resists remain fundamentally different from landed-hit DR: MitigationTracker estimates the hypothetical attack where necessary, but does not invent Flat/%DR slices for damage that never reached those stages.


DESIGN PRINCIPLES LEARNED ALONG THE WAY
=======================================

1. Prefer exact combat evidence over theory.
   Exact block/resist/absorb amounts from combat text win over estimates.

2. Prefer live UnitDamage ranges when the client exposes them.
   They provide a powerful sanity boundary for white-swing reconstruction.

3. Never let an estimate violate a known range merely to make a formula look neat.

4. Keep historical events self-contained.
   A saved fight should describe the gear, buffs and DR active then, not whatever the player is wearing now.

5. Conditional DR must be active.
   Learning a talent such as a stance/cooldown/pet-dependent reduction is not enough to count it permanently.

6. One event model should feed every UI.
   Main totals, Pie, Timeline, Details, saved fights and Tank Compare should not each invent their own mitigation math.

7. Vanilla 1.12/private-client APIs must be tested, not assumed.
   The BetterCharacterStats tooltip investigation is the clearest example: technically reasonable hidden-tooltip approaches returned incomplete data while the long-lived BCS/GameTooltip path exposed the real custom item text.

8. Keep the UI compact.
   The move to v1.0.0 was fundamentally about turning a powerful but increasingly scattered prototype into one coherent tank-analysis tool.


CURRENT HIGHLIGHTS
==================

- RAW / Physical / Magic mitigation analysis.
- Armor reconstruction and raw incoming damage estimation.
- Dodge / Parry / Miss / Block / partial block analysis.
- Spell resistance, absorbs and magic-school analysis.
- Flat and percentage DR attribution.
- VanillaPlus talent, active-aura and equipped-item DR detection.
- Blessing of Sanctuary rank + Guardian's Favor handling.
- UnitDamage-assisted MH/OH and dual-wield-safe enemy memory.
- Saved fights and Overall analysis.
- One-second Timeline with minute paging.
- Live-updating high-contrast Pie Chart.
- Clickable Pie/Timeline -> Details workflows.
- Event Inspector and Biggest Hits analysis.
- Boss/Encounter analysis.
- Export/share summaries.
- Tank comparison and addon-message fight-summary sync.
- pfUI-Legacy-inspired compact black UI and Mini Mode.
- Reload-safe per-event mitigation context.
- /mt math auditing for validating individual combat equations in the field.


THANK YOU / TESTING NOTE
========================

MitigationTracker's math has been built iteratively from real VanillaPlus combat testing: low-level Swampwalker swings, high-armor tests, Sanctuary rank changes, stacked Unbreakability/Amazing Halo/Onyx Egg DR, active cooldowns, spell damage, blocks, crits, dual-wield concerns, reload persistence and many deliberately awkward edge cases.

That testing is the reason the addon has repeatedly chosen observable combat behavior over assumptions. FR1a is the result of that process: not merely a meter, but an event-by-event explanation of where incoming damage went.

v1.0.0 RELEASE-CANDIDATE SERIES
===============================

RC6t - Reload-Safe Sanctuary + DR School Sanitizer
--------------------------------------------------
- Fixed a reload edge case where Blessing of Sanctuary survived /reload but the short-lived remembered cast rank did not.
- Persists the last confirmed Sanctuary rank in the character profile and restores it before the first post-reload aura scan.
- Can migrate/recover a recent confirmed Sanctuary rank from saved event context when needed.
- The remembered rank is only used while Sanctuary itself is actually active; it cannot create phantom Flat DR after the buff expires.
- Added a hard school-channel invariant for percentage DR attribution:

    Physical event -> percentage DR belongs to Physical DR; Magic DR = 0.
    Magic event    -> percentage DR belongs to Magic DR; Physical DR = 0.

- This fixes persisted/re-attributed events that could otherwise display Magic DR from a purely physical melee mob after reload.
- Does not change the total prevented amount or the proven Flat -> %DR -> Armor -> Block -> Resist/Absorb equations; it sanitizes where that percentage amount is displayed.
- Live testing confirmed that Rank 4 Blessing of Sanctuary + Guardian's Favor remains detected as +36 Flat DR after /reload.

RC6s - Reload-Safe Historical DR / Pie State
--------------------------------------------
- Added a complete mitigation-context snapshot directly to each event.
- Historical Pie/Timeline/Details reconstruction no longer depends only on a second mutable context table or the player's current post-reload aura/gear state.
- Backfills older RC6-era events from persisted context data on reload where possible.
- Old fights therefore remain tied to what was active for THAT hit even after mounting, gear changes, buff changes or /reload.
- Fixed the problem where Pie categories could revert after /reload to older Armor/Avoidance/Blocks-only style totals.

RC6r - Live Updating Pie Chart
------------------------------
- PL13 follow-up: RC6r correctly identified RC6q's older RC6_SumEventDR attribution path as obsolete for display totals, but RC6q itself remained in the GetDisplayData wrapper chain. LAYEREDSTOP3 finally routes that legacy helper through the final RC6B outcome-aware gate so it cannot mutate finalized Full Block events underneath the corrected RC6r totals.
- Made Pie Chart update actively during combat instead of requiring the player to return to MT Main or cycle views.
- Uses the same event-driven concept as Timeline but batches Pie redraws to at most roughly four times per second because pie rendering is heavier.
- MTPie reuses existing textures rather than continuously creating new frames/textures.
- Also corrected school-specific Flat DR aggregation to use the final authoritative RC6 attribution path.
- This is one of the major quality-of-life milestones of the 1.0 line: the mitigation breakdown visibly changes while the fight is happening.

RC6q - School-Specific Flat DR Aggregation
------------------------------------------
- Fixed specialized Physical/Magic display aggregation for all-school Flat DR such as Blessing of Sanctuary.
- RAW shows total Flat DR from all applicable events.
- Physical shows Flat DR spent on physical events.
- Magic shows Flat DR spent on magical events.
- Rebuilt the split totals from event data instead of relying on an incomplete consolidated snapshot.

RC6p - View Button Visual Cleanup
---------------------------------
- Removed remaining red UIPanelButtonTemplate artwork from the Timeline/Pie View selector.
- The selector now visually matches the sleek black MitigationTracker controls instead of showing Blizzard's red button art through the custom skin.

RC6o - Dual-Wield Safety + Compact UI Cleanup
---------------------------------------------
- Audited the new DR math against the older dual-wield model.
- Classic combat text does not identify whether a normal landed white hit was MH or OH, so constraining every white hit to MH alone could incorrectly clamp legitimate off-hand damage.
- Preserved both UnitDamage MH/OH ranges and uses their safe union for normal-white constraints.
- Kept avoidance compatible with the older combined MH/OH memory model.
- Standardized MT buttons to a clean near-black surface while preserving pfUI borders/fonts/hover feedback.
- Unified Timeline and Pie selector wording to the shorter neutral "View: RAW / PHYSICAL / MAGIC" style.
- Tightened the /mt dr layout, including armor/value spacing for five-digit armor totals and compact Effective rows.

RC6n - Sanctuary Rank Continuity Fix
------------------------------------
- Live Swampwalker testing exposed a subtle bug: a confirmed Rank 4 Sanctuary + Guardian's Favor (+36 Flat DR) could later become "rank unresolved" after the short recent-cast window expired.
- Combat inference could then incorrectly choose Rank 3 and credit +24 for one event even though the aura had never changed.
- RC6n made a confirmed Sanctuary rank sticky for the lifetime of that continuous active aura.
- A new confirmed cast/aura can replace it; losing Sanctuary clears it.
- Combat inference became a last resort only when the current continuous aura has never had a confirmed rank.
- This produced stable live Rank 1 -> Rank 4 transitions and fixed the one-hit +24 anomaly.

RC6l-RC6m - High-Contrast Pie Colors
------------------------------------
- Replaced difficult-to-distinguish gray mitigation slices with a semantic high-contrast palette.
- Added exact color keys for Flat DR, Physical DR and Magic DR so those categories no longer fell back to generic gray.
- MTPie.lua already supported per-entry RGB vertex coloring; the fix ensured the data categories actually supplied distinct keys/colors.
- Result: Armor, Flat DR, Physical DR, Magic DR, Avoidance, Blocks and magic-school slices became visually distinguishable at a glance.

RC6k - Consolidated DR Source Model
-----------------------------------
- Folded the proven RC6j item scanner into the main implementation.
- Consolidated Sanctuary Flat DR, passive talent DR, active cooldown DR and equipped-item DR into one per-event mitigation-context model.
- Corrected Rockhide to 2/4/6%.
- Finalized active Shield Wall / Divine Protection / Barkskin aura handling with tooltip-first identification and spellbook-texture fallback for clients whose hidden aura tooltip is incomplete.
- Saved fights retain the mitigation context that existed for the event, so reopening an old fight does not silently use today's gear/talents/buffs.
- Pie, Timeline, Details and saved-fight reconstruction were aligned to this same model.
- Updated stale math-audit generation labels.

RC6g-RC6j - Private-Client Gear Tooltip Scanner Investigation
-------------------------------------------------------------
- RC6g discovered that some 1.12-derived clients populate tooltip text even when SetInventoryItem returns nil/false; scanning stopped trusting that return value as proof of failure.
- RC6h/RC6i diagnostics exposed another client quirk: hidden tooltips could report zero lines or only skeletal text such as "Cloth."
- RC6i probed fixed tooltip FontString lines instead of trusting NumLines().
- RC6j adopted the method that finally worked in live testing: prefer BetterCharacterStats' long-lived tooltip when available, then the player's GameTooltip, with MT's hidden tooltip only as fallback.
- RC6j successfully detected Amazing Halo = 3% All DR and Onyx Egg = 1% All DR.
- This was a good example of why MitigationTracker favors tested client behavior over assumptions about stock 1.12 FrameXML APIs.

RC6f - Active Cooldowns + Equipped Item DR
------------------------------------------
- Added active-aura DR handling for cooldowns such as Shield Wall, Divine Protection and Barkskin rather than treating them as permanent learned-talent DR.
- Confirmed Divine Protection's VanillaPlus effect as 50% all-damage reduction while active (with its separate damage-caused penalty not misread as incoming DR).
- Added equipped-item direct-DR scanning.
- Important live examples:
  Amazing Halo - "Decreases damage taken by 3%..."
  Onyx Egg     - "Decreases damage taken by 1%."
- Updated event math generation so saved/displayed events could be re-attributed consistently through the new DR source model.

RC6e - VanillaPlus Talent Semantics
-----------------------------------
- Kept class-agnostic tooltip discovery but added verified semantics for known VanillaPlus talents where generic text alone was unsafe.
- Added school-specific/passive DR handling and rules for conditional talents.
- Conditional effects such as Shadowform, Tidal Barrier, Soul Link and Master Demonologist are not counted merely because the talent is learned.
- Corrected/expanded rules from live talent-calculator research, including the later Rockhide correction to 2/4/6%.
- Added /mt drscan / /mt talentdr diagnostics.

RC6d - Rank-Aware Blessing of Sanctuary
---------------------------------------
- Addressed the fact that Vanilla 1.12 aura APIs/textures may identify Sanctuary without reliably exposing its rank.
- Sanctuary rank resolution uses active aura information first, then the exact locally cast spell rank, then constrained combat inference only as a fallback.
- Never assumes "highest learned rank" equals "currently active rank."
- Added hard raw-range safety to keep Sanctuary inference from producing impossible enemy swings.

RC6b-RC6c - Constrained / Crit-Aware Reconstruction
---------------------------------------------------
- Made live UnitDamage white-swing ranges the strongest raw anchor when available.
- Prevented normal white hits from being inflated outside the observed raw range merely to make inverse math balance.
- Added crit-aware reconstruction so critical white hits can exceed the normal range without corrupting normal swing constraints.
- Changed separate percentage-DR effects to stack multiplicatively instead of simply adding percentages.
- Example verified model: 15%, 3% and 1% reductions combine as 1-(0.85*0.97*0.99), about 18.37% effective DR.
- Event records became the authoritative source for headline totals and visual analysis.

RC6 - Unified DR Attribution Math
---------------------------------
- Reworked landed-hit accounting around the tested Vanilla/VanillaPlus order:

    Raw
      -> Flat damage reduction
      -> Percentage damage reduction
      -> Armor
      -> Block
      -> Resist / Absorb
      -> Actual damage taken

- Blessing of Sanctuary is treated as all-damage Flat DR on VanillaPlus based on live testing.
- Flat DR is a per-event cap, not an amount blindly credited to every hit.
- Low saturated hits respect the observed 1-damage floor.
- Dodge/parry/miss/full block/full resist do not receive artificial DR slices.
- Existing exact block/resist/absorb values remain authoritative.
- Landed events are expected to satisfy, within integer rounding:

    Raw = Taken + Flat DR + %DR + Armor + Block + Resist + Absorb

- RAW/Taken/Stopped, Pie, Timeline, Details and Tank Compare were moved toward deriving from the same attributed event records.
- Added /mt math / /mt drmath auditing so individual equations could be verified against live mobs.

RC5b-RC5f - VanillaPlus Defensive-Effect Discovery
--------------------------------------------------
- Added/expanded detection for VanillaPlus defensive effects including Blessing of Sanctuary, Guardian's Favor, Unbreakability, Shield of Faith, Improved Defensive Auras and generic direct-DR wording.
- Added class-agnostic learned-talent tooltip scanning so mitigation discovery was not hard-coded only to Paladin.
- Distinguished passive direct DR from conditional effects that must actually be active.
- Added a dedicated Mitigation DR page inside the managed MT UI rather than a detached diagnostic window.
- /mt dr became the compact Armor / Flat DR / Physical DR / Magic DR inspection page.
- This work was informed by a broader VanillaPlus talent-calculator review for wording such as "reduces damage," "decreases damage taken," and school-specific damage reduction.

RC5 - Fight-History Sync + Mitigation Context
---------------------------------------------
- Compare began storing/syncing fight history rather than only each player's latest summary.
- Added < / > encounter paging, including repeated fights against the same enemy.
- Sync Now can send up to the last 20 saved fights to recover comparison history after reconnects/missed messages.
- Added Mitigation Context snapshots containing current armor, recognized defensive buffs, defensive talents and observable current-target debuffs.
- Context-matched landed hits became preferred evidence for avoidance/full-block/full-resist estimates, with confidence metadata.
- Event Inspector gained context/estimate-source information.
- Added /mt context and the beginnings of /mt dr diagnostics.
- Enemy debuffs are intentionally only trusted when the attacker is the current target; MitigationTracker reports that limitation instead of guessing.

RC4 / RC4b - Tank Comparison + Sync
-----------------------------------
- Added tank-comparison architecture using compact end-of-fight summaries rather than attempting to synchronize every raw event.
- Addon-message sync was chosen because another tank's complete incoming combat information is not reliably visible to the local client.
- Added Compare fight rows/ranking around Raw, Taken, Stopped and Mitigation.
- Fixed Details event paging.
- RC4b moved Compare to the centered position above Export/Boss so it no longer clipped Details and reasserted stable compact navigation anchors.

RC3 / RC3b - Boss / Encounter Analysis
--------------------------------------
- Added Boss / Encounter Mitigation Breakdown.
- Added persistent skull-level Boss Profiles/browser behavior so notable encounters could be revisited as mitigation records rather than being indistinguishable from ordinary trash fights.

RC2 / RC2b / RC2c - Export + UI Styling
---------------------------------------
- Added export/share fight summaries.
- Fixed Vanilla-client incompatibilities such as cursor-position APIs and chat pipe escaping encountered by Export.
- Unified Timeline, Biggest, Pie Chart, Details and Export through the same pfUI-Legacy-inspired button typography/styling path.
- RC2c normalized main navigation button visuals.

RC1c-RC1k - Single-Window Polish
--------------------------------
- Repeatedly hardened anchors, bottom-right positioning and Mini Mode transitions.
- Added an authoritative page manager so only the intended MT page remains visible.
- Restored a real clickable Details event list after early compact-layout iterations had over-compressed it.
- Added SavedVariables size warnings and reset controls as combat history became more substantial.
- De-layered/cleaned the compact Details event area and improved Event Inspector interaction.
- These letter builds were primarily about making the v1.0 architecture safe on the old client rather than adding new mitigation math.

RC1g - UnitDamage Enemy Memory Upgrade
--------------------------------------
- Made UnitDamage("target") the preferred source for enemy MH/OH damage ranges when available.
- Kept observed-combat memory as fallback.
- Improved dual-wield awareness so enemy white-swing estimation could use both weapon ranges instead of assuming every mob had one main-hand range.

RC1a-RC1b - Vanilla 1.12 Compatibility / Page Leakage Fixes
-----------------------------------------------------------
- Removed use of modern SetEnabled() behavior unavailable in Vanilla 1.12.1.
- Centralized page hiding so old/legacy popup frames could not leak through the new single-window navigation system.

v1.0.0 RC1 - Single-Window UI Rewrite
-------------------------------------
- Rebuilt MitigationTracker around one compact analysis footprint rather than multiple simultaneous floating windows.
- Summary/Main, Pie, Timeline, Details and Biggest analysis replace one another in the same location.
- Added an MT Main return path.
- Standardized shared position/drag/close behavior.
- Timeline retained one-second buckets but pages long fights by minute (0-60, 60-120, 120-180, etc.) with < / > navigation.
- Mini Mode remained manually available; automatic combat shrinking was intentionally OFF by default and opt-in through /mt automini.
- Preserved the existing parser, saved fights, timeline, charts, Details, Biggest Hits, Event Inspector, Current/Overall/saved-fight datasets and fight naming beneath the new UI.

WHY v1.0.0?
============

MitigationTracker did not move to v1.0.0 because every possible feature was finished. It moved to v1.0.0 because the underlying parser/data model had become a real, usable analyzer and the largest remaining weakness was UI cohesion.

By the end of the v0.x line the addon already had:
- Physical and magical mitigation tracking.
- Armor, block, avoidance, resist and absorb accounting.
- Enemy/attack memory and UnitDamage-assisted estimates.
- Saved fights and persistent combat data.
- One-second event timelines.
- Pie charts.
- Details/Event Inspector and Biggest Hits analysis.
- Meaningful fight naming and fight history.

The v0.x prototype had accumulated several separate floating analysis windows. The v1.0 goal therefore became consolidation: one compact MitigationTracker-sized analysis frame, one position, one visual language, and pages that replace one another instead of covering the screen with windows. That UI rewrite was substantial enough to mark the transition from experimental feature-building to the 1.0 release-candidate series.

VERSION HISTORY
===============

v0.9.9 - Graph Engine Experiment -> Standalone Pie Renderer
-----------------------------------------------------------
- Experimented with an embedded GraphLib-style pie engine inspired by existing Vanilla addon graph libraries.
- Encountered library/Ace compatibility problems (including missing MTGraph-style library instances) on the target 1.12 environment.
- Chose reliability over dependency complexity and moved toward MitigationTracker's own standalone pie renderer.
- The standalone renderer eventually became MTPie.lua and the reusable pie textures shipped with the addon.

v0.9.8 - Pie / Block / pfUI-Legacy Polish
-----------------------------------------
- Pursued cleaner filled DPSMate-style pie charts instead of the earlier rough/grainy presentation.
- Improved Block Analysis presentation and restored useful VanillaPlus tooltip/details information after UI iterations.
- Continued pfUI Legacy-inspired styling: compact black/transparent panels, cleaner borders and typography, and a UI intended to sit naturally beside addons such as DPSMate/KTM.
- Added/continued Mini Mode work for a smaller combat footprint.

v0.9.5 - Spike / Dangerous-Second Analysis Iteration
----------------------------------------------------
- Continued work toward identifying damage spikes and dangerous seconds rather than only fight-wide averages.
- Extended the idea that a tank analyzer should answer not just "how much was mitigated?" but "when did the dangerous damage happen?"

v0.9.1 - Analysis Window Consolidation
--------------------------------------
- Removed redundant Biggest-Hits popup behavior and reused the existing Timeline/analysis flow.
- Improved Inspector integration.
- Prevented duplicate analysis windows from stacking on top of one another.
- This was an early signal that MitigationTracker's feature set had outgrown its original multi-window UI.

v0.9.0 - Event Inspector / Timeline Cursor / Biggest Hits
--------------------------------------------------------
- Added Event Inspector for examining individual recorded hits and their mitigation components.
- Added a Timeline cursor for moving through a fight precisely.
- Added Biggest Hits analysis to quickly locate dangerous incoming events.
- Combat Replay was deliberately skipped; the goal was useful analysis without unnecessary complexity.

v0.8.3 - Combat Explorer / Fight Identity
-----------------------------------------
- Added meaningful fight names based on the primary/top incoming-damage enemy, including repeated/multi-enemy naming behavior.
- Improved /mt fights output.
- Remembered analysis-window positions.
- Added an event list beneath Details.
- Added foundations for replay-style inspection without committing to a full combat replay system.

v0.8.2 - Clickable Timeline Buckets
-----------------------------------
- Timeline buckets became interactive.
- Clicking a time range could filter Details to the events occurring in that bucket.
- Timeline and Details were now parts of the same analysis workflow rather than unrelated windows.

v0.8.1 - Clickable Pie Slices
-----------------------------
- Pie slices became interactive.
- Clicking a mitigation category could open/filter Details to the events behind that slice.
- This linked the visual summary to the underlying combat evidence.

v0.8.0 - Enemy / Ability Details
--------------------------------
- Added deeper enemy/ability breakdowns so the player could move from a graph total to the attacks responsible for it.
- Established the Details analysis path later used by clickable Pie slices, Timeline buckets and the Event Inspector.

v0.7.2 - Persistent Combat History
----------------------------------
- Persisted Current, Overall, events, timeline data, learned enemy information, display modes and the latest 20 fights in SavedVariables.
- Added /mt reset, /mt resetfight, /mt fights and /mt fight <n> workflows.
- Saved fights became real analysis objects rather than temporary data lost on reload/logout.

v0.7.1 - Timeline/Pie Usability
-------------------------------
- Fixed full-fight Timeline display/compression behavior.
- Improved Magic pie school memory with an Unknown fallback where school information was unavailable.
- Moved the Pie control beside the close control and continued smoothing the graph renderer/UI.

v0.7.0 - Timeline + Pie Analysis
--------------------------------
- Expanded the Timeline to a readable ~180px analysis view.
- Added RAW, Physical and Magic pie-chart analysis.
- Added hover values and Current / Overall / saved-fight dataset support.
- Began turning the raw event database into visual analysis instead of requiring chat/debug output to understand a fight.

v0.6.1 - Reliable Block-Value Gear Scanning
-------------------------------------------
- Reworked shield/equipment tooltip scanning through SetInventoryItem -> item hyperlink -> SetHyperlink fallbacks.
- Added retries after login, gear/stat/aura/talent changes.
- Added /mt blockrefresh.
- Kept block-value learning independent from ordinary fight/timeline resets.

v0.6.0 - Event / Timeline Engine
--------------------------------
- Introduced timestamped event records for landed attacks, DoTs, avoidance, blocks and resists.
- Added one-second timeline buckets.
- Saved timeline information with fight data.
- Added a live Timeline analyzer with modes for ALL/RAW/TAKEN/ARMOR/BLOCK/AVOID/MAGIC during the early implementation.
- Added /mt timeline and /mt events diagnostics.
- This event stream became one of the most important architectural changes in the addon: later Pie, Details, DR attribution and saved-fight analysis could all derive from individual combat events.

v0.5.0 - Adaptive Block Learning
--------------------------------
- Separated Base Block Value from observed block results.
- Added observed minimum, average and maximum block values overall and per enemy.
- Added /mt blocks diagnostics.
- Allowed live combat evidence to reveal VanillaPlus/custom-server block behavior instead of forcing retail-Vanilla assumptions onto the data.

v0.4.x - Mitigation Math / Block Analysis Iteration
---------------------------------------------------
- Continued live testing of armor reconstruction, avoided-hit estimates and block accounting against VanillaPlus combat behavior.
- Improved distinction between exact mitigation supplied by combat text and estimated mitigation reconstructed from enemy memory.
- Refined block-value presentation and the idea of separating a calculated/current block value from what combat had actually demonstrated.
- These builds laid the groundwork for adaptive block learning rather than assuming one static theoretical block number was always correct on a custom server.

v0.3.0 - RAW / PHYSICAL / MAGIC Pages
-------------------------------------
- Split the compact meter into three focused views:
  RAW      - incoming damage, actual damage taken, stopped damage, armor and absorbs.
  PHYSICAL - dodge, parry, miss, block and physical avoidance details.
  MAGIC    - spell mitigation and resistance details.
- Kept the same fight data while switching pages rather than creating independent datasets.
- Absorbs remained part of RAW accounting so prevented damage could not disappear merely because its source was a shield.

v0.2.0 - Raw Incoming Damage / UnitDamage Foundation
----------------------------------------------------
- Added automatic UnitDamage("target") main-hand damage-range reading when the current attacker could be queried.
- Made the enemy's known raw swing range a stronger anchor for avoidance and raw-damage estimation.
- Formalized the armor-before-avoidance/raw reconstruction flow used by later versions.
- Expanded the main display around RAW Damage In, Damage Stopped, mitigation efficiency, armor, block, resist and absorb totals.
- Added reporting/debugging for learned enemy damage memory.
- This was the point where MitigationTracker began behaving like a mitigation calculator rather than only a combat-text counter.

v0.1.2 - Parser/Attack Memory Separation
----------------------------------------
- Corrected parser ordering problems.
- Separated named physical abilities such as Crusader Strike from white-melee swing memory so special attacks could not distort the learned normal melee range.

v0.1.1 - Full Block Parsing
---------------------------
- Fixed classic combat messages such as "You block" that represent a fully blocked attack.
- Full blocks now receive an estimated prevented amount while partial blocks continue to use their exact combat-log value.

v0.1.0 - First Working MitigationTracker
----------------------------------------
- Initial incoming-damage parser and movable mitigation meter.
- Recorded exact partial blocks, partial resists and absorbs when combat text supplied exact values.
- Estimated damage prevented by dodge, parry, miss and full spell resists when no landed-damage number existed.
- Added per-enemy/per-attack memory so avoided attacks could be assigned a reasonable hypothetical raw value instead of simply counting as zero.
- Excluded critical hits from normal-hit learning where appropriate so crits would not poison normal enemy swing estimates.
- Added pending-avoidance handling, current/last-fight state, session memory, slash commands and debug output.
- Established the core design principle that MitigationTracker should separate damage actually taken from damage prevented rather than merely count combat-table outcomes.
