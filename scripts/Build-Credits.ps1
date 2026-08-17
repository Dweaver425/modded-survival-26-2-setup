param(
    [string]$StableRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [switch]$UseModrinth
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$packDirectories = [ordered]@{
    'Windows Voxy' = 'Client Mod Pack - Windows - Voxy'
    'Windows DH' = 'Client Mod Pack - Windows - Distant Horizons'
    'Windows No LOD' = 'Client Mod Pack - Windows - No LOD'
    'Mac DH' = 'Client Mod Pack - Mac - Distant Horizons'
    'Mac No LOD' = 'Client Mod Pack - Mac - No LOD'
    'Extreme Low End' = 'Client Mod Pack - Universal - Extreme Low End'
    'Server' = 'Server Mod Pack'
    'Resource Library' = 'Client Resourcepacks'
    'Shader Library' = 'Client Shaderpacks'
}

function Convert-ToStringList {
    param([object]$Value)

    if ($null -eq $Value) { return @() }
    $items = if ($Value -is [System.Array]) { @($Value) } else { @($Value) }
    $result = foreach ($item in $items) {
        if ($null -eq $item) { continue }
        if ($item -is [string]) {
            $item
        } elseif ($item.PSObject.Properties.Name -contains 'name') {
            [string]$item.name
        } else {
            [string]$item
        }
    }
    return @($result | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Read-ArchiveMetadata {
    param([string]$Path)

    $result = [ordered]@{
        id = $null
        name = $null
        version = $null
        authors = @()
        license = @()
        homepage = $null
        sources = $null
        issues = $null
        metadataSource = $null
    }

    $archive = $null
    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
        $fabricEntry = $archive.Entries | Where-Object { $_.FullName -eq 'fabric.mod.json' } | Select-Object -First 1
        if ($fabricEntry) {
            $reader = [System.IO.StreamReader]::new($fabricEntry.Open())
            try { $metadata = ($reader.ReadToEnd() | ConvertFrom-Json) } finally { $reader.Dispose() }
            if ($metadata -is [System.Array]) { $metadata = $metadata | Select-Object -First 1 }
            $result.id = [string]$metadata.id
            $result.name = [string]$metadata.name
            $result.version = [string]$metadata.version
            $result.authors = @(Convert-ToStringList $metadata.authors)
            $result.license = @(Convert-ToStringList $metadata.license)
            if ($metadata.contact) {
                $result.homepage = [string]$metadata.contact.homepage
                $result.sources = [string]$metadata.contact.sources
                $result.issues = [string]$metadata.contact.issues
            }
            $result.metadataSource = 'fabric.mod.json'
        } else {
            $packEntry = $archive.Entries | Where-Object { $_.FullName -eq 'pack.mcmeta' } | Select-Object -First 1
            if ($packEntry) {
                $reader = [System.IO.StreamReader]::new($packEntry.Open())
                try { $metadata = ($reader.ReadToEnd() | ConvertFrom-Json) } finally { $reader.Dispose() }
                $result.name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
                $result.metadataSource = 'pack.mcmeta'
            }
        }
    } catch {
        $result.metadataSource = "unreadable: $($_.Exception.Message)"
    } finally {
        if ($archive) { $archive.Dispose() }
    }

    return [pscustomobject]$result
}

function Invoke-ModrinthBatchPost {
    param([string[]]$Hashes)

    $output = @{}
    for ($offset = 0; $offset -lt $Hashes.Count; $offset += 100) {
        $last = [Math]::Min($offset + 99, $Hashes.Count - 1)
        $batch = @($Hashes[$offset..$last])
        $body = @{ hashes = $batch; algorithm = 'sha512' } | ConvertTo-Json -Compress -Depth 4
        $response = Invoke-RestMethod -Method Post -Uri 'https://api.modrinth.com/v2/version_files' -ContentType 'application/json' -Headers @{ 'User-Agent' = 'Dweaver425/modded-survival-26-2-setup credits-builder' } -Body $body
        foreach ($property in $response.PSObject.Properties) {
            $output[$property.Name.ToLowerInvariant()] = $property.Value
        }
    }
    return $output
}

function Invoke-ModrinthBatchGet {
    param(
        [string]$Endpoint,
        [string[]]$Ids
    )

    $output = @()
    for ($offset = 0; $offset -lt $Ids.Count; $offset += 100) {
        $last = [Math]::Min($offset + 99, $Ids.Count - 1)
        $batch = @($Ids[$offset..$last])
        $jsonIds = $batch | ConvertTo-Json -Compress
        $encoded = [System.Uri]::EscapeDataString($jsonIds)
        $uri = "https://api.modrinth.com/v2/$Endpoint`?ids=$encoded"
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers @{ 'User-Agent' = 'Dweaver425/modded-survival-26-2-setup credits-builder' }
        $output += @($response)
    }
    return @($output)
}

function Escape-MarkdownCell {
    param([object]$Value)
    if ($null -eq $Value) { return '' }
    return ([string]$Value).Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
}

$entriesByHash = @{}
foreach ($packName in $packDirectories.Keys) {
    $packPath = Join-Path $StableRoot $packDirectories[$packName]
    if (-not (Test-Path -LiteralPath $packPath)) { continue }

    $searches = @(
        @{ path = (Join-Path $packPath 'mods'); filter = '*.jar'; type = 'Mod' },
        @{ path = (Join-Path $packPath 'resourcepacks'); filter = '*.zip'; type = 'Resource Pack' },
        @{ path = (Join-Path $packPath 'shaderpacks'); filter = '*.zip'; type = 'Shader' }
    )
    if ($packName -eq 'Resource Library') {
        $searches = @(@{ path = $packPath; filter = '*.zip'; type = 'Resource Pack' })
    } elseif ($packName -eq 'Shader Library') {
        $searches = @(@{ path = $packPath; filter = '*.zip'; type = 'Shader' })
    }

    foreach ($search in $searches) {
        if (-not (Test-Path -LiteralPath $search.path)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $search.path -File -Filter $search.filter) {
            $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA512).Hash.ToLowerInvariant()
            if (-not $entriesByHash.ContainsKey($hash)) {
                $metadata = Read-ArchiveMetadata -Path $file.FullName
                $entriesByHash[$hash] = [ordered]@{
                    sha512 = $hash
                    file = $file.Name
                    type = $search.type
                    packs = [System.Collections.Generic.List[string]]::new()
                    id = $metadata.id
                    name = $metadata.name
                    version = $metadata.version
                    authors = @($metadata.authors)
                    license = @($metadata.license)
                    projectUrl = @($metadata.homepage, $metadata.sources | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
                    issuesUrl = $metadata.issues
                    metadataSource = $metadata.metadataSource
                    modrinthProjectId = $null
                    modrinthVersionId = $null
                    sourceType = $null
                    sourceVerified = $false
                }
            }
            if (-not $entriesByHash[$hash].packs.Contains($packName)) {
                $entriesByHash[$hash].packs.Add($packName)
            }
        }
    }
}

$entries = @($entriesByHash.Values)

if ($UseModrinth) {
    $versionByHash = Invoke-ModrinthBatchPost -Hashes @($entries.sha512)
    $projectIds = [System.Collections.Generic.HashSet[string]]::new()
    $authorIds = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($entry in $entries) {
        $version = $versionByHash[$entry.sha512]
        if ($null -eq $version) { continue }
        $entry.modrinthProjectId = [string]$version.project_id
        $entry.modrinthVersionId = [string]$version.id
        if (-not [string]::IsNullOrWhiteSpace([string]$version.version_number)) {
            $entry.version = [string]$version.version_number
        }
        [void]$projectIds.Add([string]$version.project_id)
        [void]$authorIds.Add([string]$version.author_id)
    }

    $projectById = @{}
    if ($projectIds.Count -gt 0) {
        foreach ($project in Invoke-ModrinthBatchGet -Endpoint 'projects' -Ids @($projectIds)) {
            $projectById[[string]$project.id] = $project
        }
    }

    $userById = @{}
    if ($authorIds.Count -gt 0) {
        foreach ($user in Invoke-ModrinthBatchGet -Endpoint 'users' -Ids @($authorIds)) {
            $userById[[string]$user.id] = $user
        }
    }

    foreach ($entry in $entries) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.modrinthProjectId)) { continue }
        $project = $projectById[[string]$entry.modrinthProjectId]
        if ($null -eq $project) { continue }
        $entry.name = [string]$project.title
        $projectType = switch ([string]$project.project_type) {
            'resourcepack' { 'resourcepack' }
            'shader' { 'shader' }
            'modpack' { 'modpack' }
            default { 'mod' }
        }
        $entry.projectUrl = "https://modrinth.com/$projectType/$($project.slug)"
        $entry.issuesUrl = [string]$project.issues_url
        if ($project.license) {
            $entry.license = @([string]$project.license.id)
            $entry.licenseUrl = [string]$project.license.url
        }
        if (@($entry.authors).Count -eq 0) {
            $version = $versionByHash[$entry.sha512]
            $uploader = $userById[[string]$version.author_id]
            if ($uploader) { $entry.authors = @([string]$uploader.username) }
        }
        $entry.sourceType = 'Modrinth SHA-512 match'
        $entry.sourceVerified = $true
    }
}

$visualOverrides = @{
    '3D Vanilla v1.19.zip' = @{ name = 'Vanilla 3D Extension'; authors = @('SkeletonKingIII'); url = 'https://www.curseforge.com/minecraft/texture-packs/vanilla-3d-extension' }
}
foreach ($entry in $entries) {
    if ($visualOverrides.ContainsKey([string]$entry.file)) {
        $override = $visualOverrides[[string]$entry.file]
        $entry.name = $override.name
        $entry.authors = @($override.authors)
        $entry.projectUrl = $override.url
        $entry.sourceType = 'Documented manual source'
        $entry.sourceVerified = $true
    }
    if ([string]$entry.file -eq 'indium-server-dummy.jar') {
        $entry.name = 'Indium Server Dummy (compatibility shim)'
        $entry.authors = @('Dylan Weaver (Stixity)')
        $entry.license = @('Pack-original metadata component; redistribution with this modpack permitted by the author')
        $entry.projectUrl = 'original-components/indium-server-dummy/README.md'
        $entry.sourceType = 'Pack-original documentation'
        $entry.sourceVerified = $true
    }
    if ([string]::IsNullOrWhiteSpace([string]$entry.name)) {
        $entry.name = [System.IO.Path]::GetFileNameWithoutExtension([string]$entry.file)
    }
}

$sortedEntries = @($entries | Sort-Object type, name, file)
$generatedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# Third-Party Project Credits')
$lines.Add('')
$lines.Add('This distribution is a community modpack. Dylan Weaver did not create the third-party mods, libraries, resource packs, shaders, Fabric Loader, or Minecraft listed below.')
$lines.Add('')
$lines.Add('## Pack Authorship')
$lines.Add('')
$lines.Add('- **Pack assembly, configuration, compatibility testing, and documentation:** Dylan Weaver (Minecraft username: Stixity)')
$lines.Add('- **Original pack contribution:** one coordinated Fabric 26.2 server/client distribution that supports Voxy Server for Dylan''s Voxy client and Distant Horizons for friends using DH clients.')
$lines.Add('- **Only original mod component:** `indium-server-dummy.jar`, a metadata-only dedicated-server compatibility shim created by Dylan Weaver. It contains no executable code and is documented in [`original-components/indium-server-dummy`](original-components/indium-server-dummy/README.md).')
$lines.Add('- Dylan does **not** claim authorship or ownership of Voxy, Voxy Server, Distant Horizons, Fabric, Minecraft, or any other project in this ledger.')
$lines.Add('- Minecraft is created by Mojang Studios. Fabric is created and maintained by the FabricMC project.')
$lines.Add('')
$lines.Add('Credits do not replace or modify any project license. Each project remains the property of its respective author or team. Use the linked official project page for current license terms, support, and downloads.')
$lines.Add('')
$lines.Add("Generated from the exact distributed files on $generatedAt. Modrinth matches are verified by SHA-512 file hash.")
$lines.Add('')
$lines.Add('### Pack labels')
$lines.Add('')
$lines.Add('`Windows Voxy`, `Windows DH`, `Windows No LOD`, `Mac DH`, `Mac No LOD`, `Extreme Low End`, `Server`, `Resource Library`, and `Shader Library`.')

foreach ($section in @('Mod', 'Resource Pack', 'Shader')) {
    $sectionEntries = @($sortedEntries | Where-Object { $_.type -eq $section })
    if ($sectionEntries.Count -eq 0) { continue }
    $heading = if ($section -eq 'Mod') { 'Mods And Libraries' } elseif ($section -eq 'Resource Pack') { 'Resource Packs' } else { 'Shaders' }
    $lines.Add('')
    $lines.Add("## $heading")
    $lines.Add('')
    $lines.Add('| Project | Credited author(s) | Version | License | Distributed in | File |')
    $lines.Add('| --- | --- | --- | --- | --- | --- |')
    foreach ($entry in $sectionEntries) {
        $name = Escape-MarkdownCell $entry.name
        $projectCell = if (-not [string]::IsNullOrWhiteSpace([string]$entry.projectUrl)) { "[$name]($($entry.projectUrl))" } else { "$name *(source link not found)*" }
        $authors = if (@($entry.authors).Count -gt 0) { (@($entry.authors) -join ', ') } else { 'See project page / metadata unavailable' }
        $licenseText = if (@($entry.license).Count -gt 0) { (@($entry.license) -join ', ') } else { 'Not declared in matched metadata' }
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.licenseUrl)) {
            $licenseText = "[$licenseText]($($entry.licenseUrl))"
        }
        $packs = @($entry.packs | Sort-Object) -join ', '
        $fileCell = Escape-MarkdownCell $entry.file
        $lines.Add("| $projectCell | $(Escape-MarkdownCell $authors) | $(Escape-MarkdownCell $entry.version) | $(Escape-MarkdownCell $licenseText) | $(Escape-MarkdownCell $packs) | ``$fileCell`` |")
    }
}

$unresolved = @($sortedEntries | Where-Object { -not $_.sourceVerified -or [string]::IsNullOrWhiteSpace([string]$_.projectUrl) })
$lines.Add('')
$lines.Add('## Metadata Notes')
$lines.Add('')
$lines.Add("- Total unique distributed projects/files: $($sortedEntries.Count)")
$lines.Add("- Files matched to an official Modrinth project by SHA-512: $(@($sortedEntries | Where-Object { $_.sourceType -eq 'Modrinth SHA-512 match' }).Count)")
$lines.Add("- Files with a documented manual or pack-original source: $(@($sortedEntries | Where-Object { $_.sourceType -ne 'Modrinth SHA-512 match' -and $_.sourceVerified }).Count)")
$lines.Add("- Files requiring manual source-link review: $($unresolved.Count)")
$lines.Add('- A missing source link does not mean the file is uncredited: embedded author and license metadata is retained whenever present.')

$guideRoot = Split-Path -Parent $PSScriptRoot
$creditsPath = Join-Path $guideRoot 'CREDITS.md'
$jsonPath = Join-Path $guideRoot 'credits.json'
[System.IO.File]::WriteAllLines($creditsPath, $lines, [System.Text.UTF8Encoding]::new($false))
$jsonOutput = [ordered]@{
    generated = $generatedAt
    minecraft = '26.2'
    packAssembler = 'Dylan Weaver (Stixity)'
    uniqueFiles = $sortedEntries.Count
    verifiedSources = @($sortedEntries | Where-Object sourceVerified).Count
    modrinthMatched = @($sortedEntries | Where-Object { $_.sourceType -eq 'Modrinth SHA-512 match' }).Count
    documentedManualSources = @($sortedEntries | Where-Object { $_.sourceType -ne 'Modrinth SHA-512 match' -and $_.sourceVerified }).Count
    manualReview = $unresolved.Count
    entries = $sortedEntries
}
[System.IO.File]::WriteAllText($jsonPath, ($jsonOutput | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    CreditsPath = $creditsPath
    JsonPath = $jsonPath
    UniqueFiles = $sortedEntries.Count
    VerifiedSources = @($sortedEntries | Where-Object sourceVerified).Count
    ManualReview = $unresolved.Count
    MissingAuthors = @($sortedEntries | Where-Object { @($_.authors).Count -eq 0 }).Count
    MissingLicenses = @($sortedEntries | Where-Object { @($_.license).Count -eq 0 }).Count
}
