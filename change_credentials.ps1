param(
    [string]$ConfigPath = ""
)

# Admin elevation
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $cmd = if ($ConfigPath) { "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" `"$ConfigPath`"" } else { "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" }
    Start-Process powershell -ArgumentList $cmd -Verb RunAs
    exit
}

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null

function Generate-BCryptHash {
    param([string]$PlainPassword)
    $tmp = Join-Path $env:TEMP "BCrypt.Net-Next"
    $zip = "$tmp.zip"
    Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package/BCrypt.Net-Next/4.2.0" -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    Remove-Item $zip -Force
    $dll = Get-ChildItem -LiteralPath "$tmp\lib\net462" -Filter "BCrypt-Net-Next.dll" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    if (-not $dll) { $dll = Get-ChildItem -LiteralPath "$tmp\lib\net48" -Filter "BCrypt-Net-Next.dll" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName }
    if (-not $dll) { throw "DLL not found" }
    $bytes = [System.IO.File]::ReadAllBytes($dll)
    Remove-Item $tmp -Recurse -Force
    [System.Reflection.Assembly]::Load($bytes) | Out-Null
    return [BCrypt.Net.BCrypt]::HashPassword($PlainPassword, 10)
}

do {
    [System.Console]::Clear()
    Clear-Host

    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "    AdGuardHome Credentials Tool          " -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [1] Change Username/Password in YAML" -ForegroundColor Green
    Write-Host "  [2] Generate BCrypt hash from password" -ForegroundColor Yellow
    Write-Host "  [3] Exit" -ForegroundColor Red
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan

    $Choice = Read-Host "Select an option (1-3)"

    if ($Choice -eq "3" -or [string]::IsNullOrWhiteSpace($Choice)) {
        Write-Host "[-] Exiting..." -ForegroundColor Yellow
        break
    }

    # --------------------------------------------------------------------------
    # OPTION 1 : CHANGE USERNAME / PASSWORD IN YAML
    # --------------------------------------------------------------------------
    if ($Choice -eq "1") {
        Clear-Host
        Write-Host "=== Change Username / Password ===" -ForegroundColor Magenta
        Write-Host ""

        # Path input
        if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
            $inputPath = Read-Host "Path to AdGuardHome.yaml"
        } else {
            $inputPath = $ConfigPath
        }
        if ($inputPath) { $inputPath = $inputPath.Trim('"', "'") }
        while ([string]::IsNullOrWhiteSpace($inputPath) -or -not (Test-Path $inputPath)) {
            if (-not [string]::IsNullOrWhiteSpace($inputPath)) {
                Write-Host "[-] File not found : $inputPath" -ForegroundColor Red
            }
            $inputPath = (Read-Host "Path to AdGuardHome.yaml").Trim('"', "'")
        }

        $raw = Get-Content $inputPath -Raw

        # Extract current username
        $currentName = ""
        if ($raw -match '(?m)^\s+- name:\s*(.+)$') { $currentName = $Matches[1] }

        Write-Host ""
        Write-Host "File : $inputPath" -ForegroundColor Cyan
        if ($currentName) { Write-Host "Current username : $currentName" -ForegroundColor Gray }
        Write-Host ""

        $newUser = Read-Host "New username (empty = unchanged)"
        if ([string]::IsNullOrWhiteSpace($newUser)) { $newUser = $currentName }

        $newPass = Read-Host "New password (empty = unchanged)"
        $passwordChanged = -not [string]::IsNullOrWhiteSpace($newPass)

        if ($passwordChanged) {
            Write-Host ""
            Write-Host "[*] Generating BCrypt hash..." -ForegroundColor Green
            try {
                $newHash = Generate-BCryptHash -PlainPassword $newPass
            } catch {
                Write-Host "[-] BCrypt error : $_" -ForegroundColor Red
                Read-Host "Press Enter to return to menu..."
                continue
            }

            # Replace entire users block
            $userBlock = @"
users:
  - name: $newUser
    password: "$newHash"
"@
            $updated = $raw -replace "(?m)^users:.*(?:\r?\n\s+.*)*", $userBlock
        } else {
            # Password unchanged → only touch the - name: line
            $updated = $raw -replace "(?m)^(\s+- name:).*$", "`$1 $newUser"
        }

        if ($updated -eq $raw) {
            Write-Host "[-] No changes detected (users section not found)" -ForegroundColor Red
            Read-Host "Press Enter to return to menu..."
            continue
        }

        [IO.File]::WriteAllText($inputPath, $updated, [System.Text.Encoding]::UTF8)

        Write-Host ""
        Write-Host "[+] File updated :" -ForegroundColor Green
        Write-Host "    Username : $newUser" -ForegroundColor Yellow
        if ($passwordChanged) {
            Write-Host "    Password : $newPass" -ForegroundColor Yellow
        } else {
            Write-Host "    Password : unchanged" -ForegroundColor Gray
        }
        Write-Host ""

        $aghExe = Join-Path (Split-Path $inputPath -Parent) "AdGuardHome.exe"
        Write-Host "[*] Restarting AdGuardHome..." -ForegroundColor Cyan
        & $aghExe -s restart
        Write-Host "[+] Restart done" -ForegroundColor Green
        Read-Host "Press Enter to return to menu..."
    }

    # --------------------------------------------------------------------------
    # OPTION 2 : GENERATE BCRYPT HASH
    # --------------------------------------------------------------------------
    if ($Choice -eq "2") {
        Clear-Host
        Write-Host "=== Generate BCrypt Hash ===" -ForegroundColor Yellow
        Write-Host ""

        $plainPass = Read-Host "Enter password to hash"
        if ([string]::IsNullOrWhiteSpace($plainPass)) {
            Write-Host "[-] Password cannot be empty." -ForegroundColor Red
            Read-Host "Press Enter to return to menu..."
            continue
        }

        Write-Host "[*] Generating BCrypt hash..." -ForegroundColor Green
        try {
            $hash = Generate-BCryptHash -PlainPassword $plainPass
        } catch {
            Write-Host "[-] BCrypt error : $_" -ForegroundColor Red
            Read-Host "Press Enter to return to menu..."
            continue
        }

        Write-Host ""
        Write-Host "[+] Hash : $hash" -ForegroundColor Green
        Write-Host ""
        Write-Host "Add this to your YAML:" -ForegroundColor Cyan
        Write-Host "  password: ""$hash""" -ForegroundColor White
        Write-Host ""
        Read-Host "Press Enter to return to menu..."
    }

} while ($true)
