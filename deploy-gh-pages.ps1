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

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $repoRoot

$worktreeBranch = 'gh-pages'
$worktreePath = Join-Path (Split-Path -Path $env:TEMP -Leaf) 'gh-pages'
if (-not $worktreePath) {
  $worktreePath = Join-Path $env:TEMP 'gh-pages'
}

Write-Host "Preparing worktree [$worktreeBranch] at $worktreePath"
if (Test-Path $worktreePath) {
  Remove-Item -Recurse -Force $worktreePath
}

if (-not (git show-ref --verify --quiet refs/heads/$worktreeBranch)) {
  git branch $worktreeBranch
}

$addArgs = @($worktreePath, $worktreeBranch)
git worktree add @addArgs 2>$null
if ($LASTEXITCODE -ne 0) {
  git worktree remove $worktreePath -f -ErrorAction SilentlyContinue
  git worktree add @addArgs
}

$distPath = Join-Path $repoRoot 'apps/web/dist/web'
if (-not (Test-Path $distPath)) {
  throw "Build output not found at $distPath. Run `npm run build` inside apps/web first."
}

Write-Host "Publishing contents of $distPath/browser to worktree"
Copy-Item -Recurse -Force "$distPath\browser\*" $worktreePath

foreach ($extra in @('3rdpartylicenses.txt','prerendered-routes.json')) {
  $file = Join-Path $distPath $extra
  if (Test-Path $file) {
    Copy-Item -Force $file $worktreePath
  }
}

Set-Location $worktreePath
git add --all
if (-not (git status -s)) {
  Write-Host "No changes to publish."
} else {
  git commit -m "Publish Angular site to gh-pages"
}

git push origin $worktreeBranch
