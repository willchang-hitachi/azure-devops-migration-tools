<#
.SYNOPSIS
    Compares a local folder with a SharePoint document library and downloads new or updated files.

.DESCRIPTION
    Uses Microsoft Graph (delegated sign-in with your own account) to list every file in a
    SharePoint document library, compares it with a local folder, prints/exports a report and
    downloads files that are new on SharePoint or newer on SharePoint than the local copy.

    The script never deletes or uploads anything:
      New        - exists on SharePoint only                 -> downloaded
      Changed    - SharePoint copy is newer than local copy   -> downloaded
      LocalNewer - local copy is newer than SharePoint copy   -> skipped (use -OverwriteLocalChanges)
      LocalOnly  - exists locally only                        -> reported, left alone
      Same       - same modified time                         -> nothing to do

    After a download the local file's modified time is set to the SharePoint modified time, so the
    next run reports it as Same.

.PARAMETER SiteUrl
    URL of the SharePoint site (not the library view URL).

.PARAMETER Library
    Name of the document library. "Shared Documents" and "Documents" both match the default library.

.PARAMETER RemoteFolder
    Optional folder inside the library to sync, e.g. "Design/Phase 1". Defaults to the library root.

.PARAMETER LocalPath
    Local folder to compare against / download into.

.PARAMETER DryRun
    Only report differences, do not download anything.

.PARAMETER OverwriteLocalChanges
    Also download files whose local copy is newer than the SharePoint copy (discarding local edits).

.PARAMETER UseDeviceCode
    Sign in with a device code instead of a browser pop-up.

.EXAMPLE
    .\Sync-SharePoint.ps1 -DryRun

.EXAMPLE
    .\Sync-SharePoint.ps1 -RemoteFolder "Design" -LocalPath "D:\AEON\Design"
#>
[CmdletBinding()]
param(
    [string]$SiteUrl = 'https://hsdyn.sharepoint.com/sites/AEON-HitachiLMSprj',
    [string]$Library = 'Shared Documents',
    [string]$RemoteFolder = '',
    [string]$LocalPath = 'C:\Users\73008309\OneDrive - Hitachi Group\Documents\ACSM\Sharepoint\Documents\',
    [switch]$DryRun,
    [switch]$OverwriteLocalChanges,
    [switch]$UseDeviceCode
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$GraphRoot = 'https://graph.microsoft.com/v1.0'
$ReportName = 'sync-report.csv'
$TimeToleranceSeconds = 2

#region Helpers

function Invoke-Graph {
    param([Parameter(Mandatory)][string]$Uri)

    for ($attempt = 1; ; $attempt++) {
        try {
            return Invoke-MgGraphRequest -Method GET -Uri $Uri -OutputType Hashtable
        }
        catch {
            $message = $_.Exception.Message
            if ($attempt -lt 5 -and $message -match '429|503|504|TooManyRequests|ServiceUnavailable|GatewayTimeout') {
                $wait = [math]::Pow(2, $attempt)
                Write-Warning "Graph throttled/unavailable, retrying in $wait s ..."
                Start-Sleep -Seconds $wait
                continue
            }
            throw
        }
    }
}

function ConvertTo-UtcDate {
    param($Value)
    if ($Value -is [DateTime]) { return $Value.ToUniversalTime() }
    if ($Value -is [DateTimeOffset]) { return $Value.UtcDateTime }
    return [DateTimeOffset]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime
}

function ConvertTo-GraphPath {
    param([string]$Path)
    (($Path -split '[\\/]') | Where-Object { $_ } | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
}

function New-PathMap {
    New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
}

function Get-RemoteFiles {
    param([string]$DriveId, [string]$RootItemId)

    $files = New-PathMap
    $queue = New-Object System.Collections.Generic.Queue[object]
    $queue.Enqueue(@{ Id = $RootItemId; Path = '' })

    while ($queue.Count -gt 0) {
        $folder = $queue.Dequeue()
        $uri = "$GraphRoot/drives/$DriveId/items/$($folder.Id)/children?`$top=999&`$select=id,name,size,file,folder,package,lastModifiedDateTime"

        while ($uri) {
            $page = Invoke-Graph -Uri $uri
            foreach ($item in $page['value']) {
                $relative = if ($folder.Path) { "$($folder.Path)/$($item['name'])" } else { $item['name'] }

                if ($item.ContainsKey('folder') -and $item['folder']) {
                    $queue.Enqueue(@{ Id = $item['id']; Path = $relative })
                }
                elseif ($item.ContainsKey('file') -and $item['file']) {
                    $files[$relative] = [pscustomobject]@{
                        Id       = $item['id']
                        Path     = $relative
                        Size     = [long]$item['size']
                        Modified = ConvertTo-UtcDate $item['lastModifiedDateTime']
                    }
                }
                else {
                    Write-Verbose "Skipping non-file item (e.g. OneNote notebook): $relative"
                }
            }
            $uri = if ($page.ContainsKey('@odata.nextLink')) { $page['@odata.nextLink'] } else { $null }
        }
        Write-Host "`r  scanned SharePoint: $($files.Count) files" -NoNewline
    }
    Write-Host ''
    return $files
}

function Get-LocalFiles {
    param([string]$Root)

    $files = New-PathMap
    if (-not (Test-Path -LiteralPath $Root)) { return $files }

    Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $relative = $_.FullName.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/'
        if ($relative -eq $ReportName -or $relative -like '*.sync-part') { return }
        $files[$relative] = [pscustomobject]@{
            Path     = $relative
            FullName = $_.FullName
            Size     = $_.Length
            Modified = $_.LastWriteTimeUtc
        }
    }
    return $files
}

function Save-RemoteFile {
    param([string]$DriveId, $Remote, [string]$Target)

    # Fetch a fresh pre-authenticated download URL (they expire after about an hour).
    $item = Invoke-Graph -Uri "$GraphRoot/drives/$DriveId/items/$($Remote.Id)"
    $downloadUrl = $item['@microsoft.graph.downloadUrl']
    if (-not $downloadUrl) { throw 'Graph did not return a download URL for this item.' }

    $directory = Split-Path -Path $Target -Parent
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $temp = "$Target.sync-part"
    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $temp -UseBasicParsing
        Move-Item -LiteralPath $temp -Destination $Target -Force
        (Get-Item -LiteralPath $Target).LastWriteTimeUtc = $Remote.Modified
    }
    finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
    }
}

#endregion

#region Sign in and locate the library

if (-not (Get-Command Connect-MgGraph -ErrorAction SilentlyContinue)) {
    throw "Microsoft Graph PowerShell is not installed. Run: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser"
}

$scopes = @('Sites.Read.All', 'Files.Read.All')
$context = Get-MgContext
if (-not $context -or @($scopes | Where-Object { $context.Scopes -notcontains $_ }).Count -gt 0) {
    Write-Host 'Signing in to Microsoft Graph ...'
    if ($UseDeviceCode) { Connect-MgGraph -Scopes $scopes -UseDeviceCode -NoWelcome }
    else { Connect-MgGraph -Scopes $scopes -NoWelcome }
}
Write-Host "Signed in as $((Get-MgContext).Account)"

$siteUri = [Uri]$SiteUrl.TrimEnd('/')
$site = Invoke-Graph -Uri "$GraphRoot/sites/$($siteUri.Host):$($siteUri.AbsolutePath)"
Write-Host "Site:    $($site['displayName'])"

$drives = (Invoke-Graph -Uri "$GraphRoot/sites/$($site['id'])/drives?`$select=id,name,webUrl")['value']
$wanted = $Library.Trim('/')
$drive = $drives | Where-Object {
    $_['name'] -eq $wanted -or
    ([Uri]::UnescapeDataString($_['webUrl'])).TrimEnd('/').EndsWith("/$wanted", [StringComparison]::OrdinalIgnoreCase) -or
    ($wanted -eq 'Shared Documents' -and $_['name'] -eq 'Documents')
} | Select-Object -First 1
if (-not $drive) {
    throw "Library '$Library' not found. Available libraries: $(($drives | ForEach-Object { $_['name'] }) -join ', ')"
}
Write-Host "Library: $($drive['name'])"

if ($RemoteFolder) {
    $rootItem = Invoke-Graph -Uri "$GraphRoot/drives/$($drive['id'])/root:/$(ConvertTo-GraphPath $RemoteFolder)"
}
else {
    $rootItem = Invoke-Graph -Uri "$GraphRoot/drives/$($drive['id'])/root"
}

#endregion

#region Compare

$LocalRoot = [IO.Path]::GetFullPath($LocalPath).TrimEnd('\', '/')
Write-Host "Local:   $LocalRoot"

$remoteFiles = Get-RemoteFiles -DriveId $drive['id'] -RootItemId $rootItem['id']
$localFiles = Get-LocalFiles -Root $LocalRoot

$report = New-Object System.Collections.Generic.List[object]
foreach ($remote in $remoteFiles.Values) {
    $local = $null
    if ($localFiles.ContainsKey($remote.Path)) { $local = $localFiles[$remote.Path] }

    if (-not $local) {
        $status = 'New'
    }
    else {
        $delta = ($remote.Modified - $local.Modified).TotalSeconds
        if ($delta -gt $TimeToleranceSeconds) { $status = 'Changed' }
        elseif ($delta -lt -$TimeToleranceSeconds) { $status = 'LocalNewer' }
        else { $status = 'Same' }
    }

    $report.Add([pscustomobject]@{
        Status         = $status
        Path           = $remote.Path
        RemoteModified = $remote.Modified
        LocalModified  = if ($local) { $local.Modified } else { $null }
        RemoteSize     = $remote.Size
        LocalSize      = if ($local) { $local.Size } else { $null }
        Result         = ''
        Remote         = $remote
    })
}
foreach ($local in $localFiles.Values) {
    if (-not $remoteFiles.ContainsKey($local.Path)) {
        $report.Add([pscustomobject]@{
            Status         = 'LocalOnly'
            Path           = $local.Path
            RemoteModified = $null
            LocalModified  = $local.Modified
            RemoteSize     = $null
            LocalSize      = $local.Size
            Result         = ''
            Remote         = $null
        })
    }
}

Write-Host ''
Write-Host 'Summary:'
$report | Group-Object Status | Sort-Object Name | ForEach-Object { '  {0,-11} {1,6}' -f $_.Name, $_.Count } | Write-Host

$differences = @($report | Where-Object { $_.Status -ne 'Same' } | Sort-Object Status, Path)
if ($differences.Count -gt 0) {
    $differences | Format-Table Status, Path, RemoteModified, LocalModified -AutoSize | Out-String -Width 220 | Write-Host
}

#endregion

#region Download

$toDownload = @($report | Where-Object {
    $_.Status -eq 'New' -or $_.Status -eq 'Changed' -or ($OverwriteLocalChanges -and $_.Status -eq 'LocalNewer')
} | Sort-Object Path)

if ($DryRun) {
    Write-Host "Dry run: $($toDownload.Count) file(s) would be downloaded."
    foreach ($entry in $toDownload) { $entry.Result = 'WouldDownload' }
}
else {
    $index = 0
    $failed = 0
    foreach ($entry in $toDownload) {
        $index++
        $target = Join-Path $LocalRoot ($entry.Path -replace '/', [IO.Path]::DirectorySeparatorChar)
        Write-Host ("[{0}/{1}] {2} {3}" -f $index, $toDownload.Count, $entry.Status, $entry.Path)
        try {
            Save-RemoteFile -DriveId $drive['id'] -Remote $entry.Remote -Target $target
            $entry.Result = 'Downloaded'
        }
        catch {
            $failed++
            $entry.Result = "Failed: $($_.Exception.Message)"
            Write-Warning "  failed: $($_.Exception.Message)"
        }
    }
    Write-Host "Downloaded $($toDownload.Count - $failed) file(s), $failed failed."
}

if (-not (Test-Path -LiteralPath $LocalRoot)) { New-Item -ItemType Directory -Path $LocalRoot -Force | Out-Null }
$reportPath = Join-Path $LocalRoot $ReportName
$report | Sort-Object Status, Path |
    Select-Object Status, Path, RemoteModified, LocalModified, RemoteSize, LocalSize, Result |
    Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding UTF8
Write-Host "Report:  $reportPath"

#endregion
