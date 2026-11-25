#requires -Version 5.1
<#
.SYNOPSIS
Install a pinned Microsoft ConPTY x64 pair beside Alacritty or WezTerm.
.DESCRIPTION
Close the target terminal first. Existing files are backed up before replacement.
The script changes only conpty.dll and OpenConsole.exe in the specified directory.
Without SourceDirectory it downloads the official, hash-pinned NuGet package.
SourceDirectory must contain the exact signed pair from that package.
.EXAMPLE
.\install-conpty.ps1 -AppDir 'C:\Programs\Alacritty' -SourceDirectory 'C:\Downloads\conpty-x64'
.EXAMPLE
.\install-conpty.ps1 -AppDir 'C:\Programs\WezTerm'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $AppDir,

    [string] $SourceDirectory
)

$ErrorActionPreference = 'Stop'
$packageVersion = '1.25.261109001'
$packageUrl = 'https://api.nuget.org/v3-flatcontainer/microsoft.windows.console.conpty/1.25.261109001/microsoft.windows.console.conpty.1.25.261109001.nupkg'
$packageHash = '3D77F535DF848E44225C2A8912AC844FECB23F3057732B639F3034B587496F09'
$pairHashes = [ordered]@{
    'conpty.dll' = 'E971856F89748DC3B458125E9AFDD79B5E9574A7C937676116D3CBBD3B71F492'
    'OpenConsole.exe' = 'B17E48B07EF153B420F0A6E178BACD31FB4C3390E21AE746586213FC0719A775'
}

function Get-PeMachine([string] $Path) {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $reader = New-Object IO.BinaryReader($stream)
    try {
        if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5A4D) { throw "Not a PE file: $Path" }
        $stream.Position = 60
        $offset = $reader.ReadInt32()
        if ($offset -lt 64 -or $offset -gt ($stream.Length - 6)) { throw "Invalid PE header: $Path" }
        $stream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x00004550) { throw "Invalid PE signature: $Path" }
        return $reader.ReadUInt16()
    }
    finally { $reader.Dispose() }
}

function Assert-PairFile([string] $Path, [string] $Hash) {
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing file: $Path" }
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Hash) { throw "SHA256 mismatch: $Path" }
    if ((Get-PeMachine $Path) -ne 0x8664) { throw "Expected an x64 PE file: $Path" }
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid' -or !$signature.SignerCertificate -or
        $signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false) -ne 'Microsoft Corporation') {
        throw "Expected a valid Microsoft Authenticode signature: $Path ($($signature.Status))"
    }
}

if (!(Test-Path -LiteralPath $AppDir -PathType Container)) { throw "AppDir must be an existing directory: $AppDir" }
$appDirectory = (Resolve-Path -LiteralPath $AppDir).ProviderPath
$appNames = @('alacritty.exe', 'wezterm-gui.exe', 'wezterm.exe')
$appExecutables = @($appNames | ForEach-Object { Join-Path $appDirectory $_ } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
if (!$appExecutables.Count) { throw 'AppDir must contain alacritty.exe, wezterm-gui.exe, or wezterm.exe.' }
foreach ($appExecutable in $appExecutables) {
    if ((Get-PeMachine $appExecutable) -ne 0x8664) { throw "Only x64 applications are supported: $appExecutable" }
}

$alreadyInstalled = $true
foreach ($name in $pairHashes.Keys) {
    $target = Join-Path $appDirectory $name
    if (!(Test-Path -LiteralPath $target -PathType Leaf) -or (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $pairHashes[$name]) {
        $alreadyInstalled = $false
        break
    }
}
if ($alreadyInstalled) {
    foreach ($name in $pairHashes.Keys) { Assert-PairFile (Join-Path $appDirectory $name) $pairHashes[$name] }
    Write-Output "Already installed: Microsoft ConPTY $packageVersion x64 in $appDirectory"
    return
}

$stage = Join-Path ([IO.Path]::GetTempPath()) ('terminal-conpty-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage | Out-Null
$packagePath = Join-Path $stage 'conpty.nupkg'
try {
    if ($SourceDirectory) {
        if (!(Test-Path -LiteralPath $SourceDirectory -PathType Container)) { throw "SourceDirectory must exist: $SourceDirectory" }
        foreach ($name in $pairHashes.Keys) { Copy-Item -LiteralPath (Join-Path $SourceDirectory $name) -Destination (Join-Path $stage $name) }
    }
    else {
        $previousTls = [Net.ServicePointManager]::SecurityProtocol
        try {
            [Net.ServicePointManager]::SecurityProtocol = $previousTls -bor [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $packageUrl -OutFile $packagePath -UseBasicParsing
        }
        finally { [Net.ServicePointManager]::SecurityProtocol = $previousTls }
        if ((Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash -ne $packageHash) { throw 'NuGet package SHA256 mismatch.' }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($packagePath)
        try {
            $entries = @{
                'conpty.dll' = 'runtimes/win-x64/native/conpty.dll'
                'OpenConsole.exe' = 'build/native/runtimes/x64/OpenConsole.exe'
            }
            foreach ($name in $pairHashes.Keys) {
                $entry = $archive.GetEntry($entries[$name])
                if (!$entry) { throw "Missing x64 package entry: $name" }
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $stage $name))
            }
        }
        finally { $archive.Dispose() }
    }
    foreach ($name in $pairHashes.Keys) { Assert-PairFile (Join-Path $stage $name) $pairHashes[$name] }

    # Do not replace a pair used by a running terminal or its console host.
    foreach ($process in @(Get-Process -Name alacritty, wezterm-gui, wezterm, OpenConsole -ErrorAction SilentlyContinue)) {
        $processPath = $process.Path
        if (!$processPath) { throw "Cannot inspect running $($process.ProcessName). Close it before installing." }
        if ([IO.Path]::GetDirectoryName($processPath).TrimEnd('\') -eq $appDirectory.TrimEnd('\')) {
            throw "Close the target application first: $processPath (PID $($process.Id))"
        }
    }
    $existingNames = @($pairHashes.Keys | Where-Object { Test-Path -LiteralPath (Join-Path $appDirectory $_) })
    foreach ($name in $existingNames) {
        $probe = [IO.File]::Open((Join-Path $appDirectory $name), [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $probe.Dispose()
    }

    $backup = $null
    if ($existingNames.Count) {
        $backup = Join-Path $appDirectory ('conpty-backup-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $backup | Out-Null
        foreach ($name in $existingNames) { Copy-Item -LiteralPath (Join-Path $appDirectory $name) -Destination (Join-Path $backup $name) }
    }

    $attempted = @()
    try {
        foreach ($name in $pairHashes.Keys) {
            $attempted += $name
            Copy-Item -LiteralPath (Join-Path $stage $name) -Destination (Join-Path $appDirectory $name) -Force
        }
        foreach ($name in $pairHashes.Keys) {
            if ((Get-FileHash -LiteralPath (Join-Path $appDirectory $name) -Algorithm SHA256).Hash -ne $pairHashes[$name]) { throw "Installed file SHA256 mismatch: $name" }
        }
    }
    catch {
        $installError = $_.Exception.Message
        $rollbackErrors = @()
        foreach ($name in $attempted) {
            try {
                if ($existingNames -contains $name) { Copy-Item -LiteralPath (Join-Path $backup $name) -Destination (Join-Path $appDirectory $name) -Force }
                elseif (Test-Path -LiteralPath (Join-Path $appDirectory $name)) { Remove-Item -LiteralPath (Join-Path $appDirectory $name) -Force }
            }
            catch { $rollbackErrors += $_.Exception.Message }
        }
        if ($rollbackErrors.Count) { throw "Install failed: $installError. Restore from '$backup'. Rollback errors: $($rollbackErrors -join '; ')" }
        throw "Install failed; previous files restored: $installError"
    }
    Write-Output "Installed Microsoft ConPTY $packageVersion x64 in $appDirectory"
    if ($backup) { Write-Output "Backup: $backup" }
}
finally {
    try {
        # .NET also handles short (8.3) TEMP paths correctly in Windows PowerShell 5.1.
        foreach ($name in @('conpty.nupkg', 'conpty.dll', 'OpenConsole.exe')) {
            [IO.File]::Delete((Join-Path $stage $name))
        }
        [IO.Directory]::Delete($stage)
    }
    catch { Write-Warning "Could not remove temporary directory '$stage': $($_.Exception.Message)" }
}
