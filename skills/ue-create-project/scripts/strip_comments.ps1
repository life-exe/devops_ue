# Copyright LifeEXE. All Rights Reserved.
# Removes the obvious comments from C++ sources (the engine templates are full of them): banners, "/** Constructor */",
# "// stub", and comments that only repeat the name of the declaration below them ("/** Move Input Action */" above
# "UInputAction* MoveAction;"). Comments that carry information (why, units, warnings, TODO, links, @tags, the copyright
# line) stay.
#   strip_comments.ps1 -Path C:\Game\Source\Game                  # edit *.h / *.cpp in place
#   strip_comments.ps1 -Path "<engine>\Templates\TP_ThirdPerson\Source" -DryRun   # only show what would go (writes nothing)
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [switch]$DryRun,
    # how many removed comments to print (the counts are always complete)
    [int]$Show = 30
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Path)) { throw "Not found: $Path" }

$stop = @('a', 'an', 'the', 'of', 'to', 'for', 'from', 'in', 'on', 'is', 'are', 'be', 'this', 'that', 'it', 'its', 'and', 'or', 'with', 'by',
    'as', 'at', 'when', 'if', 'will', 'can', 'should', 'used', 'use', 'called', 'handles', 'handle', 'runs', 'run', 'get', 'gets', 'set', 'sets',
    'returns', 'return', 'true', 'false', 'event', 'events', 'callback', 'function', 'method', 'we', 'you', 'our', 'your', 'here', 'then')
# a whole comment that says nothing
$generic = '^(?:default |empty )?(?:constructor|destructor|stub|tick|begin ?play|end ?play|initialization|initialize|init|' +
    '(?:gameplay|pawn|component|actor|controller|ui|input|widget) (?:initialization|initialize|setup|init)|' +
    'called every frame|called when the game starts(?: or when spawned)?|called to bind functionality to input|' +
    'sets? default values for this \w+(?:''s)? properties)$'
# comments that carry information: never touched
$keep = '(?i)copyright|licen[sc]e|todo|fixme|hack|\bnote\b|\bbecause\b|\botherwise\b|workaround|warning|careful|\bwhy\b|nolint|clang-format|https?://|@\w+|\\\w+\{|//~|region|\bunits?\b|\bseconds?\b|\bmeters?\b|\bcm\b'

function Get-Tokens([string]$Text) {
    $spaced = [regex]::Replace($Text, '([a-z0-9])([A-Z])', '$1 $2')
    $spaced = [regex]::Replace($spaced, '([A-Z]+)([A-Z][a-z])', '$1 $2')
    $set = New-Object System.Collections.Generic.HashSet[string]
    foreach ($w in [regex]::Split($spaced.ToLowerInvariant(), '[^a-z0-9]+')) { if ($w) { [void]$set.Add($w) } }
    return , $set
}
function Test-WordIn([string]$Word, $Set) {
    if ($Set.Contains($Word)) { return $true }
    if ($Word.Length -ge 4) {
        $p = $Word.Substring(0, [math]::Min(4, $Word.Length))
        foreach ($t in $Set) { if ($t.Length -ge 4 -and $t.StartsWith($p)) { return $true } }
    }
    return $false
}

function Get-CommentText([string[]]$Lines) {
    $t = foreach ($l in $Lines) { $l.Trim() -replace '^/\*+', '' -replace '\*+/$', '' -replace '^//+', '' -replace '^\*+', '' }
    return (($t | ForEach-Object { $_.Trim() }) -join ' ').Trim()
}

# true when the comment is obvious. $Next = the code line right below it ('' when none / free-standing)
function Test-Obvious([string]$Text, [string]$Next, [bool]$IsLineComment) {
    if ($Text -match '^[\s/*=\-#_~]*$') { return $true }                   # banner / empty
    if ($Text -match $keep) { return $false }
    $plain = $Text.Trim().TrimEnd('.', ':', '!')
    if ($plain -match $generic) { return $true }
    if (-not $Next) { return $false }
    $words = @([regex]::Split($Text.ToLowerInvariant(), '[^a-z0-9]+') | Where-Object { $_ })
    if ($words.Count -eq 0) { return $true }
    # "// get the instance data", "// Moving": a short narration of the next line (no digits / colon = no value or detail in it)
    if ($IsLineComment -and $words.Count -le 4 -and $Text -notmatch '[0-9:]') { return $true }
    $content = @($words | Where-Object { $_ -notin $stop })
    if ($content.Count -eq 0) { return $true }
    if ($content.Count -gt 6) { return $false }
    $code = Get-Tokens $Next
    foreach ($w in $content) { if (-not (Test-WordIn $w $code)) { return $false } }
    return $true
}

$declSkip = '^\s*(?:UPROPERTY|UFUNCTION|UCLASS|USTRUCT|UENUM|UINTERFACE|GENERATED_BODY|GENERATED_USTRUCT_BODY|GENERATED_UCLASS_BODY|public:|protected:|private:|\[)'

$files = if ((Get-Item -LiteralPath $Path).PSIsContainer) { Get-ChildItem -LiteralPath $Path -Recurse -File -Include '*.h', '*.cpp' } else { @(Get-Item -LiteralPath $Path) }
$removed = New-Object System.Collections.ArrayList
$changedFiles = 0

foreach ($file in $files) {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $raw = [IO.File]::ReadAllText($file.FullName)
    $eol = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = [regex]::Split($raw, "`r?`n")
    $n = $lines.Count
    $drop = New-Object 'bool[]' $n
    $fileRemoved = 0

    $i = 0
    while ($i -lt $n) {
        $t = $lines[$i].Trim()
        $j = -1; $isLine = $false
        if ($t.StartsWith('/*')) {
            for ($k = $i; $k -lt $n; $k++) { if ($lines[$k].Contains('*/')) { $j = $k; break } }
            # only whole-line comments: nothing but the comment on its first and last line
            if ($j -lt 0 -or -not $lines[$j].TrimEnd().EndsWith('*/')) { $j = -1 }
        }
        elseif ($t.StartsWith('//')) {
            $j = $i; $isLine = $true
            while ($j + 1 -lt $n -and $lines[$j + 1].Trim().StartsWith('//')) { $j++ }
        }
        if ($j -lt 0) { $i++; continue }

        $block = $lines[$i..$j]
        $text = Get-CommentText $block
        # next code line (the comment must sit directly above it, otherwise it is free-standing)
        $next = ''
        $m = $j + 1
        if ($m -lt $n -and $lines[$m].Trim()) {
            while ($m -lt $n -and $lines[$m] -match $declSkip) { $m++ }
            if ($m -lt $n -and $lines[$m].Trim() -and -not $lines[$m].Trim().StartsWith('//') -and -not $lines[$m].Trim().StartsWith('/*') -and $lines[$m].Trim() -ne '}') { $next = $lines[$m] }
        }
        if (Test-Obvious $text $next $isLine) {
            for ($k = $i; $k -le $j; $k++) { $drop[$k] = $true }
            $fileRemoved++
            [void]$removed.Add([pscustomobject]@{ File = $file.FullName.Substring($file.FullName.IndexOf('Source') + 0); Line = $i + 1; Text = $text })
        }
        $i = $j + 1
    }

    if ($fileRemoved -eq 0) { continue }
    $changedFiles++
    if ($DryRun) { continue }

    $out = New-Object System.Collections.ArrayList
    for ($k = 0; $k -lt $n; $k++) {
        if ($drop[$k]) { continue }
        $line = $lines[$k]
        if (-not $line.Trim() -and $out.Count -gt 0) {
            $prev = $out[$out.Count - 1]
            if (-not $prev.Trim()) { continue }                 # no double blank lines
            if ($prev.TrimEnd().EndsWith('{')) { continue }      # no blank line right after '{'
        }
        [void]$out.Add($line)
    }
    # a blank line right before '}' left behind by a removed comment
    $final = New-Object System.Collections.ArrayList
    for ($k = 0; $k -lt $out.Count; $k++) {
        if (-not $out[$k].Trim() -and $k + 1 -lt $out.Count -and $out[$k + 1].Trim() -eq '}' -and $k -gt 0) { continue }
        [void]$final.Add($out[$k])
    }
    [IO.File]::WriteAllText($file.FullName, ($final -join $eol), (New-Object System.Text.UTF8Encoding($hasBom)))
}

$verb = if ($DryRun) { 'would remove' } else { 'removed' }
$total = $files.Count
foreach ($r in ($removed | Select-Object -First $Show)) {
    $txt = if ($r.Text.Length -gt 90) { $r.Text.Substring(0, 87) + '...' } else { $r.Text }
    Write-Host ("  {0}:{1}  {2}" -f $r.File, $r.Line, $(if ($txt) { $txt } else { '(banner)' }))
}
if ($removed.Count -gt $Show) { Write-Host "  ... and $($removed.Count - $Show) more" }
Write-Host "Comments: $verb $($removed.Count) obvious comment(s) in $changedFiles of $total file(s)"
