#requires -Version 7.0
param(
    [Parameter(Mandatory)] [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9_.-]+$')] [string]$SourceContainer,
    [Parameter(Mandatory)] [ValidatePattern('^[a-z_][a-z_0-9]*$')] [string]$SourceUser,
    [Parameter(Mandatory)] [ValidatePattern('^[a-z_][a-z_0-9]*$')] [string]$SourceDatabase,
    [switch]$KeepRestored
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$root = Split-Path -Parent $PSScriptRoot
$target = 'xbd-mj-restore-' + [Guid]::NewGuid().ToString('N').Substring(0, 12)
$scratch = Join-Path $root ".tmp/$target"
$sourceArchive = "/tmp/$target.dump"
$targetArchive = '/tmp/mahjong-restore.dump'
$localArchive = Join-Path $scratch 'mahjong.dump'
$started = $false
$dumpCreated = $false
$passed = $false
$tables = @('accounts','account_sessions','game_matches','mahjong_match_results','mahjong_match_members',
    'mahjong_friend_rooms','mahjong_active_matches','mahjong_active_completions','mahjong_table_reports')
$countQuery = ($tables | ForEach-Object { "SELECT '$_', count(*) FROM $_" }) -join ' UNION ALL '

function Get-Counts($Container, $User, $Database) {
    @(& docker exec $Container psql -X -q -A -t -v ON_ERROR_STOP=1 -U $User -d $Database -c $countQuery | Sort-Object)
}

try {
    New-Item -ItemType Directory -Path $scratch | Out-Null
    $imageID = (& docker inspect --type container --format '{{.Image}}' $SourceContainer | Out-String).Trim()
    if ($imageID -notmatch '^sha256:[a-f0-9]{64}$') { throw 'The PostgreSQL source image could not be identified.' }
    $sourceBefore = Get-Counts $SourceContainer $SourceUser $SourceDatabase
    & docker exec $SourceContainer pg_dump --format=custom --no-owner --no-privileges -U $SourceUser -d $SourceDatabase -f $sourceArchive
    $dumpCreated = $true
    & docker cp "${SourceContainer}:$sourceArchive" $localArchive
    $sourceAfter = Get-Counts $SourceContainer $SourceUser $SourceDatabase
    if (Compare-Object $sourceBefore $sourceAfter) { throw 'Source row counts changed during the drill. Stop the source API writers and rerun.' }

    & docker run --rm -d --name $target -p '127.0.0.1::5432' -e 'POSTGRES_HOST_AUTH_METHOD=trust' `
        -e "POSTGRES_USER=$SourceUser" -e "POSTGRES_DB=$SourceDatabase" $imageID | Out-Null
    $started = $true
    $ready = $false
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        for ($attempt = 0; $attempt -lt 45; $attempt++) {
            & docker exec $target pg_isready -q -h 127.0.0.1 -U $SourceUser -d $SourceDatabase
            if ($LASTEXITCODE -eq 0) { $ready = $true; break }
            Start-Sleep -Milliseconds 400
        }
    } finally { $PSNativeCommandUseErrorActionPreference = $true }
    if (-not $ready) { throw 'The isolated target PostgreSQL did not become ready.' }
    & docker cp $localArchive "${target}:$targetArchive"
    & docker exec $target pg_restore --exit-on-error --single-transaction --no-owner --no-privileges `
        -U $SourceUser -d $SourceDatabase $targetArchive
    $restored = Get-Counts $target $SourceUser $SourceDatabase
    if (Compare-Object $sourceAfter $restored) { throw 'Restored table counts disagree with the source.' }
    $sha256 = (Get-FileHash -LiteralPath $localArchive -Algorithm SHA256).Hash
    $portOutput = (& docker port $target 5432/tcp | Out-String).Trim()
    if ($portOutput -notmatch '^127\.0\.0\.1:(\d+)$') { throw 'The target is not published on loopback only.' }
    $port = $Matches[1]
    $manifest = [ordered]@{
        restored_port = [int]$port
        container = $target
        dump_sha256 = $sha256
        restored_counts = $restored
    }
    $manifest | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $scratch 'restore.json') -Encoding utf8NoBOM
    $passed = $true
    Write-Output "MAHJONG_BACKUP_RESTORE_OK restored_port=$port project=$target sha256=$sha256"
    if ($KeepRestored) { Write-Output "Stop: docker stop $target" }
} finally {
    if ($dumpCreated) { & docker exec $SourceContainer rm -f $sourceArchive }
    if ($started -and -not ($KeepRestored -and $passed)) { & docker stop $target | Out-Null }
    if (Test-Path -LiteralPath $localArchive -PathType Leaf) { Remove-Item -LiteralPath $localArchive }
}
