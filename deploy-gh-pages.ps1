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
$worktreePath = Join-Path $env:TEMP 'gh-pages'

Write-Host "Preparing worktree [$worktreeBranch] at $worktreePath"
if (Test-Path $worktreePath) {
  Remove-Item -Recurse -Force $worktreePath
}

git worktree prune

if (-not (git show-ref --verify --quiet refs/heads/$worktreeBranch)) {
  git branch $worktreeBranch
}

git worktree add -B $worktreeBranch $worktreePath

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
Copy-Item -Recurse -Force "$browserPath\*" $worktreePath

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

git push --force-with-lease origin $worktreeBranch
