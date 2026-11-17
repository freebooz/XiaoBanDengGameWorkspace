#requires -Version 7.0
[CmdletBinding()]
param(
    [switch]$KeepRunning,
    [switch]$VerifyAdmin,
    [switch]$VerifyMonitor,
    [string]$AdminBrowserProbe,
    [ValidateRange(0,65535)][int]$Port = 0,
    [ValidateRange(0,65535)][int]$AdminPort = 0,
    [string]$OpenSslPath
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$root = Split-Path $PSScriptRoot -Parent
$project = 'xbd-mj-tls-' + [Guid]::NewGuid().ToString('N').Substring(0, 12)
$profile = Join-Path $root 'deploy/mahjong-local/compose.yml'
$scratch = Join-Path (Join-Path $root '.tmp') $project
$ca = Join-Path $scratch 'ca.crt'
$tls = Join-Path $scratch 'tls'
$compose = @('compose', '-p', $project, '-f', $profile)
$vars = @('XBD_MAHJONG_POSTGRES_PASSWORD','XBD_MAHJONG_TLS_PORT','XBD_MAHJONG_TLS_DIR','XBD_MAHJONG_ADMIN_PORT','XBD_MAHJONG_ADMIN_CREDENTIALS')
$previous = @{}
foreach ($name in $vars) { $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$started = $false
$passed = $false
if ($AdminBrowserProbe -and -not $VerifyAdmin) { throw 'AdminBrowserProbe requires VerifyAdmin.' }

if (-not $OpenSslPath) {
    $opensslCommand = Get-Command openssl -ErrorAction SilentlyContinue
    if ($null -ne $opensslCommand) { $OpenSslPath = $opensslCommand.Source }
    elseif ($env:ProgramFiles) { $OpenSslPath = Join-Path $env:ProgramFiles 'Git/usr/bin/openssl.exe' }
}
if (-not $OpenSslPath -or -not (Test-Path -LiteralPath $OpenSslPath -PathType Leaf)) {
    throw 'OpenSSL not found. Supply its executable path via -OpenSslPath.'
}

if (-not ('XbdMahjongTlsProbe' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;

public static class XbdMahjongTlsProbe {
    public static RemoteCertificateValidationCallback Trust(string path) {
        var root = X509Certificate2.CreateFromPem(File.ReadAllText(path));
        return (sender, cert, supplied, errors) => {
            if (cert == null || (errors & ~SslPolicyErrors.RemoteCertificateChainErrors) != 0) return false;
            using var chain = new X509Chain();
            using var leaf = new X509Certificate2(cert);
            chain.ChainPolicy.TrustMode = X509ChainTrustMode.CustomRootTrust;
            chain.ChainPolicy.CustomTrustStore.Add(root);
            chain.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;
            chain.ChainPolicy.ApplicationPolicy.Add(new System.Security.Cryptography.Oid("1.3.6.1.5.5.7.3.1"));
            return chain.Build(leaf);
        };
    }
}
'@
}

function Read-Frame($socket, $cancel) {
    $buffer = [byte[]]::new(16384)
    $bytes = [IO.MemoryStream]::new()
    try {
        do {
            $part = $socket.ReceiveAsync([ArraySegment[byte]]::new($buffer), $cancel).GetAwaiter().GetResult()
            if ($part.MessageType -ne [Net.WebSockets.WebSocketMessageType]::Text -or $bytes.Length + $part.Count -gt 262144) {
                throw 'Unexpected frame from authenticated Mahjong WebSocket.'
            }
            $bytes.Write($buffer, 0, $part.Count)
        } until ($part.EndOfMessage)
        return [Text.Encoding]::UTF8.GetString($bytes.ToArray()) | ConvertFrom-Json
    } finally { $bytes.Dispose() }
}

try {
    New-Item -ItemType Directory -Path $tls | Out-Null
    $workKey = Join-Path $scratch 'ca.key'
    $leafKey = Join-Path $tls 'server.key'
    $csr = Join-Path $scratch 'server.csr'
    $extensions = Join-Path $scratch 'server.ext'
    @('basicConstraints=critical,CA:FALSE', 'keyUsage=critical,digitalSignature,keyEncipherment', 'extendedKeyUsage=serverAuth', 'subjectAltName=DNS:localhost,IP:127.0.0.1') |
        Set-Content -LiteralPath $extensions -Encoding ascii
    & $OpenSslPath genrsa -out $workKey 2048
    & $OpenSslPath req -new -x509 -key $workKey -out $ca -days 7 -subj '/CN=XBD Mahjong Local Fixture CA' -addext 'basicConstraints=critical,CA:TRUE' -addext 'keyUsage=critical,keyCertSign,cRLSign'
    & $OpenSslPath genrsa -out $leafKey 2048
    & $OpenSslPath req -new -key $leafKey -out $csr -subj '/CN=localhost'
    & $OpenSslPath x509 -req -in $csr -CA $ca -CAkey $workKey -CAcreateserial -out (Join-Path $tls 'server.crt') -days 7 -extfile $extensions
    Remove-Item -LiteralPath $workKey

    $env:XBD_MAHJONG_POSTGRES_PASSWORD = [Guid]::NewGuid().ToString('N')
    $env:XBD_MAHJONG_TLS_DIR = $tls
    $env:XBD_MAHJONG_TLS_PORT = $Port.ToString()
    if ($VerifyAdmin -or $VerifyMonitor) {
        $adminOverlay = Join-Path $root 'deploy/mahjong-local/admin.compose.yml'
        $compose += '-f', $adminOverlay
        $env:XBD_MAHJONG_ADMIN_PORT = $AdminPort.ToString()
        $env:XBD_MAHJONG_ADMIN_CREDENTIALS = Join-Path $scratch 'admin-digests.json'
        $principals = @()
    }
    if ($VerifyAdmin) {
        $operator = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).TrimEnd('=').Replace('+','-').Replace('/','_')
        $digest = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::ASCII.GetBytes($operator))).ToLowerInvariant()
        $principals += @{name='fixture-reviewer'; token_sha256=$digest; capabilities=@('mahjong:review')}
    }
    if ($VerifyMonitor) {
        $monitorOperator = $env:XBD_MAHJONG_MONITOR_CREDENTIAL
        if (-not $monitorOperator) {
            $monitorOperator = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).TrimEnd('=').Replace('+','-').Replace('/','_')
        }
        if ($monitorOperator -cnotmatch '^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$') {
            throw 'Invalid platform monitor verification credential format.'
        }
        $digest = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::ASCII.GetBytes($monitorOperator))).ToLowerInvariant()
        $principals += @{name='local-monitor'; token_sha256=$digest; capabilities=@('platform:read')}
    }
    if ($VerifyAdmin -or $VerifyMonitor) {
        ConvertTo-Json -InputObject $principals -Depth 5 |
            Set-Content -LiteralPath $env:XBD_MAHJONG_ADMIN_CREDENTIALS -Encoding utf8NoBOM
    }
    $envFile = Join-Path $scratch 'fixture.env'
    if ($KeepRunning) {
        $vars | ForEach-Object { "$_=$([Environment]::GetEnvironmentVariable($_, 'Process'))" } | Set-Content -LiteralPath $envFile -Encoding utf8
    }

    $started = $true
    & docker @compose up --build --wait --wait-timeout 90
    $edge = ((& docker @compose port edge 443) | Select-Object -First 1).Trim()
    if ($edge -notmatch '^127\.0\.0\.1:(\d+)$') { throw "TLS edge did not bind loopback: $edge" }
    $authority = $edge
    $base = "https://$authority"
    $apiID = (& docker @compose ps -q api).Trim()
    if ((& docker inspect --format '{{.State.Health.Status}}' $apiID).Trim() -ne 'healthy') {
        throw 'Linux API readiness did not pass.'
    }
    foreach ($service in @('api','postgres','redis')) {
        $id = (& docker @compose ps -q $service).Trim()
        $bindings = (& docker inspect --format '{{json .HostConfig.PortBindings}}' $id | ConvertFrom-Json -AsHashtable)
        if ($null -ne $bindings -and $bindings.Count -gt 0) { throw "Unexpected host publication for $service." }
    }

    $handler = [Net.Http.SocketsHttpHandler]::new()
    $handler.UseProxy = $false
    $handler.SslOptions.RemoteCertificateValidationCallback = [XbdMahjongTlsProbe]::Trust($ca)
    $http = [Net.Http.HttpClient]::new($handler)
    $http.Timeout = [TimeSpan]::FromSeconds(12)
    try {
        $response = $http.GetAsync("$base/health").GetAwaiter().GetResult()
        $health = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json -AsHashtable
        if ([int]$response.StatusCode -ne 200 -or $health.Count -ne 1 -or $health.status -ne 'ready') { throw 'Minimal readiness response was unexpected.' }
        foreach ($path in @('/api/v1/admin/overview','/api/v1/admin/rooms','/api/v1/admin/matches','/api/v1/admin/monitor/stream','/api/v1/admin/monitor/snapshot','/api/v1/admin/wallet/eggs/grant','/mahjong-internal-readiness','/ws')) {
            $response = $http.GetAsync($base + $path).GetAwaiter().GetResult()
            if ([int]$response.StatusCode -ne 404) { throw "Unexpected public exposure of $path." }
        }
        $response = $http.GetAsync("$base/api/v1/catalog").GetAwaiter().GetResult()
        if ([int]$response.StatusCode -ne 200) { throw 'Catalog was unavailable.' }
        $response = $http.GetAsync("$base/api/v1/mahjong/history").GetAwaiter().GetResult()
        if ([int]$response.StatusCode -ne 401) { throw 'Anonymous history request was not rejected.' }
        $response = $http.GetAsync("$base/api/v1/wallet").GetAwaiter().GetResult()
        if ([int]$response.StatusCode -ne 401) { throw 'Anonymous wallet request was not rejected.' }
        $response = $http.GetAsync("$base/api/v1/mahjong/ws").GetAwaiter().GetResult()
        if ([int]$response.StatusCode -ne 401) { throw 'Anonymous Mahjong WebSocket endpoint was not rejected.' }
        $response = $http.PostAsync("$base/api/v1/auth/guest", [Net.Http.StringContent]::new('{}', [Text.Encoding]::UTF8, 'application/json')).GetAwaiter().GetResult()
        if ([int]$response.StatusCode -ne 201) { throw 'HTTPS guest login failed.' }
        $guest = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
        $credential = [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $guest.session_token)
        $http.DefaultRequestHeaders.Authorization = $credential
        $response = $http.GetAsync("$base/api/v1/auth/session").GetAwaiter().GetResult()
        if ([int]$response.StatusCode -ne 200) { throw 'HTTPS session restoration failed.' }
        $session = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
        if ($session.account_id -ne $guest.account_id) { throw 'HTTPS session restored a different account.' }

        $socket = [Net.WebSockets.ClientWebSocket]::new()
        $timeout = [Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(12))
        try {
            $socket.Options.Proxy = [Net.WebProxy]::new()
            $socket.Options.RemoteCertificateValidationCallback = [XbdMahjongTlsProbe]::Trust($ca)
            $socket.Options.SetRequestHeader('Authorization', $credential.ToString())
            $null = $socket.ConnectAsync([Uri]"wss://$authority/api/v1/mahjong/ws", $timeout.Token).GetAwaiter().GetResult()
            if ((Read-Frame $socket $timeout.Token).type -ne 'connected') { throw 'Authenticated WSS handshake did not yield connected.' }
            $payload = [Text.Encoding]::UTF8.GetBytes((@{type='mahjong_lobby_subscribe';client_id=$session.account_id} | ConvertTo-Json -Compress))
            $null = $socket.SendAsync([ArraySegment[byte]]::new($payload), [Net.WebSockets.WebSocketMessageType]::Text, $true, $timeout.Token).GetAwaiter().GetResult()
            $snapshot = Read-Frame $socket $timeout.Token
            if ($snapshot.type -ne 'mahjong_lobby_state' -or $snapshot.state.status -ne 'idle') { throw 'Authenticated WSS lobby snapshot was unexpected.' }
        } finally { $socket.Dispose(); $timeout.Dispose() }
        $guest = $null
        $credential = $null
        $http.DefaultRequestHeaders.Authorization = $null
        if ($VerifyAdmin -or $VerifyMonitor) {
            $adminAddress = ((& docker @compose port admin 443) | Select-Object -First 1).Trim()
            if ($adminAddress -notmatch '^127\.0\.0\.1:(\d+)$') { throw 'The management edge must bind loopback.' }
            $adminBase = "https://$adminAddress"
        }
        if ($VerifyAdmin) {
            $html = $http.GetStringAsync("$adminBase/mahjong/reports").GetAwaiter().GetResult()
            if ($html -notmatch '<div id="app"' -or $html -notmatch '/assets/[^"\s]+\.js') { throw 'Missing built admin application.' }
            $bundlePath = $Matches[0]
            $bundle = $http.GetStringAsync($adminBase + $bundlePath).GetAwaiter().GetResult()
            if ($bundle -notmatch '/api/v1/admin/session') { throw 'Admin JavaScript bundle does not provide real login.' }
            if ([int]$http.GetAsync("$adminBase/api/v1/admin/mahjong/reports").GetAwaiter().GetResult().StatusCode -ne 401) {
                throw 'Unauthenticated management access was not denied.'
            }
            $http.DefaultRequestHeaders.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $operator)
            $checked = $http.GetStringAsync("$adminBase/api/v1/admin/session").GetAwaiter().GetResult() | ConvertFrom-Json
            if ($checked.admin_name -ne 'fixture-reviewer' -or $checked.capabilities -notcontains 'mahjong:review') { throw 'Wrong admin principal.' }
            $queue = $http.GetStringAsync("$adminBase/api/v1/admin/mahjong/reports?status=pending").GetAwaiter().GetResult() | ConvertFrom-Json
            if ($queue.total -ne 0 -or $queue.items -isnot [Array]) { throw 'Wrong initial report queue.' }
            if ([int]$http.GetAsync("$adminBase/api/v1/admin/overview").GetAwaiter().GetResult().StatusCode -ne 403 -or
                [int]$http.GetAsync("$base/api/v1/admin/mahjong/reports").GetAwaiter().GetResult().StatusCode -ne 404) {
                throw 'Unexpected admin scope or player-edge route.'
            }
            if ($AdminBrowserProbe) {
                $probePath = (Resolve-Path -LiteralPath $AdminBrowserProbe).ProviderPath
                $reportID = [Guid]::NewGuid().ToString()
                $reporter = [Guid]::NewGuid().ToString()
                $reported = [Guid]::NewGuid().ToString()
                $fixtureMatch = [Guid]::NewGuid().ToString()
                $seed = @"
INSERT INTO accounts(account_id,display_name) VALUES ('$reporter','Audit fixture A'),('$reported','Audit fixture B');
INSERT INTO mahjong_table_reports(report_id,match_id,room_id,reporter_account_id,target_account_id,reporter_seat,target_seat,reason)
VALUES ('$reportID','$fixtureMatch','1648','$reporter','$reported',0,1,'spam');
"@
                $seed | & docker @compose exec -T postgres psql -q -v ON_ERROR_STOP=1 -U xbd -d xbd
                @{ base=$adminBase; token=$operator; leaf=(Join-Path $tls 'server.crt'); reportId=$reportID } |
                    ConvertTo-Json -Compress | & node $probePath
                $status = (& docker @compose exec -T postgres psql -Aqt -v ON_ERROR_STOP=1 -U xbd -d xbd -c "SELECT status_after,analyst FROM mahjong_table_report_reviews WHERE report_id='$reportID'" | Out-String).Trim()
                if ($status -ne 'upheld|fixture-reviewer') { throw 'Browser did not commit the expected report disposition.' }
            }
            $http.DefaultRequestHeaders.Authorization = $null
            $operator = $null
            Write-Output "MAHJONG_ADMIN_TLS_OK endpoint=$adminBase scope=mahjong:review player_edge=404"
        }
        if ($VerifyMonitor) {
            $html = $http.GetStringAsync("$adminBase/monitor").GetAwaiter().GetResult()
            if ($html -notmatch '<div id="app"') { throw 'Missing built monitor application.' }
            $path = "$adminBase/api/v1/admin/monitor"
            if ([int]$http.GetAsync("$path/snapshot").GetAwaiter().GetResult().StatusCode -ne 401) {
                throw 'Unauthenticated monitor snapshot was not rejected.'
            }
            $http.DefaultRequestHeaders.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $monitorOperator)
            $state = $http.GetStringAsync("$path/snapshot").GetAwaiter().GetResult() | ConvertFrom-Json
            $healthy = @($state.services | Where-Object { $_.id -in @('api','postgres','redis') -and $_.status -eq 'ok' })
            if ($healthy.Count -ne 3 -or -not ($state.lobbies.game_id -contains 'mahjong')) {
                throw 'Monitor did not provide the expected health and lobby snapshot.'
            }
            $http.DefaultRequestHeaders.Authorization = $null
            $monitorOperator = $null
            Write-Output "MAHJONG_MONITOR_TLS_OK endpoint=$adminBase/monitor services=3 scope=platform:read player_edge=404"
        }
        Write-Host "MAHJONG_TLS_OK endpoint=$base project=$project"
        if ($KeepRunning) {
            Write-Host "Local CA: $ca"
            $overlayArg = if ($VerifyAdmin -or $VerifyMonitor) { " -f `"$adminOverlay`"" } else { '' }
            Write-Host "Stop: docker compose --env-file `"$envFile`" -p $project -f `"$profile`"$overlayArg down -v"
        }
        $passed = $true
    } finally { $http.Dispose() }
} finally {
    try {
        if ($started -and -not ($KeepRunning -and $passed)) { & docker @compose down -v }
    } finally {
        if (-not ($KeepRunning -and $passed)) {
            foreach ($file in @($envFile, $workKey, $leafKey, $(if ($VerifyAdmin -or $VerifyMonitor) { $env:XBD_MAHJONG_ADMIN_CREDENTIALS }))) {
                if ($file -and (Test-Path -LiteralPath $file -PathType Leaf)) { Remove-Item -LiteralPath $file }
            }
        }
        foreach ($name in $vars) { [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process') }
    }
}
