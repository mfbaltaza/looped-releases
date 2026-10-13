param([switch]$Uninstall)
$ErrorActionPreference = 'Stop'
$releaseTag = 'v0.1.3' # The release builder stamps this value.
$repo = 'mfbaltaza/looped-releases'
$base = if ($env:LOOPED_RELEASE_BASE) { $env:LOOPED_RELEASE_BASE.TrimEnd('/') } else { "https://github.com/$repo/releases" }
$dir = Join-Path $env:LOCALAPPDATA 'Looped'
$exe = Join-Path $dir 'looped.exe'
$start = Join-Path $dir 'start.ps1'
$data = Join-Path $dir 'data'
$config = Join-Path $dir 'settings.json'
$menuLink = Join-Path ([Environment]::GetFolderPath('Programs')) 'Looped.lnk'
$startupLink = Join-Path ([Environment]::GetFolderPath('Startup')) 'Looped.lnk'
$noStart = $env:LOOPED_NO_START -eq '1'
function Stop-Looped {
    # Windows keeps the binary locked until the process is gone, so wait for it.
    Get-Process looped -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe } | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        $_.WaitForExit(10000) | Out-Null
    }
}
if ($Uninstall) {
    Stop-Looped
    Remove-Item $start, $config, $menuLink, $startupLink -Force -ErrorAction SilentlyContinue
    foreach ($i in 1..25) {
        Remove-Item $exe -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $exe)) { break }
        Start-Sleep -Milliseconds 200
    }
    if (Test-Path $exe) { throw "Could not remove $exe. Close anything using it and run the uninstall again." }
    Write-Host "Looped removed. Recordings and credentials remain in $data"
    return
}
$port = if ($env:LOOPED_PORT) { $env:LOOPED_PORT } else { '4747' }
if (Test-Path $config) {
    $settings = Get-Content -Raw $config | ConvertFrom-Json
    $port = [string]$settings.port
    $data = [string]$settings.data
} elseif (Test-Path $start) {
    $previous = Get-Content -Raw $start
    if ($previous -match "LOOPED_ADDR\s*=\s*'127\.0\.0\.1:(\d+)'") { $port = $Matches[1] }
    if ($previous -match "LOOPED_DATA\s*=\s*'((?:''|[^'])*)'") { $data = $Matches[1].Replace("''", "'") }
}
if ($port -notmatch '^\d{1,5}$' -or [int]$port -lt 1 -or [int]$port -gt 65535) { throw 'LOOPED_PORT must be 1 through 65535.' }
if (-not [IO.Path]::IsPathRooted($data) -or $data -match '[\r\n]') { throw 'Use an absolute data path without newlines.' }
$url = "http://localhost:$port"
$passwordFile = Join-Path $data 'password'
$newPassword = $null
$wrotePassword = $false
function Read-LoopedPassword($prompt) {
    $secure = Read-Host $prompt -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr).Trim() } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}
if (-not ((Test-Path $passwordFile) -and (Get-Item $passwordFile).Length -gt 0)) {
    if ($env:LOOPED_PASSWORD) {
        if ($env:LOOPED_PASSWORD -match '[\r\n]') { throw 'LOOPED_PASSWORD must not contain a newline.' }
        $newPassword = $env:LOOPED_PASSWORD.Trim()
    } else {
        if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) { throw 'Looped needs a password. Set LOOPED_PASSWORD and rerun this command.' }
        while ($true) {
            $first = Read-LoopedPassword 'Choose a password for Looped'
            $second = Read-LoopedPassword 'Repeat it'
            if (-not $first) { Write-Host 'The password cannot be blank. Try again.' }
            elseif ($first -cne $second) { Write-Host 'The passwords do not match. Try again.' }
            else { $newPassword = $first; break }
        }
    }
    if (-not $newPassword) { throw 'LOOPED_PASSWORD must not be blank.' }
}
$processor = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
$arch = switch ($processor) { 'AMD64' { 'amd64' }; 'ARM64' { 'arm64' }; default { throw "Unsupported processor $processor." } }
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue) -or -not (Get-Command ffprobe -ErrorAction SilentlyContinue)) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw 'Install FFmpeg and ffprobe, add both to PATH, then rerun this command.' }
    if ($arch -eq 'arm64') { throw 'Install an ARM64-compatible FFmpeg and ffprobe and add both to PATH, then rerun this command.' }
    & winget install --exact --id Gyan.FFmpeg --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) { throw "FFmpeg installation failed with exit code $LASTEXITCODE." }
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}
foreach ($tool in @('ffmpeg', 'ffprobe')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool is missing. Add FFmpeg to PATH and open a new PowerShell window." }
}
if ($releaseTag.StartsWith('@')) {
    $releaseTag = $env:LOOPED_VERSION
    if (-not $releaseTag) {
        $response = Invoke-WebRequest -UseBasicParsing -Uri "$base/latest"
        $resolved = if ($response.BaseResponse.ResponseUri) { $response.BaseResponse.ResponseUri.AbsoluteUri } else { $response.BaseResponse.RequestMessage.RequestUri.AbsoluteUri }
        $releaseTag = $resolved.TrimEnd('/').Split('/')[-1]
    }
}
if ($releaseTag -notmatch '^v\d+\.\d+\.\d+([.-][A-Za-z0-9.-]+)?$') { throw 'Could not resolve a release. Set LOOPED_VERSION=vX.Y.Z.' }
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$stage = Join-Path $dir ('.install-' + [guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $stage | Out-Null
$asset = "looped-windows-$arch.exe"
$tmp = Join-Path $stage 'looped.exe'
$replacing = $false
$owned = @($exe, $start, $config, $menuLink, $startupLink)
$backup = @{}
try {
    Invoke-WebRequest -UseBasicParsing -Uri "$base/download/$releaseTag/$asset" -OutFile $tmp
    $manifestFile = Join-Path $stage 'SHA256SUMS'
    Invoke-WebRequest -UseBasicParsing -Uri "$base/download/$releaseTag/SHA256SUMS" -OutFile $manifestFile
    $manifest = Get-Content -Raw $manifestFile
    $entries = @($manifest -split "`n" | Where-Object { $_ -match ("^[a-fA-F0-9]{64}\s+" + [regex]::Escape($asset) + '\r?$') })
    if ($entries.Count -ne 1) { throw 'The checksum manifest must contain exactly one entry for this binary.' }
    $expected = ($entries[0] -split '\s+')[0]
    if ((Get-FileHash -Algorithm SHA256 $tmp).Hash -ne $expected) { throw 'Checksum mismatch. Existing installation was not changed.' }
    $identity = & $tmp --version
    if ($LASTEXITCODE -ne 0 -or $identity -ne $releaseTag) { throw 'The downloaded binary has the wrong version.' }
    if (-not $noStart) {
        $listeners = @(Get-NetTCPConnection -LocalPort ([int]$port) -State Listen -ErrorAction SilentlyContinue)
        foreach ($listener in $listeners) {
            $owner = Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue
            if (-not $owner -or $owner.Path -ne $exe) { throw "Port $port belongs to another app. Set LOOPED_PORT on your first install." }
        }
    }
    foreach ($file in $owned) {
        if (Test-Path $file) {
            $copy = Join-Path $stage ([guid]::NewGuid().ToString())
            Copy-Item $file $copy
            $backup[$file] = $copy
        }
    }
    New-Item -ItemType Directory -Force -Path $data | Out-Null
    # WriteAllText writes UTF-8 without a byte-order mark, which the server would read as part of the password.
    if ($newPassword) { [IO.File]::WriteAllText($passwordFile, $newPassword); $wrotePassword = $true }
    $replacing = $true
    Stop-Looped
    if (Test-Path $exe) { [IO.File]::Replace($tmp, $exe, (Join-Path $stage 'previous.exe')) } else { [IO.File]::Move($tmp, $exe) }
    @{ port = [int]$port; data = $data } | ConvertTo-Json | Set-Content -Encoding UTF8 $config
    $quotedData = $data.Replace("'", "''")
    $quotedExe = $exe.Replace("'", "''")
    $quotedPath = $env:Path.Replace("'", "''")
    $quotedOut = (Join-Path $data 'server.out.log').Replace("'", "''")
    $quotedErr = (Join-Path $data 'server.err.log').Replace("'", "''")
    @"
`$ErrorActionPreference = 'Stop'
`$env:Path = '$quotedPath' + ';' + [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
`$env:LOOPED_ADDR = '127.0.0.1:$port'
`$env:LOOPED_DATA = '$quotedData'
`$env:LOOPED_STORAGE = 'local'
foreach (`$name in @('LOOPED_PASSWORD', 'LOOPED_S3_ENDPOINT', 'LOOPED_S3_BUCKET', 'LOOPED_S3_ACCESS_KEY', 'LOOPED_S3_SECRET_KEY', 'LOOPED_S3_REGION')) { [Environment]::SetEnvironmentVariable(`$name, `$null, 'Process') }
if (-not (Get-Process looped -ErrorAction SilentlyContinue | Where-Object { `$_.Path -eq '$quotedExe' })) { Start-Process -WindowStyle Hidden -FilePath '$quotedExe' -RedirectStandardOutput '$quotedOut' -RedirectStandardError '$quotedErr' }
"@ | Set-Content -Encoding UTF8 $start
    if (-not $noStart) {
        $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $shell = New-Object -ComObject WScript.Shell
        $link = $shell.CreateShortcut($startupLink)
        $link.TargetPath = $powershell
        $link.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$start`""
        $link.WindowStyle = 7
        $link.Save()
        $link = $shell.CreateShortcut($menuLink)
        $link.TargetPath = Join-Path $env:SystemRoot 'explorer.exe'
        $link.Arguments = $url
        $link.Description = 'Record your screen locally'
        $link.Save()
        & $powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $start
        $ready = $false
        $why = 'the process did not start'
        # Windows tries IPv6 first for localhost and waits seconds on a closed port, so probe the bound address.
        $probe = "http://127.0.0.1:$port/api/me"
        foreach ($i in 1..50) {
            $process = @(Get-Process looped -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe })
            if ($process.Count -gt 0) {
                try {
                    Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 $probe | Out-Null
                    $listeners = @(Get-NetTCPConnection -LocalPort ([int]$port) -State Listen -ErrorAction SilentlyContinue)
                    if ($listeners.Count -gt 0 -and @($listeners | Where-Object { $_.OwningProcess -notin $process.Id }).Count -eq 0) { $ready = $true; break }
                    $why = "port $port is not owned by Looped alone"
                } catch { $why = "no answer from ${probe}: $($_.Exception.Message)" }
            }
            Start-Sleep -Milliseconds 200
        }
        if (-not $ready) { throw "Startup failed: $why. Read $(Join-Path $data 'server.err.log'). The previous installation will be restored." }
    }
    $replacing = $false
    Write-Host "Looped $releaseTag installed. Open $url"
    Write-Host "Recordings: $data"
    if ($wrotePassword) { Write-Host 'Sign in with the password you chose.' }
    if (-not $noStart) { Start-Process $url }
} catch {
    if ($replacing) {
        Stop-Looped
        foreach ($file in $owned) {
            if ($backup.ContainsKey($file)) { Copy-Item -Force $backup[$file] $file } else { Remove-Item -Force $file -ErrorAction SilentlyContinue }
        }
        if (-not $noStart -and (Test-Path $start)) { & $powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $start }
        Write-Warning 'Previous installation restored.'
    }
    if ($wrotePassword) { Remove-Item -Force $passwordFile -ErrorAction SilentlyContinue }
    throw
} finally { Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue }
