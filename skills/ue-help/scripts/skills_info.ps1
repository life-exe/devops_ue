# Copyright LifeEXE. All Rights Reserved.
# Information about the devops_ue skills: name, what it does, scripts and their parameters, where it is installed.
#   skills_info.ps1                    # table of all skills (name + short description)
#   skills_info.ps1 -Name ue-cook      # details: full description, scripts with parameters, usage lines
#   skills_info.ps1 -Full              # details of every skill
#   skills_info.ps1 -Format Markdown   # Markdown table (for docs / README)   |  -Format Json  # machine readable
#   skills_info.ps1 -Lang ru           # descriptions in Russian (-Lang both: Russian + English; default en)
#   skills_info.ps1 -Where             # + the folders where each skill is installed (user / project, per agent)
#   skills_info.ps1 -Format Html -Open # a self-contained HTML help page (search, groups, RU/EN switch, parameters), opened in the browser
#   skills_info.ps1 -Format Html -Out C:\Temp\skills.html -Lang ru   # where to write it (default: %TEMP%\ue-skills-help.html) + start language
[CmdletBinding()]
param(
    [string]$Name = '',
    [switch]$Full,
    [switch]$Where,
    [switch]$All,   # also skills that do not start with ue-
    [ValidateSet('Table', 'Markdown', 'Json', 'Html')][string]$Format = 'Table',
    [string]$Out = '',     # -Format Html: output file
    [switch]$Open,         # -Format Html: open the page in the default browser
    # language of the descriptions: en (SKILL.md text), ru (summaries.ru.json), both (ru + en)
    [ValidateSet('en', 'ru', 'both')][string]$Lang = 'en',
    [string]$SkillsDir = '',
    [string]$ProjectDir = ''
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
# Russian summaries: <skill dir>\summaries.ru.json { "ue-x": "..." }; a skill without an entry falls back to English
$ruFile = Join-Path $PSScriptRoot '..\summaries.ru.json'
$ru = @{}
if (Test-Path -LiteralPath $ruFile) {
    $obj = [IO.File]::ReadAllText($ruFile, [Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($p in $obj.PSObject.Properties) { $ru[$p.Name] = [string]$p.Value }
}
# description lines to print for a skill in the chosen language
function Get-Summaries($s) {
    $r = $ru[$s.Name]
    switch ($Lang) {
        'en' { return , @($s.Summary) }
        'ru' { return , @($(if ($r) { $r } else { $s.Summary })) }
        'both' { if ($r) { return , @($r, $s.Summary) } else { return , @($s.Summary) } }
    }
}

# skills live side by side: this script is <skills>\ue-help\scripts\skills_info.ps1
if (-not $SkillsDir) { $SkillsDir = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
if (-not $ProjectDir) {
    # <project>\devops_ue\skills and <project>\.claude\skills (or .agents\skills) are both two levels below the project
    $ProjectDir = (Resolve-Path -LiteralPath (Join-Path $SkillsDir '..\..')).Path
}

function Read-Frontmatter([string]$File) {
    $text = [IO.File]::ReadAllText($File)
    $m = [regex]::Match($text, '(?s)\A---\s*\r?\n(.*?)\r?\n---')
    $r = @{ name = ''; description = '' }
    if ($m.Success) {
        foreach ($line in ($m.Groups[1].Value -split '\r?\n')) {
            $kv = [regex]::Match($line, '^(name|description):\s*(.*)$')
            if ($kv.Success) { $r[$kv.Groups[1].Value] = $kv.Groups[2].Value.Trim().Trim('"') }
        }
    }
    return $r
}

function Get-ScriptParams([string]$File) {
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($File, [ref]$tokens, [ref]$errors)
    if (-not $ast.ParamBlock) { return @() }
    foreach ($p in $ast.ParamBlock.Parameters) {
        $type = ''
        $isSwitch = $false
        $mandatory = $false
        foreach ($a in $p.Attributes) {
            if ($a -is [Management.Automation.Language.TypeConstraintAst]) { $type = $a.TypeName.Name; if ($type -eq 'switch') { $isSwitch = $true } }
            elseif ($a -is [Management.Automation.Language.AttributeAst]) {
                if ($a.TypeName.Name -eq 'ValidateSet') { $type = 'one of: ' + (($a.PositionalArguments | ForEach-Object { $_.Value }) -join '|') }
                if ($a.TypeName.Name -eq 'Parameter') { foreach ($n in $a.NamedArguments) { if ($n.ArgumentName -eq 'Mandatory') { $mandatory = $true } } }
            }
        }
        $def = if ($p.DefaultValue) { $p.DefaultValue.Extent.Text } else { '' }
        $o = [ordered]@{ Name = $p.Name.VariablePath.UserPath; Type = $(if ($isSwitch) { 'switch' } else { $type }); Default = $def; Mandatory = $mandatory }
        [pscustomobject]$o
    }
}

function Get-SkillHeaderComment([string]$File) {
    # leading '#' lines (after the copyright line) hold the usage examples
    $out = @()
    foreach ($line in [IO.File]::ReadAllLines($File)) {
        if ($line -match '^\s*#(?!requires)\s?(.*)$') { $out += $Matches[1] } elseif ($out.Count -gt 0 -or $line.Trim()) { if ($line.Trim() -ne '' -and $line -notmatch '^\s*#') { break } }
    }
    return @($out | Where-Object { $_ -notmatch 'Copyright' })
}

function Get-InstalledAt([string]$Skill) {
    $locs = @(
        @{ Name = 'user claude'; Dir = Join-Path $env:USERPROFILE '.claude\skills' },
        @{ Name = 'user agents (codex/opencode)'; Dir = Join-Path $env:USERPROFILE '.agents\skills' },
        @{ Name = 'user antigravity'; Dir = Join-Path $env:USERPROFILE '.gemini\antigravity\skills' },
        @{ Name = 'project claude'; Dir = Join-Path $ProjectDir '.claude\skills' },
        @{ Name = 'project agents'; Dir = Join-Path $ProjectDir '.agents\skills' }
    )
    @($locs | Where-Object { Test-Path -LiteralPath (Join-Path $_.Dir $Skill) } | ForEach-Object { $_.Name })
}

$skills = foreach ($d in Get-ChildItem -LiteralPath $SkillsDir -Directory | Sort-Object Name) {
    $md = Join-Path $d.FullName 'SKILL.md'
    if (-not (Test-Path -LiteralPath $md)) { continue }
    if (-not $All -and $d.Name -notlike 'ue-*') { continue }   # installed copies sit next to the user's other skills
    $fm = Read-Frontmatter $md
    $scripts = @(Get-ChildItem -LiteralPath (Join-Path $d.FullName 'scripts') -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.ps1', '.bat', '.py' } | Sort-Object Name)
    $desc = $fm.description
    $use = ''
    $i = $desc.IndexOf(' Use ')
    if ($i -ge 0) { $use = $desc.Substring($i + 1).Trim(); $desc = $desc.Substring(0, $i).Trim() }
    [pscustomobject]@{
        Name        = $(if ($fm.name) { $fm.name } else { $d.Name })
        Summary     = $desc
        UseWhen     = $use
        Scripts     = $scripts
        Path        = $d.FullName
    }
}

if ($Name) {
    $want = $Name.TrimStart('/')
    $known = @($skills)
    $skills = @($known | Where-Object { $_.Name -eq $want -or $_.Name -eq "ue-$want" })
    if (-not $skills) { $skills = @($known | Where-Object { $_.Name -like "$want*" -or $_.Name -like "ue-$want*" }) }   # start of a name: "target" -> ue-target-create
    if ($skills.Count -eq 0) { Write-Host "No skill '$Name'. Available: $(($known | ForEach-Object Name) -join ', ')" -ForegroundColor Red; exit 1 }
}
$detailed = [bool]$Name -or $Full

if ($Format -eq 'Json') {
    $skills | ForEach-Object {
        [ordered]@{
            name = $_.Name; summary = $_.Summary; summaryRu = $(if ($ru[$_.Name]) { $ru[$_.Name] } else { $null }); useWhen = $_.UseWhen; path = $_.Path; installed = @(Get-InstalledAt $_.Name)
            scripts = @($_.Scripts | ForEach-Object { [ordered]@{ file = $_.Name; parameters = @(if ($_.Extension -eq '.ps1') { Get-ScriptParams $_.FullName }) } })
        }
    } | ConvertTo-Json -Depth 6
    exit 0
}

if ($Format -eq 'Html') {
    $template = Join-Path $PSScriptRoot '..\assets\help.html'
    if (-not (Test-Path -LiteralPath $template)) { Write-Host "HTML template not found: $template" -ForegroundColor Red; exit 1 }
    if (-not $Out) { $Out = Join-Path ([IO.Path]::GetTempPath()) 'ue-skills-help.html' }
    # group of a skill on the page (labels are in the template); a new skill falls into "other" until it is listed here
    $groups = @{
        'ue-check-env' = 'env'; 'ue-install-env' = 'env'
        'ue-create-project' = 'project'; 'ue-upgrade-engine' = 'project'; 'ue-clean' = 'project'; 'ue-content-audit' = 'project'
        'ue-format' = 'code'; 'ue-run-tests' = 'code'; 'ue-add-test' = 'code'; 'ue-docs' = 'code'; 'ue-plugin-create' = 'code'; 'ue-plugin-package' = 'code'
        'ue-target-create' = 'build'; 'ue-cook' = 'build'; 'ue-package' = 'build'
        'ue-help' = 'help'
    }
    $data = [ordered]@{
        generated  = (Get-Date -Format 'yyyy-MM-dd HH:mm')
        lang       = $Lang
        langForced = $PSBoundParameters.ContainsKey('Lang')   # an explicit -Lang wins over the language remembered by the page
        skillsDir  = $SkillsDir
        skills     = @(foreach ($s in $skills) {
                [ordered]@{
                    name      = $s.Name
                    category  = $(if ($groups[$s.Name]) { $groups[$s.Name] } else { 'other' })
                    summary   = $s.Summary
                    summaryRu = $(if ($ru[$s.Name]) { $ru[$s.Name] } else { $null })
                    useWhen   = $s.UseWhen
                    installed = @(Get-InstalledAt $s.Name)
                    scripts   = @(foreach ($sc in $s.Scripts) {
                            [ordered]@{
                                file       = $sc.Name
                                usage      = @(if ($sc.Extension -eq '.ps1') { Get-SkillHeaderComment $sc.FullName | Select-Object -First 12 })
                                parameters = @(if ($sc.Extension -eq '.ps1') {
                                        Get-ScriptParams $sc.FullName | ForEach-Object { [ordered]@{ name = $_.Name; type = $_.Type; default = $_.Default; mandatory = $_.Mandatory } }
                                    })
                            }
                        })
                }
            })
    }
    # "</" would end the <script> block the JSON is embedded in
    $json = ($data | ConvertTo-Json -Depth 8 -Compress).Replace('</', '<\/')
    $html = [IO.File]::ReadAllText($template, [Text.Encoding]::UTF8).Replace('__SKILLS_JSON__', $json)
    $outDir = Split-Path -Parent $Out
    if ($outDir -and -not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
    [IO.File]::WriteAllText($Out, $html, (New-Object Text.UTF8Encoding($true)))
    Write-Host "HTML help ($(@($skills).Count) skills): $Out"
    if ($Open) { Start-Process -FilePath $Out }
    exit 0
}

if ($Format -eq 'Markdown' -and -not $detailed) {
    '| Skill | Description |'
    '|-------|-------------|'
    foreach ($s in $skills) { '| `{0}` | {1} |' -f $s.Name, ((Get-Summaries $s) -join '<br>').Replace('|', '\|') }
    exit 0
}

if (-not $detailed) {
    Write-Host ''
    Write-Host "devops_ue skills ($(@($skills).Count)) - $SkillsDir" -ForegroundColor Cyan
    Write-Host ''
    $w = ($skills | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum
    foreach ($s in $skills) {
        $first = $true
        foreach ($short in (Get-Summaries $s)) {
            if ($short.Length -gt 130) { $short = $short.Substring(0, 127) + '...' }
            if ($first) { Write-Host ('  /{0}  {1}' -f $s.Name.PadRight($w), $short) }
            else { Write-Host ('   {0}  {1}' -f ''.PadRight($w), $short) -ForegroundColor DarkGray }
            $first = $false
        }
    }
    Write-Host ''
    Write-Host '  Details:   skills_info.ps1 -Name <skill>     All details: -Full     Where installed: -Where' -ForegroundColor DarkGray
    Write-Host '  Other:     -Format Markdown | Json | Html (-Open)     Language: -Lang ru | en | both' -ForegroundColor DarkGray
    if ($Where) {
        Write-Host ''
        foreach ($s in $skills) {
            $at = Get-InstalledAt $s.Name
            Write-Host ('  {0}  {1}' -f $s.Name.PadRight($w), $(if ($at) { $at -join ', ' } else { '(not installed)' }))
        }
    }
    exit 0
}

foreach ($s in $skills) {
    Write-Host ''
    Write-Host "/$($s.Name)" -ForegroundColor Cyan
    $sum = Get-Summaries $s
    Write-Host "  $($sum[0])"
    if ($sum.Count -gt 1) { Write-Host "  $($sum[1])" -ForegroundColor DarkGray }
    if ($s.UseWhen -and $Lang -ne 'ru') { Write-Host "  $($s.UseWhen)" -ForegroundColor DarkGray }
    Write-Host "  SKILL.md : $(Join-Path $s.Path 'SKILL.md')"
    if ($Where -or $Name) {
        $at = Get-InstalledAt $s.Name
        Write-Host "  installed: $(if ($at) { $at -join ', ' } else { '(not installed in user/project folders)' })"
    }
    if (-not $s.Scripts) { Write-Host '  scripts  : none (the skill is a workflow for the agent)'; continue }
    foreach ($sc in $s.Scripts) {
        Write-Host "  script   : scripts\$($sc.Name)" -ForegroundColor Yellow
        if ($sc.Extension -ne '.ps1') { continue }
        foreach ($line in (Get-SkillHeaderComment $sc.FullName | Select-Object -First 6)) { Write-Host "             $line" -ForegroundColor DarkGray }
        foreach ($p in Get-ScriptParams $sc.FullName) {
            $info = @()
            if ($p.Type -and $p.Type -ne 'switch') { $info += $p.Type }
            if ($p.Mandatory) { $info += 'required' }
            if ($p.Default) { $info += "default $($p.Default)" }
            $flag = if ($p.Type -eq 'switch') { '-' + $p.Name + ' (switch)' } else { '-' + $p.Name }
            Write-Host ('             {0}{1}' -f $flag, $(if ($info) { '  [' + ($info -join '; ') + ']' } else { '' }))
        }
    }
}
Write-Host ''
exit 0
