param(
    [string]$ConfigPath = ""
)

# Élévation admin immédiate
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $cmd = if ($ConfigPath) { "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" `"$ConfigPath`"" } else { "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" }
    Start-Process powershell -ArgumentList $cmd -Verb RunAs
    exit
}

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null

# --- Demande interactive du chemin ---
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Read-Host "Chemin du fichier AdGuardHome.yaml"
}
if ($ConfigPath) { $ConfigPath = $ConfigPath.Trim('"', "'") }
while ([string]::IsNullOrWhiteSpace($ConfigPath) -or -not (Test-Path $ConfigPath)) {
    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        Write-Host "[-] Fichier introuvable : $ConfigPath" -ForegroundColor Red
    }
    $ConfigPath = (Read-Host "Chemin du fichier AdGuardHome.yaml").Trim('"', "'")
}

$raw = Get-Content $ConfigPath -Raw

# --- Extraction des valeurs actuelles ---
$currentName = ""
$currentHash = ""
if ($raw -match '(?m)^\s+- name:\s*(.+)$') { $currentName = $Matches[1] }
if ($raw -match '(?m)^\s+password:\s*"(.+)"') { $currentHash = $Matches[1] }

Write-Host ""
Write-Host "=== Modification Identifiant / Mot de passe ===" -ForegroundColor Magenta
Write-Host "Fichier : $ConfigPath" -ForegroundColor Cyan
if ($currentName) { Write-Host "Utilisateur actuel : $currentName" -ForegroundColor Gray }
Write-Host ""

# --- Saisie des nouvelles valeurs (vide = inchangé) ---
$newUser = Read-Host "Nouvel identifiant (vide = inchangé)"
if ([string]::IsNullOrWhiteSpace($newUser)) { $newUser = $currentName }

$newPass = Read-Host "Nouveau mot de passe (vide = inchangé)"
$passwordChanged = -not [string]::IsNullOrWhiteSpace($newPass)

# --- Hash si mot de passe modifié ---
if ($passwordChanged) {
    Write-Host ""
    Write-Host "[*] Génération du hash BCrypt..." -ForegroundColor Green
    try {
        $tmp = Join-Path $env:TEMP "BCrypt.Net-Next"
        $zip = "$tmp.zip"
        Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package/BCrypt.Net-Next/4.2.0" -OutFile $zip -UseBasicParsing
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        Remove-Item $zip -Force
        $dll = Get-ChildItem -LiteralPath "$tmp\lib\net462" -Filter "BCrypt-Net-Next.dll" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        if (-not $dll) { $dll = Get-ChildItem -LiteralPath "$tmp\lib\net48" -Filter "BCrypt-Net-Next.dll" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName }
        if (-not $dll) { throw "DLL introuvable" }
        $bytes = [System.IO.File]::ReadAllBytes($dll)
        Remove-Item $tmp -Recurse -Force
        [System.Reflection.Assembly]::Load($bytes) | Out-Null
        $newHash = [BCrypt.Net.BCrypt]::HashPassword($newPass, 10)
    } catch {
        Write-Host "[-] Erreur BCrypt : $_" -ForegroundColor Red
        exit 1
    }
} else {
    $newHash = $currentHash
}

# --- Construction du bloc utilisateur ---
$userBlock = @"
users:
  - name: $newUser
    password: "$newHash"
"@

# --- Remplacement dans le YAML ---
$updated = $raw -replace "(?m)^users:.*(?:\r?\n\s+.*)*", $userBlock

if ($updated -eq $raw) {
    Write-Host "[-] Aucune modification détectée (section users non trouvée)" -ForegroundColor Red
    exit 1
}

[IO.File]::WriteAllText($ConfigPath, $updated, [System.Text.Encoding]::UTF8)

Write-Host ""
Write-Host "[+] Fichier mis à jour :" -ForegroundColor Green
Write-Host "    Utilisateur : $newUser" -ForegroundColor Yellow
if ($passwordChanged) {
    Write-Host "    Mot de passe : $newPass" -ForegroundColor Yellow
} else {
    Write-Host "    Mot de passe : inchangé" -ForegroundColor Gray
}
Write-Host ""
$aghExe = Join-Path (Split-Path $ConfigPath -Parent) "AdGuardHome.exe"
Write-Host "[*] Redémarrage d'AdGuardHome..." -ForegroundColor Cyan
& $aghExe -s restart
Write-Host "[+] Redémarrage effectué" -ForegroundColor Green
Read-Host "Appuyez sur Entrée pour quitter..."
