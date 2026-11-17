param(
    [Parameter(Mandatory)] [string]$Godot,
    [Parameter(Mandatory)] [string]$TemplateArchive,
    [Parameter(Mandatory)] [ValidatePattern('^\d+\.\d+\.\d+$')] [string]$Version,
    [Parameter(Mandatory)] [ValidateRange(1, 2100000000)] [int]$VersionCode,
    [Parameter(Mandatory)] [uri]$Server,
    [string]$AndroidSdk = $env:ANDROID_SDK_ROOT,
    [string]$JavaSdk = $env:JAVA_HOME,
    [ValidateSet('Both', 'Windows', 'Android')] [string]$Platform = 'Both',
    [string]$LocalTestCA,
    [switch]$DevelopmentDomainTest,
    [string]$LocalTestSigningDirectory,
    [string]$ValidatedProjectDirectory,
    [ValidatePattern('^[a-z][a-z0-9]*$')] [string]$AndroidTestSuffix,
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$engine = (Resolve-Path -LiteralPath $Godot).ProviderPath
$archive = (Resolve-Path -LiteralPath $TemplateArchive).ProviderPath
if (-not $Server.IsAbsoluteUri -or $Server.Scheme -ne 'https' -or $Server.AbsolutePath -ne '/' -or
    $Server.Query -or $Server.Fragment -or $Server.UserInfo) {
    throw 'Server must be a valid HTTPS origin.'
}
$knownDevelopmentDomains = @('api.xbd.freeboozstudio.test')
$isDevelopmentDomainTest = $DevelopmentDomainTest.IsPresent -and ($Server.DnsSafeHost -in $knownDevelopmentDomains) -and $Server.Port -eq 443
if ($DevelopmentDomainTest -and (-not $isDevelopmentDomainTest -or -not $LocalTestCA)) {
    throw 'DevelopmentDomainTest requires the known api.xbd.freeboozstudio.test HTTPS origin on port 443 and a public LocalTestCA.'
}
if ($LocalTestCA -and -not $Server.IsLoopback -and -not $isDevelopmentDomainTest) {
    throw 'LocalTestCA requires loopback or an explicitly selected, known development test domain.'
}
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $workspace ('.tmp/mahjong-candidate-' + $Version + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
}
$output = [IO.Path]::GetFullPath($OutputDirectory, $workspace)
if (-not $output.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)) {
    throw 'OutputDirectory must be a new directory under the workspace.'
}

$engineVersion = (& $engine --version | Select-Object -First 1).Trim()
if ($engineVersion -notmatch '^(4\.\d+\.\d+\.stable)\.') { throw 'A stable Godot 4 build is required.' }
$templateVersion = $Matches[1]
$archiveVersion = (& tar -xOf $archive templates/version.txt | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $archiveVersion -ne $templateVersion) { throw 'Godot and export templates must have matching versions.' }
$buildWindows = $Platform -ne 'Android'
$buildAndroid = $Platform -ne 'Windows'
if ($AndroidTestSuffix -and (-not $buildAndroid -or -not $LocalTestCA)) {
    throw 'AndroidTestSuffix requires a local Android test build.'
}
if ($isDevelopmentDomainTest -and $buildAndroid -and -not $AndroidTestSuffix) {
    throw 'Development-domain Android builds require AndroidTestSuffix to preserve installed production apps.'
}
$requiresDebugKeystore = $buildAndroid -and -not $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH
if ($LocalTestSigningDirectory -and (-not $buildAndroid -or -not $LocalTestCA -or -not $AndroidTestSuffix -or -not $requiresDebugKeystore)) {
    throw 'LocalTestSigningDirectory is only for explicitly suffixed Android test packages with LocalTestCA and no external signing key.'
}
$signingDirectory = $null
if ($LocalTestSigningDirectory) {
    $signingDirectory = [IO.Path]::GetFullPath($LocalTestSigningDirectory, $workspace)
    $signingRoot = [IO.Path]::GetFullPath((Join-Path $workspace '.tmp/mahjong-test-signing')) + [IO.Path]::DirectorySeparatorChar
    if (-not $signingDirectory.StartsWith($signingRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Local test signing storage must stay below the project .tmp/mahjong-test-signing directory.'
    }
    $signingAncestor = $signingDirectory
    while ($signingAncestor -and $signingAncestor -ne $workspace) {
        if ((Test-Path -LiteralPath $signingAncestor) -and ((Get-Item -LiteralPath $signingAncestor).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Local test signing storage and its parents must not be redirected directories.'
        }
        $signingAncestor = Split-Path -Parent $signingAncestor
    }
}
if ($buildAndroid) {
    if (-not $AndroidSdk -or -not $JavaSdk) { throw 'Set AndroidSdk and JavaSdk for Android export.' }
    $AndroidSdk = (Resolve-Path -LiteralPath $AndroidSdk).ProviderPath
    $JavaSdk = (Resolve-Path -LiteralPath $JavaSdk).ProviderPath
    if (-not (Test-Path -LiteralPath (Join-Path $AndroidSdk 'platform-tools/adb.exe')) -or
        -not (Test-Path -LiteralPath (Join-Path $JavaSdk 'bin/java.exe'))) { throw 'Android SDK and Java SDK are required for Android export.' }
    if ($requiresDebugKeystore -and -not $LocalTestCA -and -not $Server.IsLoopback) { throw 'Configure GODOT_ANDROID_KEYSTORE_RELEASE_* for an external origin.' }
}

$project = Join-Path $output 'project'
$validatedSnapshotHash = $null
if ($ValidatedProjectDirectory) {
    $snapshot = (Resolve-Path -LiteralPath $ValidatedProjectDirectory).ProviderPath
    if (-not $snapshot.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'ValidatedProjectDirectory must be inside this workspace.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $snapshot 'project.godot')) -or -not (Test-Path -LiteralPath (Join-Path $snapshot 'product.json'))) {
        throw 'Validated snapshot must contain project.godot and product.json.'
    }
    $snapshotProduct = Get-Content -LiteralPath (Join-Path $snapshot 'product.json') -Raw | ConvertFrom-Json
    if ($snapshotProduct.game_id -ne 'mahjong' -or $snapshotProduct.product_id -ne 'xbd_mahjong') {
        throw 'Validated snapshot must be the mahjong product.'
    }
    $snapshotManifest = Join-Path (Split-Path -Parent $snapshot) 'source-manifest.json'
    if (-not (Test-Path -LiteralPath $snapshotManifest)) { throw 'Validated snapshot requires its adjacent source-manifest.json.' }
    $validatedSnapshotHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $snapshotManifest).Hash
    $snapshotFiles = @(Get-Content -LiteralPath $snapshotManifest -Raw | ConvertFrom-Json)
    $snapshotPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $snapshotFiles) {
        $relative = [string]$entry.path
        if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[/\\])\.\.([/\\]|$)' -or $relative -match '^\.godot[/\\]' -or $entry.sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or -not $snapshotPaths.Add($relative.Replace('\', '/'))) {
            throw 'Invalid or duplicate resource in validated snapshot manifest.'
        }
        $sourceFile = [IO.Path]::GetFullPath((Join-Path $snapshot $relative))
        if (-not $sourceFile.StartsWith($snapshot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Snapshot resource escapes its project.' }
        $ancestor = $sourceFile
        while ($ancestor -and $ancestor -ne $workspace) {
            if ((Get-Item -LiteralPath $ancestor).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Snapshot resources must not be redirected.' }
            $ancestor = Split-Path -Parent $ancestor
        }
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $sourceFile).Hash -ne $entry.sha256) { throw "Validated resource changed: $relative" }
        $destinationFile = Join-Path $project $relative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destinationFile) | Out-Null
        Copy-Item -LiteralPath $sourceFile -Destination $destinationFile
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $destinationFile).Hash -ne $entry.sha256) { throw "Snapshot copy changed: $relative" }
    }
    $actualFiles = @(Get-ChildItem -LiteralPath $snapshot -File -Recurse -Force | Where-Object { -not [IO.Path]::GetRelativePath($snapshot, $_.FullName).Replace('\', '/').StartsWith('.godot/') })
    if ($actualFiles.Count -ne $snapshotFiles.Count) { throw 'Validated snapshot has unlisted or missing resources.' }
    Copy-Item -LiteralPath $snapshotManifest -Destination (Join-Path $output 'validated-source-manifest.json')
    Write-Host "Using validated mahjong snapshot: $snapshot"
} else {
    & (Join-Path $PSScriptRoot 'compose-godot.ps1') -Product mahjong -OutputDirectory $project
}
$coach = Join-Path $project 'modules/games/mahjong/guiyang/native'
$hasCoach = Test-Path -LiteralPath (Join-Path $coach 'mahjong_coach.gdextension') -PathType Leaf
if ($hasCoach -and $buildAndroid -and -not (Test-Path -LiteralPath (Join-Path $coach 'libmahjong_coach_gdext.so') -PathType Leaf)) {
    throw 'The composed coach bundle has no Android ARM64 library. Rebuild via build-mahjong-coach.ps1.'
}
$profile = Join-Path $output 'profile'
$engineState = Join-Path $profile 'Godot'
$templates = Join-Path $engineState "export_templates/$templateVersion"
New-Item -ItemType Directory -Path $templates -Force | Out-Null
$files = @()
if ($buildWindows) { $files += 'templates/windows_release_x86_64.exe' }
if ($buildAndroid) { $files += 'templates/android_release.apk' }
& tar -xf $archive -C $templates --strip-components=1 @files
if ($LASTEXITCODE -ne 0) { throw 'Could not extract matching export templates.' }

$utf8 = [Text.UTF8Encoding]::new($false)
if ($buildAndroid) {
    # Keep the manifest's mipmap/icon reference and all density variants. Override only the
    # API 26 drawable with a bitmap so AdaptiveIconDrawable cannot add a mask or a black base.
    $templateApk = Join-Path $templates 'android_release.apk'
    $aapt = Get-ChildItem -LiteralPath (Join-Path $AndroidSdk 'build-tools') -Directory |
        Where-Object Name -Match '^\d+\.\d+\.\d+$' |
        Sort-Object { [version]$_.Name } -Descending |
        ForEach-Object { Join-Path $_.FullName 'aapt2.exe' } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    $androidJar = Get-ChildItem -LiteralPath (Join-Path $AndroidSdk 'platforms') -Directory |
        Where-Object Name -Match '^android-\d+$' |
        Sort-Object { [int]($_.Name -replace '^android-') } -Descending |
        ForEach-Object { Join-Path $_.FullName 'android.jar' } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $aapt -or -not $androidJar) { throw 'Android SDK aapt2 and platform android.jar are required for the transparent launcher icon.' }
    $templatePackage = (& $aapt dump packagename $templateApk | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $templatePackage -notmatch '^[a-zA-Z0-9_.]+$') { throw 'Cannot read the Android template package.' }
    $templateResources = @(& $aapt dump resources $templateApk)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read the Android template resources.' }
    $launcherResources = @($templateResources | Select-String '^\s*resource (0x[0-9a-fA-F]{8}) mipmap/(icon|icon_foreground)\s*$')
    if ($launcherResources.Count -ne 2) { throw 'Android template launcher resource IDs do not match the expected density layout.' }
    $launcherWork = Join-Path $profile 'launcher-resources'
    $launcherSrc = Join-Path $launcherWork 'res'
    New-Item -ItemType Directory -Path (Join-Path $launcherSrc 'mipmap-anydpi-v26'),(Join-Path $launcherSrc 'values') -Force | Out-Null
    $launcherXml = 'res/mipmap-anydpi-v26/icon.xml'
    [IO.File]::WriteAllText((Join-Path $launcherWork $launcherXml), '<bitmap xmlns:android="http://schemas.android.com/apk/res/android" android:src="@mipmap/icon_foreground"/>', $utf8)
    [IO.File]::WriteAllText((Join-Path $launcherSrc 'values/launcher.xml'), '<resources><item type="mipmap" name="icon_foreground">@null</item></resources>', $utf8)
    $launcherManifest = Join-Path $launcherWork 'AndroidManifest.xml'
    [IO.File]::WriteAllText($launcherManifest, ('<manifest package="' + $templatePackage + '"/>'), $utf8)
    $resourceIds = Join-Path $launcherWork 'ids.txt'
    $resourceIdLines = foreach ($name in $launcherResources) {
        $id = $name.Matches[0]
        "$($templatePackage):mipmap/$($id.Groups[2].Value) = $($id.Groups[1].Value)"
    }
    [IO.File]::WriteAllLines($resourceIds, [string[]]$resourceIdLines, $utf8)
    $compiledLauncher = Join-Path $launcherWork 'compiled.zip'
    $launcherApk = Join-Path $launcherWork 'launcher.apk'
    & $aapt compile --dir $launcherSrc -o $compiledLauncher
    if ($LASTEXITCODE -ne 0) { throw 'Could not compile the transparent Android launcher bitmap.' }
    & $aapt link --manifest $launcherManifest -I $androidJar --stable-ids $resourceIds -o $launcherApk $compiledLauncher
    if ($LASTEXITCODE -ne 0) { throw 'Could not link the transparent Android launcher bitmap.' }
    $launcherZip = [IO.Compression.ZipFile]::OpenRead($launcherApk)
    try {
        $bitmapXml = $launcherZip.GetEntry($launcherXml)
        if (-not $bitmapXml) { throw 'Compiled transparent launcher drawable is missing.' }
        $templateZip = [IO.Compression.ZipFile]::Open($templateApk, [IO.Compression.ZipArchiveMode]::Update)
        try {
            $oldDrawable = $templateZip.GetEntry($launcherXml)
            if (-not $oldDrawable) { throw 'Android template adaptive drawable is missing.' }
            $oldDrawable.Delete()
            $newDrawable = $templateZip.CreateEntry($launcherXml)
            $sourceStream = $bitmapXml.Open()
            try {
                $targetStream = $newDrawable.Open()
                try { $sourceStream.CopyTo($targetStream) } finally { $targetStream.Dispose() }
            } finally { $sourceStream.Dispose() }
        } finally { $templateZip.Dispose() }
    } finally { $launcherZip.Dispose() }
}

$projectFile = Join-Path $project 'project.godot'
$settings = [IO.File]::ReadAllText($projectFile)
$serverOrigin = $Server.GetLeftPart([UriPartial]::Authority)
$settings = [regex]::Replace($settings, '(?m)^config/version="[^"\r\n]*"\r?\n', '')
$settings = $settings.Replace('run/main_scene=', ('config/version="' + $Version + '"' + "`nrun/main_scene="))
if ($buildAndroid) {
    $settings = $settings.Replace('[rendering]', "[rendering]`ntextures/vram_compression/import_etc2_astc=true")
}
$settings = [regex]::Replace($settings, '(?m)^network/default_server_url="[^"\r\n]*"\r?\n', '')
$originSetting = 'network/default_server_url=' + (ConvertTo-Json $serverOrigin -Compress) + "`n"
if ($buildAndroid -and $isDevelopmentDomainTest) {
    $originSetting += "testing/log_mahjong_viewport=true`n"
}
if ($settings.Contains('[xiaobandeng]')) { $settings = $settings.Replace('[xiaobandeng]', ("[xiaobandeng]`n" + $originSetting)) }
else { $settings += "`n[xiaobandeng]`n" + $originSetting }
$presetsFile = Join-Path $project 'export_presets.cfg'
$presets = [IO.File]::ReadAllText($presetsFile).Replace("`r`n", "`n")
$presets = [regex]::Replace($presets, '(?m)^version/code=\d+$', "version/code=$VersionCode")
$presets = [regex]::Replace($presets, '(?m)^version/name="[^"]*"$', ('version/name="' + $Version + '"'))
if ($AndroidTestSuffix) {
    $presets = [regex]::Replace($presets, '(?m)^(package/unique_name="[^"]+)(")$', ('$1.' + $AndroidTestSuffix + '$2'))
    $presets = [regex]::Replace($presets, '(?m)^package/name="[^"]*"$', 'package/name="小板凳麻将"')
}
$extraResources = @()
if ($hasCoach) {
    $notices = 'mahjong-coach-third-party.txt'
    Copy-Item -LiteralPath (Join-Path $workspace 'rust-gdext/THIRD_PARTY_NOTICES.txt') -Destination (Join-Path $project $notices)
    $extraResources += $notices
}
if ($LocalTestCA) {
    $ca = (Resolve-Path -LiteralPath $LocalTestCA).ProviderPath
    $certificate = [IO.File]::ReadAllText($ca)
    if ($certificate -notmatch '-----BEGIN CERTIFICATE-----' -or $certificate -match 'PRIVATE KEY') { throw 'LocalTestCA must contain only a public PEM certificate.' }
    [IO.File]::WriteAllText((Join-Path $project 'local-fixture-ca.crt'), $certificate, $utf8)
    $settings = $settings.Replace('[network]', "[network]`ntls/certificate_bundle_override=`"res://local-fixture-ca.crt`"")
    # Local manual-test packages must not silently cap rendering on Android.
    # Limit this to the generated test project; release and player settings stay intact.
    $settings = $settings.Replace('[application]', "[application]`nrun/flush_stdout_on_print=true`nrun/max_fps=0")
    $settings = $settings.Replace('[display]', "[display]`nwindow/vsync/vsync_mode=0")
    $extraResources += 'local-fixture-ca.crt'
}
if ($extraResources.Count -gt 0) {
    # Keep the shared font license and any existing product resources while
    # appending the public test CA / native-coach notices.
    $presets = [regex]::Replace($presets, '(?m)^include_filter="([^"\r\n]*)"', {
        param($match)
        $filters = @($match.Groups[1].Value.Split(',', [StringSplitOptions]::RemoveEmptyEntries)) + $extraResources
        return 'include_filter="' + (($filters | Select-Object -Unique) -join ',') + '"'
    })
}
[IO.File]::WriteAllText($projectFile, $settings, $utf8)
[IO.File]::WriteAllText($presetsFile, $presets, $utf8)

$oldAppData = $env:APPDATA
$oldLocalAppData = $env:LOCALAPPDATA
$oldTemp = $env:TEMP
$oldTmp = $env:TMP
$oldKey = $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH
$oldKeyUser = $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER
$oldKeyPassword = $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
$localSigningReused = $false
try {
    $env:APPDATA = $profile
    $env:LOCALAPPDATA = $profile
    $tempDir = Join-Path $profile 'temp'
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    $env:TEMP = $tempDir
    $env:TMP = $tempDir
    if ($buildAndroid) {
        $editorMajorMinor = $templateVersion -replace '^([0-9]+\.[0-9]+).*$', '$1'
        $editorFile = Join-Path $engineState "editor_settings-$editorMajorMinor.tres"
        $editorBody = "[gd_resource type=`"EditorSettings`" format=3]`n`n[resource]`n"
        $editorBody += 'export/android/java_sdk_path = ' + (ConvertTo-Json $JavaSdk.Replace('\','/') -Compress) + "`n"
        $editorBody += 'export/android/android_sdk_path = ' + (ConvertTo-Json $AndroidSdk.Replace('\','/') -Compress) + "`n"
        [IO.File]::WriteAllText($editorFile, $editorBody, $utf8)
        if ($requiresDebugKeystore) {
            $localKey = Join-Path $profile 'candidate.keystore'
            $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = 'mahjong_candidate'
            if ($signingDirectory) {
                $localKey = Join-Path $signingDirectory 'candidate.keystore'
                $protectedPassword = Join-Path $signingDirectory 'password.dpapi'
                $signingMetadata = Join-Path $signingDirectory 'signing.json'
                $hasKey = Test-Path -LiteralPath $localKey
                $hasPassword = Test-Path -LiteralPath $protectedPassword
                if ($hasKey -ne $hasPassword) { throw 'Incomplete test signing pair; refusing to replace an existing key or password.' }
                if ($hasKey) {
                    $metadata = Get-Content -LiteralPath $signingMetadata -Raw | ConvertFrom-Json
                    if ($metadata.android_test_suffix -ne $AndroidTestSuffix) { throw 'Test signing directory belongs to another package suffix.' }
                    $secret = ConvertTo-SecureString ([IO.File]::ReadAllText($protectedPassword))
                    try { $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = [Net.NetworkCredential]::new('', $secret).Password }
                    finally { $secret.Dispose() }
                    $localSigningReused = $true
                } else {
                    if ((Test-Path -LiteralPath $signingDirectory) -and @(Get-ChildItem -LiteralPath $signingDirectory -Force).Count -gt 0) {
                        throw 'Refusing to initialize test signing in a nonempty unrelated directory.'
                    }
                    New-Item -ItemType Directory -Force -Path $signingDirectory | Out-Null
                    $owner = [Security.Principal.WindowsIdentity]::GetCurrent().User
                    $acl = [Security.AccessControl.DirectorySecurity]::new()
                    $acl.SetOwner($owner)
                    $acl.SetAccessRuleProtection($true, $false)
                    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($owner, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
                    Set-Acl -LiteralPath $signingDirectory -AclObject $acl
                    [IO.File]::WriteAllText((Join-Path $signingDirectory '.gitignore'), "*`n", $utf8)
                    $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
                    $secret = ConvertTo-SecureString $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD -AsPlainText -Force
                    try { [IO.File]::WriteAllText($protectedPassword, (ConvertFrom-SecureString $secret), $utf8) }
                    finally { $secret.Dispose() }
                    $metadata = @{ android_test_suffix = $AndroidTestSuffix; alias = $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER; protection = 'Windows DPAPI CurrentUser'; owner_sid = $owner.Value }
                    [IO.File]::WriteAllText($signingMetadata, ($metadata | ConvertTo-Json), $utf8)
                }
            } else {
                $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = [guid]::NewGuid().ToString('N')
            }
            $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = $localKey
            if ($localSigningReused) {
                & (Join-Path $JavaSdk 'bin/keytool.exe') -list -keystore $localKey -alias $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER -storepass:env GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD | Out-Null
                if ($LASTEXITCODE -ne 0) { throw 'Could not reopen the protected test signing key.' }
            } else {
                & (Join-Path $JavaSdk 'bin/keytool.exe') -genkeypair -keystore $localKey -alias $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER -storepass:env GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD -keypass:env GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD -keyalg RSA -keysize 2048 -validity 3650 -dname 'CN=XiaoBanDeng Local Candidate' -noprompt
                if ($LASTEXITCODE -ne 0) { throw 'Could not make a local Android candidate signing key.' }
            }
        }
    }
    & $engine --headless --path $project --import --log-file (Join-Path $output 'import.log') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }
    $packages = @()
    if ($buildWindows) {
        $exe = Join-Path $output 'XiaoBanDengMahjong.exe'
        & $engine --headless --path $project --export-release 'Windows Desktop（Windows桌面版）' $exe --log-file (Join-Path $output 'windows-export.log') | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $exe)) { throw 'Windows export failed.' }
        $packages += $exe, ([IO.Path]::ChangeExtension($exe, '.pck'))
        if ($hasCoach) {
            $packages += Join-Path $output 'mahjong_coach_gdext.dll'
        }
    }
    if ($buildAndroid) {
        $apk = Join-Path $output 'XiaoBanDengMahjong.apk'
        & $engine --headless --path $project --export-release 'Android（安卓移动版）' $apk --log-file (Join-Path $output 'android-export.log') | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $apk)) { throw 'Android export failed.' }
        $product = Get-Content -LiteralPath (Join-Path $project 'product.json') -Raw | ConvertFrom-Json
        $packageName = [string]$product.android_package
        if ($AndroidTestSuffix) { $packageName += ".$AndroidTestSuffix" }
        $badging = & $aapt dump badging $apk
        $identity = "^package: name='$([regex]::Escape($packageName))' versionCode='$VersionCode' versionName='$([regex]::Escape($Version))'( |$)"
        if ($LASTEXITCODE -ne 0 -or -not ($badging -match $identity)) {
            throw "Exported Android manifest does not match $packageName $Version ($VersionCode)."
        }
        $packages += $apk
    }
    if ($hasCoach) {
        $noticeOutput = Join-Path $output $notices
        Copy-Item -LiteralPath (Join-Path $project $notices) -Destination $noticeOutput
        $packages += $noticeOutput
    }
    $result = [ordered]@{
        product = 'xbd_mahjong'
        version = $Version
        version_code = $VersionCode
        godot = $engineVersion
        endpoint = $serverOrigin
        coach_native = $hasCoach
        local_ca = [bool]$LocalTestCA
        development_domain_test = [bool]$isDevelopmentDomainTest
        public_ca_sha256 = $(if ($LocalTestCA) { (Get-FileHash -Algorithm SHA256 -LiteralPath $ca).Hash } else { $null })
        android_local_key = [bool]$requiresDebugKeystore
        local_signing_persistent = [bool]$signingDirectory
        local_signing_reused = [bool]$localSigningReused
        validated_project = $(if ($ValidatedProjectDirectory) { $snapshot } else { $null })
        validated_snapshot_sha256 = $validatedSnapshotHash
        local_debug_limits = $(if ($LocalTestCA) { @{ max_fps = 0; vsync_mode = 0 } } else { $null })
        artifacts = @($packages | ForEach-Object { Get-Item -LiteralPath $_ } | ForEach-Object {
            @{ file = $_.Name; bytes = $_.Length; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash }
        })
    }
    [IO.File]::WriteAllText((Join-Path $output 'build-manifest.json'), ($result | ConvertTo-Json -Depth 6), $utf8)
    Write-Host "Mahjong candidate: $output"
} finally {
    $env:APPDATA = $oldAppData
    $env:LOCALAPPDATA = $oldLocalAppData
    $env:TEMP = $oldTemp
    $env:TMP = $oldTmp
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = $oldKey
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = $oldKeyUser
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = $oldKeyPassword
}
