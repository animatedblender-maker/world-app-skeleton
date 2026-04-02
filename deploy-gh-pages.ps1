<#
.SYNOPSIS
  Publishes the `apps/web/dist/web` build to the `gh-pages` branch.

.DESCRIPTION
  Builds the Angular web app (if not already built), copies the `dist/web` output
  into a temporary worktree, commits the result, and pushes the `gh-pages` branch.

.NOTES
  Run this from the repository root. PowerShell 7 or Windows PowerShell works fine.
#>

param()

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $repoRoot

$worktreeBranch = 'gh-pages'
$tempRoot = if ($env:TEMP) {
  $env:TEMP
} elseif ($env:TMPDIR) {
  $env:TMPDIR
} else {
  '/tmp'
}
$worktreePath = Join-Path $tempRoot 'gh-pages-deploy'

Write-Host "Preparing worktree [$worktreeBranch] at $worktreePath"
if (Test-Path $worktreePath) {
  Remove-Item -Recurse -Force $worktreePath
}

git worktree prune

$existingWorktree = git worktree list --porcelain | ForEach-Object -Begin {
  $path = $null
  $branch = $null
} -Process {
  if ($_ -like 'worktree *') {
    $path = $_.Substring(9)
  } elseif ($_ -like 'branch *') {
    $branch = $_.Substring(7)
    if ($branch -eq "refs/heads/$worktreeBranch" -and $path -and $path -ne $repoRoot) {
      $path
    }
  }
}

if ($existingWorktree) {
  foreach ($path in $existingWorktree) {
    Write-Host "Removing existing worktree for [$worktreeBranch] at $path"
    git worktree remove --force $path
  }
}

git fetch origin $worktreeBranch --quiet 2>$null

$localRef = "refs/heads/$worktreeBranch"
$remoteRef = "refs/remotes/origin/$worktreeBranch"

git show-ref --verify --quiet $localRef
if ($LASTEXITCODE -eq 0) {
  Write-Host "Using existing local branch [$worktreeBranch]"
} else {
  git show-ref --verify --quiet $remoteRef
  if ($LASTEXITCODE -eq 0) {
  git branch --track $worktreeBranch origin/$worktreeBranch
  } else {
    throw "Local branch '$worktreeBranch' is missing and origin/$worktreeBranch was not found."
  }
}

git worktree add $worktreePath $worktreeBranch

$distPath = Join-Path $repoRoot 'apps/web/dist/web'
if (-not (Test-Path $distPath)) {
  throw "Build output not found at $distPath. Run `npm run build` inside apps/web first."
}

$browserPath = Join-Path $distPath 'browser'
if (-not (Test-Path $browserPath)) {
  throw "Build output not found at $browserPath. Run `npm run build` inside apps/web first."
}

Write-Host "Cleaning existing contents in worktree"
Get-ChildItem -Force $worktreePath | Where-Object { $_.Name -ne '.git' } | Remove-Item -Recurse -Force

Write-Host "Publishing contents of $browserPath to worktree"
Copy-Item -Recurse -Force (Join-Path $browserPath '*') $worktreePath

foreach ($extra in @('3rdpartylicenses.txt','prerendered-routes.json')) {
  $file = Join-Path $distPath $extra
  if (Test-Path $file) {
    Copy-Item -Force $file $worktreePath
  }
}

# Stamp a fresh version so the home-screen app can detect updates.
$versionStamp = Get-Date -Format "yyyyMMddHHmmss"
@{ version = $versionStamp } | ConvertTo-Json -Compress | Set-Content -Encoding UTF8 (Join-Path $worktreePath 'version.json')

Set-Location $worktreePath
git add --all
if (-not (git status -s)) {
  Write-Host "No changes to publish."
} else {
  git commit -m "Publish Angular site to gh-pages"
}

git push --force-with-lease origin $worktreeBranch
