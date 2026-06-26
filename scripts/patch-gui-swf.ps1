# patch-gui-swf.ps1 — Surgical JPEXS P-code patch for the Ranked-match crash (issue #1006).
#
#   *** SHELF PATCH — produces a patched COPY; it does NOT install anything. ***
#
# WHAT IT DOES
#   Fixes the "TypeError: value is not a function" crash that fires the moment a player clicks
#   "Ranked" in the Great Hall. The fix is a single AVM2 bytecode instruction swap inside the
#   resource SWF  gui\great_hall.swf , in
#   game.gui.pages.GuiGreatHallBannerVersus.rankedMatchHandler:
#
#       callproperty  ...IPartyDef::totalPower, 0      (call totalPower as a method)
#   ->  getproperty   ...IPartyDef::totalPower         (read totalPower as a getter)
#
#   Both pop the PartyDef receiver and push one int — identical stack effect — so the following
#   convert_i / setlocal2 are unaffected. Nothing else in the SWF changes.
#
# SCOPE — this covers ONE of the three #1006 sites in great_hall.swf (KNOWN GAP)
#   It patches only GuiGreatHallBannerVersus.rankedMatchHandler (the Ranked button). The SAME
#   getter-as-function bug exists, UNPATCHED, at two more sites in the same SWF — a different
#   class, so different method-body indices that index 777 does not touch:
#       GuiGreatHallBannerTournament.onTourneyBannerClick   (GuiGreatHallBannerTournament.as:208)
#       GuiGreatHallBannerTournament.onJoinClick            (GuiGreatHallBannerTournament.as:251)
#   Both call context.party.totalPower() as a function and will throw the same #1006 once the
#   Tournament UI is reachable. Tournament is also online-only, so it is shelved for the same
#   reason — but BEFORE enabling Tournament, extend this script with a -replace for each (derive
#   their indices the same way 777 was; see "HOW THE METHOD-BODY INDEX ... WAS DERIVED" below).
#
# WHY A BYTECODE PATCH (and not a src/ patch + build.ps1)
#   great_hall.swf is a SEPARATE resource SWF loaded at runtime; build.ps1 only rebuilds
#   app.game.air.swf and never touches it. The crashing class is symbol-linked INSIDE
#   great_hall.swf, so the town screen instantiates that stale copy regardless of any app-side
#   rebuild — see docs/architecture.md -> "Resource SWFs and runtime class resolution".
#   A refactor turned PartyDef.totalPower from a method into a getter. Modern callers read it as
#   a property; this stale resource-SWF caller still CALLS it, so AVM2 invokes the getter, gets
#   an int, then tries to call the int as a function -> TypeError. The getter must stay (modern
#   callers depend on it), so the only correct fix is to patch this one stale call site.
#
# WHY "DO NOT APPLY" (shelved)
#   Ranked is online-only. The offline player-vs-AI build never reaches a live Ranked queue, so
#   the crash isn't hit in normal play. This script is kept ready on the shelf for if/when Ranked
#   is enabled. See bsf-client/misc/Plan-Fix-Issue-12-ai-battle-init-hang.md.
#
# HOW THE METHOD-BODY INDEX (777) WAS DERIVED
#   JPEXS -replace addresses AS3 method bodies by their GLOBAL index in the SWF's ABC. 777 is
#   GuiGreatHallBannerVersus.rankedMatchHandler in the shipped great_hall.swf (v1.10.51). It is
#   intrinsic to that fixed 2013 asset and does not drift across JPEXS versions. The verification
#   step below ABORTS (and deletes the output) rather than emit a bad patch if 777 ever
#   mis-points — e.g. if great_hall.swf is ever replaced. To re-derive: export the class P-code
#   and sweep -replace indices until the only change is this call site losing its "callproperty".
#
# TO APPLY LATER (manual; only if Ranked is turned on)
#   1. Back up the original :  Copy-Item "<install>\gui\great_hall.swf" "<install>\gui\great_hall.swf.bak"
#   2. Overwrite with patch :  Copy-Item "<repo>\_build\great_hall.patched.swf" "<install>\gui\great_hall.swf"
#   (<install> = %ProgramFiles(x86)%\Steam\steamapps\common\The Banner Saga Factions)
#
# Usage:
#   .\scripts\patch-gui-swf.ps1
#   .\scripts\patch-gui-swf.ps1 -SwfPath "D:\...\gui\great_hall.swf" -OutPath "D:\out\great_hall.patched.swf"

param(
    [string]$SwfPath  = (Join-Path ${env:ProgramFiles(x86)} "Steam\steamapps\common\The Banner Saga Factions\gui\great_hall.swf"),
    [string]$OutPath,
    [string]$FfdecJar = (Join-Path ${env:ProgramFiles(x86)} "FFDec\ffdec.jar")
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path $PSScriptRoot
if (-not $OutPath) { $OutPath = Join-Path $RepoRoot "_build\great_hall.patched.swf" }

# The one instruction to swap, as P-code text. Single-quoted so the inner " stay literal.
$TargetClass     = "game.gui.pages.GuiGreatHallBannerVersus"
$ScriptRelPath   = "scripts\game\gui\pages\GuiGreatHallBannerVersus.pcode"   # JPEXS export layout
$MethodName      = "rankedMatchHandler"
$MethodBodyIndex = 777
$CallPcode = 'callproperty QName(Namespace("engine.entity.def:IPartyDef"),"totalPower"), 0'
$GetPcode  = 'getproperty QName(Namespace("engine.entity.def:IPartyDef"),"totalPower")'
# NOTE for anyone copying this as a template: the verification below counts these two as literal
# (-SimpleMatch) needles, so they must NOT be substrings of each other. They aren't here
# ("getproperty" is not a substring of "callproperty"); pick opcodes with that property.

function Invoke-Ffdec {
    param([string[]]$FfdecArgs)
    $out = & java -jar $FfdecJar @FfdecArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host ($out -join "`n")
        throw "JPEXS failed (exit $LASTEXITCODE): ffdec $($FfdecArgs -join ' ')"
    }
    return $out
}

# Count literal (non-regex) occurrences of a string across an array of lines.
function Get-MatchCount { param($Lines, [string]$Needle) return @($Lines | Select-String -SimpleMatch $Needle).Count }

# ── 0. Preconditions ──────────────────────────────────────────────────────────
if (-not (Test-Path $FfdecJar)) { Write-Error "JPEXS not found at '$FfdecJar'. Install FFDec or pass -FfdecJar."; exit 1 }
if (-not (Test-Path $SwfPath))  { Write-Error "great_hall.swf not found at '$SwfPath'. Pass -SwfPath."; exit 1 }
if (-not (Get-Command java -ErrorAction SilentlyContinue)) { Write-Error "Java not found on PATH (JPEXS needs it)."; exit 1 }

Write-Host "Input  (read-only): $SwfPath"
Write-Host "Output (patched)  : $OutPath"
Write-Host ""

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("bsf-patch-gui-swf-" + [System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $work -Force | Out-Null

try {
    # Hash the input up front so we can prove at the end we never modified the original. Safety is by
    # construction — the install path is only ever a JPEXS *input*, never an output — and this hash
    # re-check is the proof of that, not an OS-level lock.
    $inHashBefore = (Get-FileHash -Algorithm SHA256 $SwfPath).Hash

    # ── 1. Export the target class P-code from the (unmodified) input ──────────
    $preDir = Join-Path $work "pre"
    Invoke-Ffdec @("-selectclass", $TargetClass, "-format", "script:pcode", "-export", "script", $preDir, $SwfPath) | Out-Null
    $preFile = Join-Path $preDir $ScriptRelPath
    if (-not (Test-Path $preFile)) { throw "Could not export $TargetClass from the input SWF." }
    $preLines = Get-Content $preFile

    # ── 2. Confirm the expected stale state (exactly one callproperty totalPower) ──
    #   This class (GuiGreatHallBannerVersus) has exactly ONE totalPower() call site
    #   (rankedMatchHandler), so a healthy stale input has count == 1 — the count-1 guard relies on
    #   that. (The two Tournament call sites are in a different SWF script, so they don't appear in
    #   this class's export — see the SCOPE note in the header.) Any other count means this isn't the
    #   expected SWF or index 777 has drifted → abort rather than risk patching the wrong method.
    $callCount = Get-MatchCount $preLines $CallPcode
    if ($callCount -ne 1) {
        throw ("Expected exactly 1 stale '$CallPcode' in the input, found $callCount. " +
               "This is not the expected stale great_hall.swf; aborting (method index $MethodBodyIndex may not apply).")
    }

    # ── 3. Extract the rankedMatchHandler 'method ... end ; method' block ──────
    #   The WHOLE method block, not just its body: importing only the body drops the
    #   param signature (-> 0-param method called with 1 arg -> AVM2 #1063 at click time).
    $traitIdx = -1
    for ($i = 0; $i -lt $preLines.Count; $i++) {
        if ($preLines[$i] -match ('trait method .*"' + [regex]::Escape($MethodName) + '"\)')) { $traitIdx = $i; break }
    }
    if ($traitIdx -lt 0) { throw "Trait method '$MethodName' not found in $TargetClass." }

    $mStart = -1
    for ($i = $traitIdx; $i -lt $preLines.Count; $i++) { if ($preLines[$i].Trim() -eq "method") { $mStart = $i; break } }
    if ($mStart -lt 0) { throw "'method' keyword not found after trait '$MethodName'." }

    $depth = 0; $mEnd = -1
    for ($i = $mStart; $i -lt $preLines.Count; $i++) {
        $t = $preLines[$i].Trim()
        if ($t -eq "method") { $depth++ }
        elseif ($t -eq "end ; method") { $depth--; if ($depth -eq 0) { $mEnd = $i; break } }
    }
    if ($mEnd -lt 0) { throw "Unterminated 'method' block for '$MethodName'." }
    $block = $preLines[$mStart..$mEnd]

    # ── 4. Apply the swap inside the extracted block ──────────────────────────
    $block = $block | ForEach-Object { $_ -replace [regex]::Escape($CallPcode), $GetPcode }
    if ((Get-MatchCount $block $GetPcode)  -ne 1) { throw "Swap did not apply cleanly (getproperty not present once)." }
    if ((Get-MatchCount $block $CallPcode) -ne 0) { throw "Stale callproperty still present after swap." }
    $importFile = Join-Path $work "rankedMatchHandler.pcode"
    Set-Content -Path $importFile -Value $block -Encoding ascii

    # ── 5. Replace method body 777 -> write the patched COPY (input untouched) ──
    New-Item -ItemType Directory -Path (Split-Path $OutPath) -Force | Out-Null
    Invoke-Ffdec @("-replace", $SwfPath, $OutPath, $TargetClass, $importFile, "$MethodBodyIndex") | Out-Null
    if (-not (Test-Path $OutPath)) { throw "JPEXS did not produce '$OutPath'." }

    # ── 6. Verify the patched copy ────────────────────────────────────────────
    $postDir = Join-Path $work "post"
    Invoke-Ffdec @("-selectclass", $TargetClass, "-format", "script:pcode", "-export", "script", $postDir, $OutPath) | Out-Null
    $postFile = Join-Path $postDir $ScriptRelPath
    if (-not (Test-Path $postFile)) { throw "Could not re-export $TargetClass from the patched copy." }
    $postLines = Get-Content $postFile

    $okGet  = (Get-MatchCount $postLines $GetPcode)  -eq 1
    $okCall = (Get-MatchCount $postLines $CallPcode) -eq 0
    $okSig  = (Get-MatchCount $postLines "rankedMatchHandler(param1:ButtonWithIndex)") -ge 1

    # Strong guard: the ONLY lines allowed to differ pre vs post are the swapped instruction and
    # the auto-renumbered jump-offset labels (every such line contains 'totalPower' or 'ofs').
    $unexpected = @()
    Compare-Object $preLines $postLines | ForEach-Object {
        $l = $_.InputObject.Trim()
        if ($l -notmatch "totalPower" -and $l -notmatch "ofs[0-9A-Fa-f]+") { $unexpected += $l }
    }

    $okUntouched = ((Get-FileHash -Algorithm SHA256 $SwfPath).Hash -eq $inHashBefore)

    Write-Host "Verification:"
    Write-Host ("  swap applied (getproperty present) : {0}" -f $okGet)
    Write-Host ("  stale call removed                 : {0}" -f $okCall)
    Write-Host ("  method signature preserved         : {0}" -f $okSig)
    Write-Host ("  no other lines changed             : {0}" -f ($unexpected.Count -eq 0))
    Write-Host ("  input SWF byte-identical (untouched): {0}" -f $okUntouched)

    if (-not ($okGet -and $okCall -and $okSig -and ($unexpected.Count -eq 0) -and $okUntouched)) {
        if ($unexpected.Count -gt 0) { Write-Host ("  unexpected diffs:`n    " + ($unexpected -join "`n    ")) -ForegroundColor Red }
        Remove-Item $OutPath -Force -ErrorAction SilentlyContinue
        throw "Verification FAILED — patched copy deleted, nothing applied. (Re-derive the method index? see header.)"
    }

    Write-Host ""
    Write-Host "SUCCESS — surgical patch verified (one instruction swapped, input untouched)." -ForegroundColor Green
    Write-Host "Patched copy: $OutPath"
    Write-Host ""
    Write-Host "NOT installed — this is a shelf patch (Ranked is online-only)." -ForegroundColor Yellow
    Write-Host "To apply later, back up then overwrite the install copy:"
    Write-Host "  Copy-Item `"$SwfPath`" `"$SwfPath.bak`""
    Write-Host "  Copy-Item `"$OutPath`" `"$SwfPath`""
}
finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}
