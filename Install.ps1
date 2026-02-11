# Bloodware System Suite – Installer / Launcher
# Run as Administrator

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Base = "https://raw.githubusercontent.com/Bloodware-Inc/BloodwareSystemSuite/refs/heads/main"

$Scripts = @(
    "Windows.ps1",
    "Edge.ps1"
)

foreach ($s in $Scripts) {
    Write-Host "[Bloodware] Loading $s..." -ForegroundColor Cyan
    irm "$Base/$s" | iex
}
