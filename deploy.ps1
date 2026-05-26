# deploy.ps1 - local fallback when GitHub Actions is unavailable
# Builds Hugo site and pushes ./public to the gh-pages branch.
# Usage: .\deploy.ps1

$ErrorActionPreference = "Stop"

# Resolve key paths once.
$repoRoot = (Get-Location).Path
if ([string]::IsNullOrWhiteSpace($repoRoot)) {
    throw "Could not determine repo root"
}
$worktreeDir = Join-Path -Path $repoRoot -ChildPath ".gh-pages-worktree"
$publicDir   = Join-Path -Path $repoRoot -ChildPath "public"

Write-Host "Repo root   : $repoRoot"
Write-Host "Worktree dir: $worktreeDir"
Write-Host "Public dir  : $publicDir"
Write-Host ""

# 1. Build Hugo site
Write-Host "[1/4] Building Hugo site..." -ForegroundColor Cyan
hugo --minify
if ($LASTEXITCODE -ne 0) { throw "Hugo build failed" }

# 2. Prepare gh-pages worktree
if (Test-Path -LiteralPath $worktreeDir) {
    git worktree remove $worktreeDir --force | Out-Null
    if (Test-Path -LiteralPath $worktreeDir) {
        Remove-Item -LiteralPath $worktreeDir -Recurse -Force
    }
}

$remoteHasBranch = git ls-remote --heads origin gh-pages
if ($remoteHasBranch) {
    Write-Host "[2/4] Checking out existing gh-pages..." -ForegroundColor Cyan
    git fetch origin gh-pages
    git worktree add $worktreeDir gh-pages
} else {
    Write-Host "[2/4] Creating new orphan gh-pages branch..." -ForegroundColor Cyan
    git worktree add --orphan -b gh-pages $worktreeDir
}
if ($LASTEXITCODE -ne 0) { throw "git worktree add failed" }

# 3. Sync build output into the worktree and add .nojekyll
Write-Host "[3/4] Syncing build output..." -ForegroundColor Cyan
Get-ChildItem -LiteralPath $worktreeDir -Force |
    Where-Object { $_.Name -ne ".git" } |
    Remove-Item -Recurse -Force
Copy-Item -Path (Join-Path -Path $publicDir -ChildPath "*") `
          -Destination $worktreeDir -Recurse -Force
$nojekyll = Join-Path -Path $worktreeDir -ChildPath ".nojekyll"
New-Item -ItemType File -Path $nojekyll -Force | Out-Null

# 4. Commit and push
try {
    Push-Location -LiteralPath $worktreeDir
    git add -A
    $hasChanges = git status --porcelain
    if (-not $hasChanges) {
        Write-Host "[4/4] No changes to deploy." -ForegroundColor Yellow
    } else {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        git commit -m "Deploy: $timestamp"
        Write-Host "[4/4] Pushing to origin/gh-pages..." -ForegroundColor Cyan
        git push origin gh-pages
        if ($LASTEXITCODE -ne 0) { throw "git push failed" }
        Write-Host "Deployed successfully." -ForegroundColor Green
    }
} finally {
    Pop-Location
    git worktree remove $worktreeDir --force | Out-Null
}
