<#
.SYNOPSIS
    Log today's work in CHANGELOG.md, commit everything and push to GitHub.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\daily-commit.ps1 "Built KPI cards on Shock Overview"
#>
param(
    [Parameter(Position = 0)]
    [string]$Message
)

Set-Location (Split-Path $PSScriptRoot -Parent)

if (-not (git status --porcelain)) {
    Write-Host 'No changes to commit.' -ForegroundColor Yellow
    return
}

Write-Host 'Changes to be committed:' -ForegroundColor Cyan
git status --short

# GitHub rejects files over 100 MB - catch them before they get into a commit
$tooBig = git status --porcelain --untracked-files=all |
    ForEach-Object { $_.Substring(3).Trim('"') } |
    Where-Object { (Test-Path -LiteralPath $_ -PathType Leaf) -and (Get-Item -LiteralPath $_).Length -gt 95MB }
if ($tooBig) {
    Write-Host "These files are over 95 MB and would be rejected by GitHub:`n  $($tooBig -join "`n  ")" -ForegroundColor Red
    Write-Host 'Add them to .gitignore and run again.' -ForegroundColor Red
    exit 1
}

if (-not $Message) {
    $Message = Read-Host 'What did you work on today?'
}
if (-not $Message) {
    Write-Host 'A message is required.' -ForegroundColor Red
    exit 1
}

# Add the message under today's heading in CHANGELOG.md (newest first)
$log = Join-Path (Get-Location) 'CHANGELOG.md'
$lines = [System.Collections.Generic.List[string]]::new([string[]][System.IO.File]::ReadAllLines($log))
$heading = '## ' + (Get-Date -Format 'yyyy-MM-dd')
$idx = $lines.IndexOf($heading)
if ($idx -ge 0) {
    $lines.Insert($idx + 1, "- $Message")
} else {
    $at = $lines.Count
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].StartsWith('## ')) { $at = $i; break }
    }
    $lines.InsertRange($at, [string[]]@($heading, "- $Message", ''))
}
[System.IO.File]::WriteAllLines($log, $lines, (New-Object System.Text.UTF8Encoding $false))

git add -A
git commit -m $Message
if ($LASTEXITCODE -ne 0) { exit 1 }

# Pick up anything changed on GitHub (e.g. README edited in the browser) before pushing
git pull --rebase
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Pull failed. Resolve the conflict, then run: git rebase --continue; git push' -ForegroundColor Red
    exit 1
}

git push
if ($LASTEXITCODE -eq 0) {
    Write-Host "Pushed: $Message" -ForegroundColor Green
}
