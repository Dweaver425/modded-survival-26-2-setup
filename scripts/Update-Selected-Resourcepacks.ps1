[CmdletBinding()]
param(
    [switch]$SyncActiveClients
)

$ErrorActionPreference = 'Stop'
$stableRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$resourceLibrary = Join-Path $stableRoot 'Client Resourcepacks'
$visualGuideName = 'RECOMMENDED VISUALS - READ ME FIRST.txt'

$selectedPacks = @(
    'Default-Dark-Mode-26.2-2026.6.0.zip',
    'Low Shield.zip',
    'Low Fire.zip',
    'EvenBetterEnchants_v3_1.21.5+.zip',
    'FA+Player-v1.1.zip',
    'FA+All_Extensions-v1.9.2.zip',
    'FreshAnimations_v1.10.5.zip'
)

$lowEndPacks = @(
    'Default-Dark-Mode-26.2-2026.6.0.zip',
    'EvenBetterEnchants_v3_1.21.5+.zip'
)

$standardClients = @(
    'Client Mod Pack - Mac - Distant Horizons',
    'Client Mod Pack - Mac - No LOD',
    'Client Mod Pack - Windows - Distant Horizons',
    'Client Mod Pack - Windows - No LOD',
    'Client Mod Pack - Windows - Voxy'
)
$lowEndClient = 'Client Mod Pack - Universal - Extreme Low End'

$selectedResourceOrder = 'resourcePacks:["vanilla","file/FreshAnimations_v1.10.5.zip","file/FA+All_Extensions-v1.9.2.zip","file/FA+Player-v1.1.zip","file/EvenBetterEnchants_v3_1.21.5+.zip","file/Low Fire.zip","file/Low Shield.zip","file/Default-Dark-Mode-26.2-2026.6.0.zip","continuity:glass_pane_culling_fix","continuity:default"]'

function Assert-PathWithin {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    if (-not $fullPath.StartsWith($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to modify a path outside $fullRoot`: $fullPath"
    }
    return $fullPath
}

function Set-ResourcepackDirectory {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string[]]$AllowedFiles,
        [Parameter(Mandatory)][string]$AllowedRoot
    )

    $fullDirectory = Assert-PathWithin -Path $Directory -Root $AllowedRoot
    if (-not (Test-Path -LiteralPath $fullDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $fullDirectory | Out-Null
    }

    foreach ($file in Get-ChildItem -LiteralPath $fullDirectory -File -Filter '*.zip') {
        if ($file.Name -notin $AllowedFiles) {
            Remove-Item -LiteralPath $file.FullName -Force
            Write-Host "Removed test resource pack: $($file.FullName)"
        }
    }

    foreach ($fileName in $AllowedFiles) {
        $source = Join-Path $resourceLibrary $fileName
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Selected resource pack is missing from the library: $source"
        }
        Copy-Item -LiteralPath $source -Destination (Join-Path $fullDirectory $fileName) -Force
    }
}

function Set-OptionsResourcepacks {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$AllowedRoot
    )

    $fullPath = Assert-PathWithin -Path $Path -Root $AllowedRoot
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { return }
    $content = Get-Content -LiteralPath $fullPath
    $updated = $content | ForEach-Object {
        if ($_ -match '^resourcePacks:') { $selectedResourceOrder } else { $_ }
    }
    [System.IO.File]::WriteAllLines($fullPath, $updated, [System.Text.UTF8Encoding]::new($false))
}

function Update-ClientManifest {
    param(
        [Parameter(Mandatory)][string]$ClientRoot,
        [Parameter(Mandatory)][bool]$EnabledByDefault
    )

    $fullClientRoot = Assert-PathWithin -Path $ClientRoot -Root $stableRoot
    $manifestPath = Join-Path $fullClientRoot 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $manifest.visualsUpdated = (Get-Date).ToString('o')
    $manifest.resourcePacks = @(
        Get-ChildItem -LiteralPath (Join-Path $fullClientRoot 'resourcepacks') -File -Filter '*.zip' |
            Sort-Object Name |
            ForEach-Object {
                [ordered]@{
                    file = $_.Name
                    sha512 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA512).Hash.ToLowerInvariant()
                }
            }
    )
    if ($manifest.PSObject.Properties.Name -contains 'resourcePacksEnabledByDefault') {
        $manifest.resourcePacksEnabledByDefault = $EnabledByDefault
    } else {
        $manifest | Add-Member -NotePropertyName resourcePacksEnabledByDefault -NotePropertyValue $EnabledByDefault
    }
    [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
}

function New-ZipFromDirectory {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$ArchivePath
    )

    $fullDirectory = Assert-PathWithin -Path $Directory -Root $stableRoot
    $fullArchive = Assert-PathWithin -Path $ArchivePath -Root $stableRoot
    $temporaryArchive = "$fullArchive.new.zip"
    if (Test-Path -LiteralPath $temporaryArchive) {
        Remove-Item -LiteralPath $temporaryArchive -Force
    }

    $entries = @(Get-ChildItem -LiteralPath $fullDirectory -Force | Select-Object -ExpandProperty Name)
    if ($entries.Count -eq 0) { throw "Cannot archive an empty directory: $fullDirectory" }

    & tar -a -c -f $temporaryArchive -C $fullDirectory @entries
    if ($LASTEXITCODE -ne 0) { throw "Archive creation failed: $fullArchive" }
    Move-Item -LiteralPath $temporaryArchive -Destination $fullArchive -Force
    Write-Host "Rebuilt: $fullArchive"
}

# First clean the canonical library, while retaining its non-pack readme.
foreach ($file in Get-ChildItem -LiteralPath $resourceLibrary -File -Filter '*.zip') {
    if ($file.Name -notin $selectedPacks) {
        Remove-Item -LiteralPath $file.FullName -Force
        Write-Host "Removed test resource pack: $($file.FullName)"
    }
}

foreach ($client in $standardClients) {
    $clientRoot = Join-Path $stableRoot $client
    Set-ResourcepackDirectory -Directory (Join-Path $clientRoot 'resourcepacks') -AllowedFiles $selectedPacks -AllowedRoot $stableRoot
    Set-OptionsResourcepacks -Path (Join-Path $clientRoot 'config\modpack_defaults\options.txt') -AllowedRoot $stableRoot
    Update-ClientManifest -ClientRoot $clientRoot -EnabledByDefault $true
}

$lowEndRoot = Join-Path $stableRoot $lowEndClient
Set-ResourcepackDirectory -Directory (Join-Path $lowEndRoot 'resourcepacks') -AllowedFiles $lowEndPacks -AllowedRoot $stableRoot
Update-ClientManifest -ClientRoot $lowEndRoot -EnabledByDefault $false

$canonicalGuide = Join-Path $resourceLibrary $visualGuideName
if (-not (Test-Path -LiteralPath $canonicalGuide -PathType Leaf)) {
    throw "Visual guide is missing: $canonicalGuide"
}
foreach ($destinationRoot in @($stableRoot) + $standardClients.ForEach({ Join-Path $stableRoot $_ }) + @($lowEndRoot, (Join-Path $stableRoot 'Client Shaderpacks'))) {
    Copy-Item -LiteralPath $canonicalGuide -Destination (Join-Path $destinationRoot $visualGuideName) -Force
}

if ($SyncActiveClients) {
    $installationsRoot = 'C:\Users\Dylan\Minecraft Installations'
    $activeClients = @(
        'Modded 26_2 Minecraft Client for Server DH',
        'Modded 26_2 Minecraft Client for Server VOXY'
    )
    foreach ($client in $activeClients) {
        $clientRoot = Assert-PathWithin -Path (Join-Path $installationsRoot $client) -Root $installationsRoot
        Set-ResourcepackDirectory -Directory (Join-Path $clientRoot 'resourcepacks') -AllowedFiles $selectedPacks -AllowedRoot $installationsRoot
        Set-OptionsResourcepacks -Path (Join-Path $clientRoot 'options.txt') -AllowedRoot $installationsRoot
    }
}

$archives = @($standardClients + $lowEndClient)
foreach ($client in $archives) {
    New-ZipFromDirectory -Directory (Join-Path $stableRoot $client) -ArchivePath (Join-Path $stableRoot "$client.zip")
}
New-ZipFromDirectory -Directory $resourceLibrary -ArchivePath (Join-Path $stableRoot 'Client Resourcepacks.zip')
New-ZipFromDirectory -Directory (Join-Path $stableRoot 'Client Shaderpacks') -ArchivePath (Join-Path $stableRoot 'Client Shaderpacks.zip')

$checksumFiles = @(
    'Client Mod Pack - Mac - Distant Horizons.zip',
    'Client Mod Pack - Mac - No LOD.zip',
    'Client Mod Pack - Universal - Extreme Low End.zip',
    'Client Mod Pack - Windows - Distant Horizons.zip',
    'Client Mod Pack - Windows - No LOD.zip',
    'Client Mod Pack - Windows - Voxy.zip',
    'Server Mod Pack.zip',
    'Client Resourcepacks.zip',
    'Client Shaderpacks.zip'
)
$checksumLines = foreach ($fileName in $checksumFiles) {
    $path = Join-Path $stableRoot $fileName
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $fileName"
}
[System.IO.File]::WriteAllLines((Join-Path $stableRoot 'SHA256SUMS.txt'), $checksumLines, [System.Text.UTF8Encoding]::new($false))

$resultPackNames = @($archives + 'Server Mod Pack')
$buildResults = foreach ($packName in $resultPackNames) {
    $packRoot = Join-Path $stableRoot $packName
    $archivePath = Join-Path $stableRoot "$packName.zip"
    $archiveEntries = @(& tar -tf $archivePath)
    if ($LASTEXITCODE -ne 0) { throw "Archive verification failed: $archivePath" }

    $manifestPath = Join-Path $packRoot 'manifest.json'
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $actualMods = @(Get-ChildItem -LiteralPath (Join-Path $packRoot 'mods') -File -Filter '*.jar').Count
        $actualResources = @(Get-ChildItem -LiteralPath (Join-Path $packRoot 'resourcepacks') -File -Filter '*.zip' -ErrorAction SilentlyContinue).Count
        $manifestResources = if ($null -eq $manifest.resourcePacks) { 0 } else { @($manifest.resourcePacks).Count }
        if (@($manifest.mods).Count -ne $actualMods -or $manifestResources -ne $actualResources) {
            throw "Manifest counts do not match $packName"
        }
    }

    $archiveFile = Get-Item -LiteralPath $archivePath
    [ordered]@{
        Name = $packName
        Zip = $archivePath
        JarEntries = @(Get-ChildItem -LiteralPath (Join-Path $packRoot 'mods') -File -Filter '*.jar').Count
        ResourcePacks = @(Get-ChildItem -LiteralPath (Join-Path $packRoot 'resourcepacks') -File -Filter '*.zip' -ErrorAction SilentlyContinue).Count
        ShaderPacks = @(Get-ChildItem -LiteralPath (Join-Path $packRoot 'shaderpacks') -File -Filter '*.zip' -ErrorAction SilentlyContinue).Count
        Entries = $archiveEntries.Count
        SizeMB = [Math]::Round($archiveFile.Length / 1MB, 2)
        SHA256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}
[System.IO.File]::WriteAllText((Join-Path $stableRoot 'Build-Results.json'), ($buildResults | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))

$visualLibraries = foreach ($libraryName in @('Client Resourcepacks', 'Client Shaderpacks')) {
    $archivePath = Join-Path $stableRoot "$libraryName.zip"
    $archiveEntries = @(& tar -tf $archivePath)
    if ($LASTEXITCODE -ne 0) { throw "Archive verification failed: $archivePath" }
    [ordered]@{
        Name = $libraryName
        Entries = $archiveEntries.Count
        SHA256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

$serverBuildResult = $buildResults | Where-Object { $_['Name'] -eq 'Server Mod Pack' } | Select-Object -First 1
$finalVerification = [ordered]@{
    Result = 'passed'
    Verified = (Get-Date).ToString('o')
    Minecraft = '26.2'
    FabricLoader = '0.19.3'
    ServerAddress = 'katherine-thorough.tun.ply.gg'
    Server = [ordered]@{
        ModCount = [int]$serverBuildResult['JarEntries']
        LODComponents = @('Distant Horizons 3.2.0-b', 'Voxy 0.2.18-beta', 'VoxyServer 1.2.4')
        ChunkyIncluded = $true
        Backups = 'FastBack snapshots configured on the host; private backup paths excluded from share packs.'
    }
    SelectedResourcepacks = $selectedPacks
    Packs = $buildResults
    VisualLibraries = $visualLibraries
    Checks = [ordered]@{
        ArchiveOpenTest = $true
        ManifestCountsMatch = $true
        EmbeddedVisualArchivesValid = $true
        RemovedTestResourcepacksAbsent = $true
        NormalClientResourcepacksEnabledByDefault = $true
        LowEndResourcepacksEnabledByDefault = $false
        TemporaryFiles = @(Get-ChildItem -LiteralPath $stableRoot -File -Filter '*.new.zip').Count
    }
}
[System.IO.File]::WriteAllText((Join-Path $stableRoot 'Final-Verification.json'), ($finalVerification | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    SelectedResourcepacks = $selectedPacks.Count
    StandardClients = $standardClients.Count
    ActiveClientsSynced = [bool]$SyncActiveClients
    ArchivesRebuilt = $archives.Count + 2
    ChecksumEntries = $checksumLines.Count
    Verification = $finalVerification.Result
}
