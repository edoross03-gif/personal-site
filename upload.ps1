# Same job as upload.sh, for a Windows PC without rsync. It packs this folder with tar, sends the
# archive with scp, and lets the server's own rsync mirror it into /opt/personal-site. Then it runs
# deploy.sh there, exactly as upload.sh does.
#
#   powershell -ExecutionPolicy Bypass -File .\upload.ps1             send + build + show what would change live (changes nothing live)
#   powershell -ExecutionPolicy Bypass -File .\upload.ps1 apply       send + build + checks + confirm + backup + deploy
#   powershell -ExecutionPolicy Bypass -File .\upload.ps1 rollback    restore the latest backup on the server
#   powershell -ExecutionPolicy Bypass -File .\upload.ps1 -DryRun     pack only: list what would be sent, contact nobody
#   Add -Yes to apply or rollback to skip the server's "Apply to live? [y/N]" question.
#
# Needs: the OpenSSH client and tar that ship with Windows 10/11, and your usual SSH access to the server.
# The server address comes from .deploy.env (not in git, see .deploy.env.example).

param(
    [ValidateSet("status", "apply", "rollback")]
    [string]$Action = "status",
    [switch]$DryRun,
    [switch]$Yes      # apply / rollback without the server's confirmation prompt
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# ---------------------------------------------------------------- what is sent
# Mirrors the exclude list of upload.sh: these are never sent and never deleted on the server.
$top = Get-ChildItem -Force -Name | Where-Object {
    $_ -notin @(".git", ".venv", ".claude", ".gitattributes", "desktop.ini", ".DS_Store") -and
    $_ -notlike "_*" -and $_ -notlike ".deploy.env*" -and $_ -notlike "*.bak*"
}
if (-not ($top -contains "site") -or -not ($top -contains "deploy.sh")) {
    Write-Error "site\ or deploy.sh not found next to this script."; exit 1
}

$tgz = Join-Path $env:TEMP "personal-site-upload.tgz"
if (Test-Path $tgz) { Remove-Item $tgz -Force }
& tar -czf $tgz --exclude "site/dist" --exclude "site/out" --exclude "__pycache__" --exclude "*.bak*" `
    --exclude ".DS_Store" --exclude "desktop.ini" --exclude ".venv" @top
if ($LASTEXITCODE -ne 0) { Write-Error "tar failed (exit $LASTEXITCODE)."; exit 1 }

# Safety net: refuse to send an archive that holds anything from the exclude list.
$entries = & tar -tzf $tgz
$bad = $entries | Where-Object { $_ -match '^site/(dist|out)/|(^|/)__pycache__/|(^|/)\.venv/|^\.git/|^\.claude/|^_|^\.deploy\.env|\.bak' }
if ($bad) {
    Remove-Item $tgz -Force
    Write-Error ("The archive contains files that must stay on this PC: " + (($bad | Select-Object -First 5) -join ", ")); exit 1
}
$files = @($entries | Where-Object { $_ -notmatch '/$' })
$sizeKb = [math]::Round((Get-Item $tgz).Length / 1KB)
Write-Host ("Packed {0} files, {1} KB: {2}" -f $files.Count, $sizeKb, ($top -join ", ")) -ForegroundColor Cyan

if ($DryRun) {
    $files | ForEach-Object { Write-Host "  $_" }
    Remove-Item $tgz -Force
    Write-Host "Dry run: nothing was sent." -ForegroundColor Green
    exit 0
}

# ---------------------------------------------------------------- where it goes
$envFile = Join-Path $PSScriptRoot ".deploy.env"
if (-not (Test-Path $envFile)) { Write-Error "Set SERVER in .deploy.env (copy .deploy.env.example)."; exit 1 }
$line = Get-Content $envFile | Where-Object { $_ -match '^\s*SERVER\s*=' } | Select-Object -First 1
$Server = ($line -replace '^\s*SERVER\s*=\s*', '').Trim().Trim('"').Trim("'")
if (-not $Server) { Write-Error "SERVER is empty in .deploy.env."; exit 1 }

# ---------------------------------------------------------------- send
Write-Host "Sending to the server ..." -ForegroundColor Cyan
& scp -q $tgz "${Server}:/tmp/personal-site-upload.tgz"
if ($LASTEXITCODE -ne 0) { Remove-Item $tgz -Force; Write-Error "Upload failed - check your SSH access."; exit 1 }
Remove-Item $tgz -Force

# Unpack beside the real folder, then let the server's rsync mirror it in. Same rules as upload.sh:
# compare by content, delete what is gone here, leave the excluded paths alone. Nothing here is live.
$mirror = "rm -rf /opt/personal-site.incoming && mkdir -p /opt/personal-site.incoming " +
    "&& tar -xzf /tmp/personal-site-upload.tgz -C /opt/personal-site.incoming && rm -f /tmp/personal-site-upload.tgz " +
    "&& rsync -rlc --delete --exclude='.git/' --exclude='.DS_Store' --exclude='*.bak*' --exclude='site/dist/' " +
    "--exclude='site/out/' --exclude='__pycache__/' --exclude='.venv/' --exclude='/_*/' --exclude='/.claude/' " +
    "--exclude='/.gitattributes' --exclude='/.deploy.env*' --exclude='desktop.ini' " +
    "/opt/personal-site.incoming/ /opt/personal-site/ && rm -rf /opt/personal-site.incoming"
& ssh $Server $mirror
if ($LASTEXITCODE -ne 0) { Write-Error "Mirroring on the server failed (exit $LASTEXITCODE). Nothing is live."; exit 1 }

# ---------------------------------------------------------------- deploy.sh on the server
# -t: deploy.sh asks before applying or rolling back, so it needs a terminal.
$remote = "bash /opt/personal-site/deploy.sh $Action"
if ($Yes -and $Action -ne "status") { $remote += " --yes" }
& ssh -t $Server $remote
exit $LASTEXITCODE
