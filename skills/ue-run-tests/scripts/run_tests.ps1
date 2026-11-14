# Copyright LifeEXE. All Rights Reserved.
# Builds the editor target, runs Unreal automation tests headless and reports the results.
#   run_tests.ps1 -ProjectPath C:\Game                         # tests matching the project name (or config.bat TestNames)
#   run_tests.ps1 -ProjectPath C:\Game -Filter "Game.Weapon"    # tests whose path starts with/contains the filter
#   run_tests.ps1 -ProjectPath C:\Game -List                    # list matching tests, don't run
#   run_tests.ps1 -ProjectPath C:\Game -Coverage -JUnit         # + OpenCppCoverage html/cobertura, + JUnit xml for CI
#   run_tests.ps1 -ProjectPath C:\Game -NewSpec WeaponComponent -Dir Tests\Weapon   # new spec file from the devops_ue template
#   run_tests.ps1 -ProjectPath C:\Game -NewTest WeaponMath -Dir Tests               # new legacy test (.h/.cpp)
[CmdletBinding()]
param(
    [string]$ProjectPath = '.',
    [string]$Filter = '',
    [switch]$List,
    [switch]$Coverage,
    [switch]$JUnit,
    [switch]$SkipBuild,
    # run with a real RHI (screenshot/rendering tests); default -nullrhi
    [switch]$WithRHI,
    [string]$NewSpec = '',
    [string]$NewTest = '',
    [string]$Dir = 'Tests',
    [string]$EnginePath = '',
    [int]$TimeoutMinutes = 60
)

$ErrorActionPreference = 'Stop'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Warnings = New-Object System.Collections.ArrayList

# --- step timing (same block in every devops_ue skill script) ---
$ScriptTimer = [Diagnostics.Stopwatch]::StartNew()
$StepTimes = New-Object System.Collections.ArrayList
$script:CurrentStep = $null
function Complete-Step {
    if ($script:CurrentStep) {
        [void]$StepTimes.Add([pscustomobject]@{ Step = $script:CurrentStep.Name; Time = $ScriptTimer.Elapsed - $script:CurrentStep.Start })
        $script:CurrentStep = $null
    }
}
function Write-Step([string]$Text) {
    Complete-Step
    $script:CurrentStep = [pscustomobject]@{ Name = $Text; Start = $ScriptTimer.Elapsed }
    Write-Host ''; Write-Host "==> $Text" -ForegroundColor Cyan
}
function Write-FinalStep([string]$Text) { Complete-Step; Write-Host ''; Write-Host "==> $Text" -ForegroundColor Cyan }
function Format-Duration([TimeSpan]$T) {
    if ($T.TotalHours -ge 1) { return '{0}h {1:D2}m {2:D2}s' -f [int][math]::Floor($T.TotalHours), $T.Minutes, $T.Seconds }
    if ($T.TotalMinutes -ge 1) { return '{0}m {1:D2}s' -f $T.Minutes, $T.Seconds }
    return '{0:N1}s' -f $T.TotalSeconds
}
function Write-Timing([string]$Result = 'total') {
    Complete-Step
    Write-Host ''; Write-Host 'Time:' -ForegroundColor Cyan
    foreach ($s in $StepTimes) { Write-Host ('  {0,-10} {1}' -f (Format-Duration $s.Time), $s.Step) }
    Write-Host ('  {0,-10} {1}' -f (Format-Duration $ScriptTimer.Elapsed), $Result) -ForegroundColor Green
}
trap { Write-Timing 'total (FAILED)'; break }
function Add-Warning([string]$Text) { [void]$Warnings.Add($Text); Write-Host "WARNING: $Text" -ForegroundColor Yellow }
function Read-Text([string]$Path) { [IO.File]::ReadAllText($Path) }
function Write-Text([string]$Path, [string]$Text) {
    $d = Split-Path -Parent $Path; if ($d -and -not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, $Utf8NoBom)
}

# reads a file another process may still hold open for writing
function Read-SharedLines([string]$Path) {
    $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try { $text = (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
    return @($text -split "`r?`n")
}

# runs a process, streams its output and keeps it in $LogFile; returns the exit code (-1 on timeout)
function Invoke-Logged([string]$FilePath, [string]$Arguments, [string]$LogFile, [int]$TimeoutMin = 0) {
    $dir = Split-Path -Parent $LogFile; if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $errFile = "$LogFile.stderr"
    $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -NoNewWindow -PassThru -RedirectStandardOutput $LogFile -RedirectStandardError $errFile
    $null = $p.Handle
    $pos = 0L; $started = Get-Date
    while ($true) {
        $exited = $p.HasExited
        if (Test-Path -LiteralPath $LogFile) {
            $fs = [IO.File]::Open($LogFile, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            try { [void]$fs.Seek($pos, [IO.SeekOrigin]::Begin); $sr = New-Object IO.StreamReader($fs); $chunk = $sr.ReadToEnd(); $pos = $fs.Position } finally { $fs.Dispose() }
            if ($chunk) { Write-Host -NoNewline $chunk }
        }
        if ($exited) { break }
        if ($TimeoutMin -gt 0 -and ((Get-Date) - $started).TotalMinutes -gt $TimeoutMin) {
            Add-Warning "Timeout after $TimeoutMin min: stopping $FilePath"
            try { Stop-Process -Id $p.Id -Force } catch { }
            return -1
        }
        Start-Sleep -Milliseconds 700
    }
    $p.WaitForExit()
    if (Test-Path -LiteralPath $errFile) {
        # processes the tool starts (UnrealZenServer, ShaderCompileWorker) inherit the redirected handles and may keep them open
        try {
            $e = (Read-SharedLines $errFile) -join "`r`n"
            if ($e.Trim()) { Write-Host $e; try { Add-Content -LiteralPath $LogFile -Value $e -ErrorAction Stop } catch { } }
        } catch { }
        try { Remove-Item -LiteralPath $errFile -Force -ErrorAction Stop } catch { }
    }
    return $p.ExitCode
}
function Invoke-BatLogged([string]$BatPath, [string]$Arguments, [string]$LogFile) {
    return Invoke-Logged $env:ComSpec "/d /s /c `"`"$BatPath`" $Arguments < nul`"" $LogFile
}
function Get-ConfigValue([string]$ConfigBat, [string]$Name) {
    if (-not (Test-Path -LiteralPath $ConfigBat)) { return '' }
    $v = [IO.File]::ReadAllLines($ConfigBat) | Where-Object { $_ -match "^set $([regex]::Escape($Name))=(.*)$" } | ForEach-Object { $Matches[1].Trim() } | Select-Object -First 1
    return "$v"
}
function Resolve-ProjectEngine([string]$Root, [string]$Assoc, [string]$Explicit) {
    if ($Explicit) { return (Resolve-Path -LiteralPath $Explicit).Path.TrimEnd('\') }
    $e = Get-ConfigValue (Join-Path $Root 'devops_data\config.bat') 'EnginePath'
    if ($e -and (Test-Path -LiteralPath (Join-Path $e 'Engine\Build\Build.version'))) { return $e.TrimEnd('\') }
    $common = Join-Path $PSScriptRoot '..\..\ue-create-project\scripts\ue_common.ps1'
    if (Test-Path -LiteralPath $common) {
        . $common
        $m = Get-UnrealEngines | Where-Object { $_.Association -eq $Assoc -or $_.MajorMinor -eq $Assoc } | Select-Object -First 1
        if ($m) { return $m.Path }
    }
    throw "Engine for EngineAssociation '$Assoc' not found: pass -EnginePath"
}

# ---------------------------------------------------------------------------------------------
Write-Step 'Project'
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$ProjectRoot = if ($ProjectPath -like '*.uproject') { Split-Path -Parent $ProjectPath } else { $ProjectPath }
$uprojectFile = Get-ChildItem -LiteralPath $ProjectRoot -Filter '*.uproject' -File | Select-Object -First 1
if (-not $uprojectFile) { throw "No .uproject in $ProjectRoot" }
$UProjectPath = $uprojectFile.FullName
$ProjectName = $uprojectFile.BaseName
$assoc = ([regex]::Match((Read-Text $UProjectPath), '"EngineAssociation"\s*:\s*"([^"]*)"')).Groups[1].Value
$configBat = Join-Path $ProjectRoot 'devops_data\config.bat'
$sourceDir = Join-Path $ProjectRoot 'Source'
if (-not (Test-Path -LiteralPath (Join-Path $sourceDir $ProjectName))) { throw "No Source\${ProjectName}: automation tests need a C++ module (Blueprint-only project?)" }
Write-Host "  $UProjectPath"

# ---------------------------------------------------------------------------------------------
if ($NewSpec -or $NewTest) {
    Write-Step 'New test file'
    $name = if ($NewSpec) { $NewSpec } else { $NewTest }
    if ($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { throw "Invalid test class name '$name'" }
    $tplDir = Join-Path $ProjectRoot 'devops_ue\tests\templates'
    if (-not (Test-Path -LiteralPath $tplDir)) { throw "Templates not found: $tplDir (devops_ue submodule missing?)" }
    $copyright = Get-ConfigValue $configBat 'COPYRIGHT_LINE'
    if (-not $copyright -or $copyright -match 'My game copyright') {
        $notice = ''
        $dg = Join-Path $ProjectRoot 'Config\DefaultGame.ini'
        if (Test-Path -LiteralPath $dg) { $notice = ([regex]::Match((Read-Text $dg), '(?m)^CopyrightNotice=(.*)$')).Groups[1].Value.Trim() }
        $copyright = if ($notice) { "// $notice" } else { "// Copyright $ProjectName. All Rights Reserved." }
    }
    $relDir = $Dir.Trim('\', '/').Replace('/', '\')
    $absDir = if ($relDir) { Join-Path (Join-Path $sourceDir $ProjectName) $relDir } else { Join-Path $sourceDir $ProjectName }
    $includePath = (@($ProjectName) + $(if ($relDir) { @($relDir) } else { @() }) + @("$name.h")) -join '/'
    $includePath = $includePath.Replace('\', '/')
    function Expand-Template([string]$TemplateFile) {
        $out = foreach ($line in [IO.File]::ReadAllLines($TemplateFile)) {
            if ($line.Trim() -eq 'NEW_LINE') { '' }
            else {
                $line.Replace('%COPYRIGHT_LINE%', $copyright).Replace('%TestClassName%', $name).Replace('%OR%', '|').Replace('%AND%', '&').
                    Replace('%TEST_INCLUDE_FILE%', "`"$includePath`"")
            }
        }
        return ($out -join "`r`n") + "`r`n"
    }
    $created = @()
    if ($NewSpec) {
        $f = Join-Path $absDir "$name.spec.cpp"
        if (Test-Path -LiteralPath $f) { throw "Already exists: $f" }
        Write-Text $f (Expand-Template (Join-Path $tplDir 'Test.spec.cpp.template')); $created += $f
    }
    else {
        $h = Join-Path $absDir "$name.h"; $c = Join-Path $absDir "$name.cpp"
        if ((Test-Path -LiteralPath $h) -or (Test-Path -LiteralPath $c)) { throw "Already exists: $h / $c" }
        Write-Text $h (Expand-Template (Join-Path $tplDir 'Test.h.template')); Write-Text $c (Expand-Template (Join-Path $tplDir 'Test.cpp.template')); $created += @($h, $c)
    }
    if (Get-Command clang-format -ErrorAction SilentlyContinue) { foreach ($f in $created) { & clang-format -i $f } }
    $created | ForEach-Object { Write-Host "  created $_" }
    Write-Host "  test path in the file: 'Category...' - rename it to '$ProjectName.<Area>.<Name>' so -Filter $ProjectName finds it"
    Write-FinalStep 'Done'
    Write-Timing
    exit 0
}

# ---------------------------------------------------------------------------------------------
$EnginePath = Resolve-ProjectEngine $ProjectRoot $assoc $EnginePath
$editorCmd = Join-Path $EnginePath 'Engine\Binaries\Win64\UnrealEditor-Cmd.exe'
if (-not (Test-Path -LiteralPath $editorCmd)) { throw "UnrealEditor-Cmd.exe not found in $EnginePath" }
if (-not $Filter) { $Filter = Get-ConfigValue $configBat 'TestNames' }
if (-not $Filter) { $Filter = $ProjectName }
$outDir = Join-Path $ProjectRoot 'Build\Tests'
Write-Host "  engine: $EnginePath"
Write-Host "  filter: $Filter"

if (-not $SkipBuild) {
    Write-Step "Build ${ProjectName}Editor Win64 Development"
    $buildLog = Join-Path $ProjectRoot 'Saved\Tests\build.log'
    $code = Invoke-BatLogged (Join-Path $EnginePath 'Engine\Build\BatchFiles\Build.bat') "${ProjectName}Editor Win64 Development -Project=`"$UProjectPath`" -WaitMutex" $buildLog
    if ($code -ne 0) {
        $errs = @((Read-SharedLines $buildLog) | Where-Object { $_ -match ':\s*(fatal )?error\s*[A-Z]*\d*\s*:|error LNK\d+' } | Select-Object -Unique -First 20)
        $errs | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        throw "Build failed (code $code), see $buildLog"
    }
}

$rhi = if ($WithRHI) { '' } else { '-nullrhi' }
$common = "-unattended -nopause -nosplash -nosound -nop4 $rhi"

if ($List) {
    Write-Step 'List tests'
    $listLog = Join-Path $ProjectRoot 'Saved\Tests\list.log'
    $null = Invoke-Logged $editorCmd "`"$UProjectPath`" -ExecCmds=`"Automation List;Quit`" $common -stdout -FullStdOutLogOutput" $listLog $TimeoutMinutes
    $tests = @((Read-SharedLines $listLog) | ForEach-Object { if ($_ -match 'LogAutomationCommandLine:\s*Display:\s+(\S.*)$') { $Matches[1].Trim() } } |
        Where-Object { $_ -and $_ -notmatch '^Found \d+ (automation )?tests' } | Where-Object { $_ -like "*$Filter*" } | Sort-Object -Unique)
    Write-Host ''
    $tests | ForEach-Object { Write-Host "  $_" }
    Write-FinalStep "$($tests.Count) test(s) match '$Filter'"
    Write-Timing
    exit 0
}

# ---------------------------------------------------------------------------------------------
Write-Step "Run tests '$Filter'$(if ($Coverage) { ' with coverage' })"
if (Test-Path -LiteralPath $outDir) { Remove-Item -LiteralPath $outDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$editorArgs = "`"$UProjectPath`" -ExecCmds=`"Automation RunTests $Filter;Quit`" $common -ReportExportPath=`"$outDir`" -abslog=`"$outDir\Tests.log`" -stdout -FullStdOutLogOutput"
$runLog = Join-Path $ProjectRoot 'Saved\Tests\run.log'

if ($Coverage) {
    $occ = Get-ConfigValue $configBat 'OpenCPPCoveragePath'
    if (-not $occ -or -not (Test-Path -LiteralPath $occ)) { $occ = 'C:\Program Files\OpenCppCoverage\OpenCppCoverage.exe' }
    if (-not (Test-Path -LiteralPath $occ)) { throw 'OpenCppCoverage not found: winget install --id OpenCppCoverage.OpenCppCoverage -e (or ue-install-env -Tools opencppcoverage)' }
    $excluded = Get-ConfigValue $configBat 'ExcludedPathForTestReport'
    $exArgs = ''
    foreach ($p in ($excluded -split ';' | Where-Object { $_ })) {
        $p = $p.Replace('%SourceCodePath%', $sourceDir).Replace('%ProjectPureName%', $ProjectName)
        $exArgs += " --excluded_sources=`"$p`""
    }
    $covDir = Join-Path $outDir 'Coverage'
    $occArgs = "--modules=`"$ProjectRoot`" --sources=`"$sourceDir`"$exArgs --export_type=`"html:$covDir\CodeCoverageReport`" --export_type=`"cobertura:$covDir\CodeCoverageReport.xml`" -- `"$editorCmd`" $editorArgs"
    $code = Invoke-Logged $occ $occArgs $runLog $TimeoutMinutes
}
else {
    $code = Invoke-Logged $editorCmd $editorArgs $runLog $TimeoutMinutes
}

# ---------------------------------------------------------------------------------------------
Write-Step 'Results'
$index = Join-Path $outDir 'index.json'
if (-not (Test-Path -LiteralPath $index)) { throw "No test report ($index): the editor exited with $code before writing it, see $runLog" }
$report = [IO.File]::ReadAllText($index, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF) | ConvertFrom-Json
$tests = @($report.tests)
$failedTests = @($tests | Where-Object { $_.state -eq 'Fail' -or $_.errors -gt 0 })
$passed = @($tests | Where-Object { $_.state -eq 'Success' -and $_.errors -eq 0 }).Count
$skipped = $tests.Count - $passed - $failedTests.Count
Write-Host ("  {0} test(s): {1} passed, {2} failed, {3} not run/other, {4:N1}s" -f $tests.Count, $passed, $failedTests.Count, $skipped, [double]$report.totalDuration)
foreach ($t in $failedTests) {
    Write-Host "  FAIL $($t.fullTestPath)" -ForegroundColor Red
    foreach ($e in @($t.entries | Where-Object { $_.event.type -eq 'Error' } | Select-Object -First 5)) {
        $where = if ($e.filename) { " ($([IO.Path]::GetFileName($e.filename)):$($e.lineNumber))" } else { '' }
        Write-Host "       $($e.event.message)$where"
    }
}
if ($tests.Count -eq 0) { Add-Warning "No tests matched '$Filter' (test paths come from IMPLEMENT_SIMPLE_AUTOMATION_TEST / DEFINE_SPEC names; try -List)" }

if ($JUnit) {
    $py = Join-Path $EnginePath 'Engine\Binaries\ThirdParty\Python3\Win64\python.exe'
    $conv = Join-Path $ProjectRoot 'devops_ue\tests\ue_report_to_junit.py'
    if ((Test-Path -LiteralPath $conv) -and (Test-Path -LiteralPath $py)) {
        & $py -I $conv "-ue_report_path=$index" "-junit_xml_path=$outDir\junit.xml"
        if ($LASTEXITCODE -eq 0) { Write-Host "  JUnit: $outDir\junit.xml" } else { Add-Warning 'JUnit conversion failed' }
    }
    else { Add-Warning "JUnit conversion skipped: $conv or the engine Python not found" }
}
if ($Coverage) {
    $covIndex = Join-Path $outDir 'Coverage\CodeCoverageReport\index.html'
    if (Test-Path -LiteralPath $covIndex) {
        $xml = Join-Path $outDir 'Coverage\CodeCoverageReport.xml'
        if (Test-Path -LiteralPath $xml) {
            [xml]$c = Get-Content -LiteralPath $xml -Raw
            Write-Host ("  coverage: {0:P1} lines" -f [double]$c.coverage.'line-rate')
        }
        Write-Host "  coverage report: $covIndex"
    }
    else { Add-Warning 'Coverage report was not written, see the run log' }
}
Write-Host "  report: $outDir (index.json, Tests.log); the HTML viewer needs a local server: devops_ue\tests\run_tests.bat flow / npx http-server"

$result = if ($tests.Count -eq 0) { 'NO TESTS' } elseif ($failedTests.Count) { 'FAILED' } else { 'PASSED' }
Write-FinalStep "Tests $result"
if ($Warnings.Count -gt 0) {
    Write-Host 'Warnings:' -ForegroundColor Yellow
    foreach ($w in $Warnings) { Write-Host "  - $w" -ForegroundColor Yellow }
}
Write-Timing $(if ($result -eq 'PASSED') { 'total' } else { "total ($result)" })
if ($result -ne 'PASSED') { exit 1 }
