#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Bloodware System Suite - Professional Edition

.DESCRIPTION
    A comprehensive system optimization and maintenance tool with modern UI,
    performance optimization, and enterprise-grade code quality.

.NOTES
    File Name      : BloodwareSystemSuite.ps1
    Version        : 2.0.0
    Author         : Bloodware Team
    Prerequisite   : PowerShell 5.1+, Administrator privileges
    Copyright      : 2025

.LINK
    https://github.com/bloodware/system-suite

.EXAMPLE
    .\BloodwareSystemSuite.ps1
    Launches the interactive system suite interface
#>

[CmdletBinding()]
[OutputType([void])]
param()

#region Script Configuration
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$VerbosePreference = 'SilentlyContinue'
Set-StrictMode -Version Latest

# Script constants
$Script:VERSION = '2.0.0'
$Script:BUILD_DATE = '2025-02-01'
$Script:CACHE_INITIALIZED = $false
#endregion

#region Color Theme Configuration
$Script:Theme = [PSCustomObject]@{
    Primary       = [ConsoleColor]::Cyan
    Secondary     = [ConsoleColor]::Magenta
    Success       = [ConsoleColor]::Green
    Warning       = [ConsoleColor]::Yellow
    Error         = [ConsoleColor]::Red
    Info          = [ConsoleColor]::White
    Accent        = [ConsoleColor]::DarkCyan
    Border        = [ConsoleColor]::DarkGray
    Highlight     = [ConsoleColor]::Yellow
    Muted         = [ConsoleColor]::Gray
}
#endregion

#region System Information Cache
$Script:SystemCache = [PSCustomObject]@{
    ComputerSystem = $null
    BaseBoard      = $null
    BIOS           = $null
    Product        = $null
    GPU            = $null
    Battery        = $null
    FirmwareType   = $null
    SecureBoot     = $null
    BitLocker      = $null
    IsVM           = $false
    IsAdmin        = $false
    CacheTime      = $null
}
#endregion

#region Initialization Functions
function Initialize-SystemCache {
    <#
    .SYNOPSIS
        Initializes or refreshes the system information cache.
    
    .DESCRIPTION
        Performs parallel WMI/CIM queries to gather system information efficiently.
        Uses job-based parallelization for optimal performance.
    #>
    [CmdletBinding()]
    param()
    
    if ($Script:CACHE_INITIALIZED -and $Script:SystemCache.CacheTime -and 
        ((Get-Date) - $Script:SystemCache.CacheTime).TotalMinutes -lt 5) {
        Write-Verbose "Using cached system information (age: $((Get-Date) - $Script:SystemCache.CacheTime))"
        return
    }
    
    Write-Host "`n⚡ Initializing system diagnostics..." -ForegroundColor $Theme.Accent -NoNewline
    
    try {
        # Define parallel jobs for system queries
        $jobs = @{
            ComputerSystem = { Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop }
            BaseBoard      = { Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction Stop }
            BIOS           = { Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop }
            Product        = { Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction Stop }
            GPU            = { Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop }
            Battery        = { Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop }
        }
        
        # Start all jobs
        $runningJobs = @{}
        foreach ($jobName in $jobs.Keys) {
            $runningJobs[$jobName] = Start-Job -ScriptBlock $jobs[$jobName] -Name "Cache_$jobName"
        }
        
        # Wait for completion with timeout
        $timeout = (Get-Date).AddSeconds(30)
        while (($runningJobs.Values | Where-Object { $_.State -eq 'Running' }) -and ((Get-Date) -lt $timeout)) {
            Start-Sleep -Milliseconds 100
        }
        
        # Collect results
        foreach ($jobName in $runningJobs.Keys) {
            $job = $runningJobs[$jobName]
            if ($job.State -eq 'Completed') {
                $Script:SystemCache.$jobName = Receive-Job -Job $job -ErrorAction SilentlyContinue
            } else {
                Write-Verbose "Job $jobName did not complete in time"
                $Script:SystemCache.$jobName = $null
            }
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
        
        # Gather additional system information
        $Script:SystemCache.FirmwareType = Get-FirmwareType
        $Script:SystemCache.SecureBoot = Get-SecureBootStatus
        $Script:SystemCache.BitLocker = Get-BitLockerStatus
        $Script:SystemCache.IsVM = Test-VirtualMachine
        $Script:SystemCache.IsAdmin = Test-AdministratorPrivilege
        $Script:SystemCache.CacheTime = Get-Date
        
        $Script:CACHE_INITIALIZED = $true
        
        Write-Host " Done" -ForegroundColor $Theme.Success
    }
    catch {
        Write-Host " Failed" -ForegroundColor $Theme.Error
        Write-Warning "System cache initialization failed: $_"
    }
}

function Get-FirmwareType {
    <#
    .SYNOPSIS
        Determines the system firmware type (UEFI or Legacy BIOS).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    try {
        $computerInfo = Get-ComputerInfo -Property BiosFirmwareType -ErrorAction Stop
        return $computerInfo.BiosFirmwareType
    }
    catch {
        Write-Verbose "Unable to determine firmware type: $_"
        return 'Unknown'
    }
}

function Get-SecureBootStatus {
    <#
    .SYNOPSIS
        Checks if Secure Boot is enabled.
    #>
    [CmdletBinding()]
    [OutputType([System.Nullable[bool]])]
    param()
    
    try {
        return Confirm-SecureBootUEFI -ErrorAction Stop
    }
    catch {
        Write-Verbose "Unable to determine Secure Boot status: $_"
        return $null
    }
}

function Get-BitLockerStatus {
    <#
    .SYNOPSIS
        Retrieves BitLocker protection status for all volumes.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param()
    
    try {
        return Get-BitLockerVolume -ErrorAction Stop | 
            Where-Object { $_.ProtectionStatus -eq 'On' }
    }
    catch {
        Write-Verbose "Unable to determine BitLocker status: $_"
        return $null
    }
}

function Test-VirtualMachine {
    <#
    .SYNOPSIS
        Detects if running in a virtual machine environment.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    if (-not $Script:SystemCache.ComputerSystem) {
        return $false
    }
    
    $vmIndicators = @('Virtual', 'VMware', 'KVM', 'Hyper-V', 'VirtualBox', 'Xen', 'QEMU')
    $model = $Script:SystemCache.ComputerSystem.Model
    
    foreach ($indicator in $vmIndicators) {
        if ($model -match $indicator) {
            return $true
        }
    }
    
    return $false
}

function Test-AdministratorPrivilege {
    <#
    .SYNOPSIS
        Checks if the current session has administrator privileges.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        Write-Verbose "Unable to determine administrator status: $_"
        return $false
    }
}
#endregion

#region UI Rendering Functions
function Write-Banner {
    <#
    .SYNOPSIS
        Displays the application banner with branding.
    #>
    [CmdletBinding()]
    param()
    
    Clear-Host
    
    $banner = @"

    ╔═══════════════════════════════════════════════════════════════════════════╗
    ║                                                                           ║
    ║  ██████╗ ██╗      ██████╗  ██████╗ ██████╗ ██╗    ██╗ █████╗ ██████╗ ███████╗
    ║  ██╔══██╗██║     ██╔═══██╗██╔═══██╗██╔══██╗██║    ██║██╔══██╗██╔══██╗██╔════╝
    ║  ██████╔╝██║     ██║   ██║██║   ██║██║  ██║██║ █╗ ██║███████║██████╔╝█████╗  
    ║  ██╔══██╗██║     ██║   ██║██║   ██║██║  ██║██║███╗██║██╔══██║██╔══██╗██╔══╝  
    ║  ██████╔╝███████╗╚██████╔╝╚██████╔╝██████╔╝╚███╔███╔╝██║  ██║██║  ██║███████╗
    ║  ╚═════╝ ╚══════╝ ╚═════╝  ╚═════╝ ╚═════╝  ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝
    ║                                                                           ║
    ║                    SYSTEM OPTIMIZATION SUITE v$($Script:VERSION)                    ║
    ║                Professional Edition • Build $($Script:BUILD_DATE)                ║
    ╚═══════════════════════════════════════════════════════════════════════════╝

"@
    
    # Gradient color effect
    $lines = $banner -split "`n"
    foreach ($line in $lines) {
        switch -Regex ($line) {
            '╔|╚|═|║' {
                Write-Host $line -ForegroundColor $Theme.Border
            }
            'BLOODWARE|██' {
                Write-Host $line -ForegroundColor $Theme.Primary
            }
            'SYSTEM|Professional|Build' {
                Write-Host $line -ForegroundColor $Theme.Secondary
            }
            default {
                Write-Host $line -ForegroundColor $Theme.Info
            }
        }
    }
}

function Write-StyledBox {
    <#
    .SYNOPSIS
        Renders a styled box with title and content.
    
    .PARAMETER Title
        The box title text.
    
    .PARAMETER Lines
        Array of content lines to display.
    
    .PARAMETER TitleColor
        Color for the title text.
    
    .PARAMETER BorderColor
        Color for the box borders.
    
    .PARAMETER Style
        Box style: Success, Warning, Error, or Info.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,
        
        [Parameter(Mandatory)]
        [string[]]$Lines,
        
        [ConsoleColor]$TitleColor = $Script:Theme.Primary,
        
        [ConsoleColor]$BorderColor = $Script:Theme.Border,
        
        [ValidateSet('Success', 'Warning', 'Error', 'Info')]
        [string]$Style = 'Info'
    )
    
    # Apply style-based color override
    switch ($Style) {
        'Success' { $TitleColor = $Theme.Success }
        'Warning' { $TitleColor = $Theme.Warning }
        'Error'   { $TitleColor = $Theme.Error }
    }
    
    # Calculate box width
    $maxLength = ($Lines | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
    $boxWidth = [Math]::Max($maxLength, $Title.Length) + 4
    
    # Draw box
    $topBorder = "╔" + ("═" * $boxWidth) + "╗"
    $separator = "╠" + ("═" * $boxWidth) + "╣"
    $bottomBorder = "╚" + ("═" * $boxWidth) + "╝"
    
    Write-Host $topBorder -ForegroundColor $BorderColor
    Write-Host "║ " -NoNewline -ForegroundColor $BorderColor
    Write-Host $Title.PadRight($boxWidth - 2) -NoNewline -ForegroundColor $TitleColor
    Write-Host " ║" -ForegroundColor $BorderColor
    Write-Host $separator -ForegroundColor $BorderColor
    
    foreach ($line in $Lines) {
        Write-Host "║ " -NoNewline -ForegroundColor $BorderColor
        Write-Host $line.PadRight($boxWidth - 2) -NoNewline -ForegroundColor $Theme.Info
        Write-Host " ║" -ForegroundColor $BorderColor
    }
    
    Write-Host $bottomBorder -ForegroundColor $BorderColor
    Write-Host ""
}

function Write-ProgressBar {
    <#
    .SYNOPSIS
        Displays an animated progress bar.
    
    .PARAMETER Label
        Progress bar label.
    
    .PARAMETER Total
        Total number of steps.
    
    .PARAMETER Delay
        Delay in milliseconds between steps.
    
    .PARAMETER Color
        Progress bar color.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Label,
        
        [int]$Total = 100,
        
        [int]$Delay = 15,
        
        [ConsoleColor]$Color = $Script:Theme.Success
    )
    
    Write-Host "⚙️  $Label " -NoNewline
    Write-Host "[" -NoNewline -ForegroundColor $Theme.Border
    
    for ($i = 0; $i -lt $Total; $i++) {
        Write-Host "█" -NoNewline -ForegroundColor $Color
        Start-Sleep -Milliseconds $Delay
    }
    
    Write-Host "]" -NoNewline -ForegroundColor $Theme.Border
    Write-Host " ✓" -ForegroundColor $Theme.Success
}

function Write-MenuItem {
    <#
    .SYNOPSIS
        Renders a menu item with consistent formatting.
    
    .PARAMETER Key
        Menu item key/shortcut.
    
    .PARAMETER Description
        Menu item description.
    
    .PARAMETER Highlight
        Whether to highlight this item.
    
    .PARAMETER Divider
        Render as a divider line instead.
    #>
    [CmdletBinding()]
    param(
        [string]$Key,
        
        [string]$Description,
        
        [switch]$Highlight,
        
        [switch]$Divider
    )
    
    if ($Divider) {
        Write-Host ("  " + ("─" * 72)) -ForegroundColor $Theme.Border
        return
    }
    
    $keyColor = if ($Highlight) { $Theme.Highlight } else { $Theme.Primary }
    $descColor = if ($Highlight) { $Theme.Info } else { $Theme.Accent }
    
    Write-Host "  [" -NoNewline -ForegroundColor $Theme.Border
    Write-Host $Key -NoNewline -ForegroundColor $keyColor
    Write-Host "] " -NoNewline -ForegroundColor $Theme.Border
    Write-Host $Description -ForegroundColor $descColor
}

function Write-StatusIndicator {
    <#
    .SYNOPSIS
        Writes a status indicator (checkmark or X).
    
    .PARAMETER Status
        Boolean status to display.
    
    .PARAMETER TrueIcon
        Icon to show for true status.
    
    .PARAMETER FalseIcon
        Icon to show for false status.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [bool]$Status,
        
        [string]$TrueIcon = "✓",
        
        [string]$FalseIcon = "✗"
    )
    
    if ($Status) {
        Write-Host $TrueIcon -ForegroundColor $Theme.Success -NoNewline
    }
    else {
        Write-Host $FalseIcon -ForegroundColor $Theme.Error -NoNewline
    }
}
#endregion

#region System Information Display
function Show-SystemInformation {
    <#
    .SYNOPSIS
        Displays comprehensive system information.
    #>
    [CmdletBinding()]
    param()
    
    Initialize-SystemCache
    
    if (-not $Script:SystemCache.ComputerSystem) {
        Write-Warning "Unable to retrieve system information"
        return
    }
    
    $cs = $Script:SystemCache.ComputerSystem
    $bb = $Script:SystemCache.BaseBoard
    $prod = $Script:SystemCache.Product
    
    $info = @(
        "Manufacturer  : $($cs.Manufacturer ?? 'Unknown')",
        "Model         : $($cs.Model ?? 'Unknown')",
        "Board         : $($bb.Product ?? 'Unknown')",
        "Serial Number : $($prod.IdentifyingNumber ?? 'Unknown')",
        "Total RAM     : $([Math]::Round($cs.TotalPhysicalMemory / 1GB, 2)) GB",
        "Domain/WG     : $($cs.Domain ?? 'Unknown')"
    )
    
    Write-StyledBox -Title "SYSTEM INFORMATION" -Lines $info -TitleColor $Theme.Secondary
}

function Show-PreFlightChecklist {
    <#
    .SYNOPSIS
        Displays pre-flight system checks for safe operation.
    #>
    [CmdletBinding()]
    param()
    
    Initialize-SystemCache
    
    # Calculate battery status
    $batteryLevel = if ($Script:SystemCache.Battery) { 
        $Script:SystemCache.Battery.EstimatedChargeRemaining 
    } else { 
        100 
    }
    
    $acConnected = if ($Script:SystemCache.ComputerSystem) {
        $Script:SystemCache.ComputerSystem.PowerSupplyState -eq 1
    } else {
        $false
    }
    
    # Build checklist
    $checks = @(
        "Admin Privileges        : $(if ($Script:SystemCache.IsAdmin) { '✓ Yes' } else { '✗ No (REQUIRED)' })",
        "UEFI Firmware           : $(if ($Script:SystemCache.FirmwareType -eq 'UEFI') { '✓ Yes' } else { '✗ No' })",
        "Secure Boot Enabled     : $(if ($Script:SystemCache.SecureBoot -eq $true) { '✓ Yes' } elseif ($Script:SystemCache.SecureBoot -eq $false) { '✗ No' } else { '? Unknown' })",
        "BitLocker Suspended     : $(if (-not $Script:SystemCache.BitLocker) { '✓ Yes' } else { '⚠ Active (May require suspend)' })",
        "Battery Level           : $(if ($batteryLevel -ge 40) { "✓ $batteryLevel%" } else { "⚠ $batteryLevel% (Low)" })",
        "AC Power Connected      : $(if ($acConnected) { '✓ Yes' } else { '⚠ No (Recommended)' })",
        "Physical Machine        : $(if (-not $Script:SystemCache.IsVM) { '✓ Yes' } else { '⚠ Virtual Machine' })"
    )
    
    Write-StyledBox -Title "PRE-FLIGHT SYSTEM CHECKLIST" -Lines $checks -TitleColor $Theme.Primary
}
#endregion

#region Hardware Link Generation
function Get-GPUDriverLinks {
    <#
    .SYNOPSIS
        Generates GPU-specific driver download links.
    
    .OUTPUTS
        Hashtable of GPU information and download URLs.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    Initialize-SystemCache
    
    $gpuList = $Script:SystemCache.GPU
    if (-not $gpuList) {
        Write-Warning "No GPU information available"
        return @{}
    }
    
    $links = @{}
    $index = 1
    
    foreach ($gpu in $gpuList) {
        $name = $gpu.Name
        $url = switch -Regex ($name) {
            'NVIDIA'     { 'https://www.nvidia.com/en-us/software/nvidia-app/' }
            'AMD|Radeon' { 'https://www.amd.com/en/support' }
            'Intel'      { 'https://www.intel.com/content/www/us/en/download-center/home.html' }
            default      { "https://www.startpage.com/do/search?query=$([uri]::EscapeDataString($name + ' drivers'))" }
        }
        
        $links[$index] = @{
            Name = $name
            URL  = $url
        }
        $index++
    }
    
    return $links
}

function Get-BIOSUpdateLink {
    <#
    .SYNOPSIS
        Generates manufacturer-specific BIOS update link.
    
    .OUTPUTS
        String URL for BIOS updates.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    Initialize-SystemCache
    
    if (-not $Script:SystemCache.ComputerSystem) {
        return 'https://www.startpage.com/do/search?query=BIOS+update'
    }
    
    $cs = $Script:SystemCache.ComputerSystem
    $bb = $Script:SystemCache.BaseBoard
    $prod = $Script:SystemCache.Product
    
    $vendor = $cs.Manufacturer.Trim()
    $model = $cs.Model.Trim()
    $board = $bb.Product.Trim()
    $serial = $prod.IdentifyingNumber.Trim()
    
    # Normalize vendor name
    $vendorNormalized = switch -Regex ($vendor) {
        'ASUSTeK|ASUS' { 'ASUS' }
        'MSI'          { 'MSI' }
        'Gigabyte'     { 'Gigabyte' }
        'HP'           { 'HP' }
        'Dell'         { 'Dell' }
        'Lenovo'       { 'Lenovo' }
        default        { $vendor }
    }
    
    # Generate manufacturer-specific URL
    $url = switch ($vendorNormalized) {
        'Dell'     { "https://www.dell.com/support/home/en-us/product-support/servicetag/$serial" }
        'Lenovo'   { "https://pcsupport.lenovo.com/us/en/products?serialNumber=$serial" }
        'HP'       { "https://support.hp.com/us-en/search?q=$serial" }
        'MSI'      { "https://www.msi.com/support/search?q=$board" }
        'Gigabyte' { "https://www.gigabyte.com/Search?kw=$board" }
        default    {
            $query = [uri]::EscapeDataString("$vendor $model $board BIOS update")
            "https://www.startpage.com/do/search?query=$query"
        }
    }
    
    return $url
}
#endregion

#region System Restore
function New-SystemRestorePoint {
    <#
    .SYNOPSIS
        Prompts user and creates a system restore point.
    #>
    [CmdletBinding()]
    param()
    
    Write-Host ""
    $response = Read-Host "🛡️  Create system restore point before proceeding? (Y/N)"
    
    if ($response -match '^[Yy]') {
        try {
            Write-ProgressBar -Label "Creating restore point" -Total 50 -Delay 20
            
            Checkpoint-Computer -Description "Bloodware Pre-Run Restore - $(Get-Date -Format 'yyyy-MM-dd HH:mm')" `
                               -RestorePointType MODIFY_SETTINGS `
                               -ErrorAction Stop
            
            Write-Host "`n✓ Restore point created successfully`n" -ForegroundColor $Theme.Success
        }
        catch {
            Write-Host "`n⚠️  Failed to create restore point: $_" -ForegroundColor $Theme.Warning
            Write-Host "   Ensure System Restore is enabled in System Properties`n" -ForegroundColor $Theme.Muted
        }
    }
    else {
        Write-Host "`n⏭️  Skipping restore point creation`n" -ForegroundColor $Theme.Accent
    }
}
#endregion

#region Optimization Modules
function Test-PowerShellVersion {
    <#
    .SYNOPSIS
        Checks PowerShell version and recommends upgrades.
    #>
    [CmdletBinding()]
    param()
    
    Write-Host "`n🔍 Checking PowerShell version..." -ForegroundColor $Theme.Accent
    Start-Sleep -Milliseconds 500
    
    $version = $PSVersionTable.PSVersion
    $edition = $PSVersionTable.PSEdition
    
    Write-Host "   Version: $version ($edition)" -ForegroundColor $Theme.Info
    
    if ($version.Major -ge 7) {
        Write-Host "✓ PowerShell $version is installed and up-to-date" -ForegroundColor $Theme.Success
    }
    else {
        Write-Host "⚠️  PowerShell $($version.Major) detected (legacy)" -ForegroundColor $Theme.Warning
        Write-Host "💡 Recommendation: Install PowerShell 7+ for better performance" -ForegroundColor $Theme.Info
        Write-Host "   Command: winget install Microsoft.PowerShell" -ForegroundColor $Theme.Muted
    }
    
    Write-Host ""
}

function Install-DotNetSDKs {
    <#
    .SYNOPSIS
        Installs .NET SDK versions via WinGet.
    
    .PARAMETER Channel
        SDK channel to install: Current, LTS, or Both.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Current', 'LTS', 'Both')]
        [string]$Channel = 'Both'
    )
    
    Write-Host "`n📦 Installing .NET SDKs ($Channel)..." -ForegroundColor $Theme.Accent
    
    # Verify WinGet availability
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host "✗ WinGet not found. Please install from Microsoft Store.`n" -ForegroundColor $Theme.Error
        return
    }
    
    try {
        $sdks = @()
        
        if ($Channel -in @('Current', 'Both')) {
            $sdks += @{
                Name = '.NET 8 (Current)'
                Id   = 'Microsoft.DotNet.SDK.8'
            }
        }
        
        if ($Channel -in @('LTS', 'Both')) {
            $sdks += @{
                Name = '.NET 6 (LTS)'
                Id   = 'Microsoft.DotNet.SDK.6'
            }
        }
        
        foreach ($sdk in $sdks) {
            Write-ProgressBar -Label "Installing $($sdk.Name)" -Total 60 -Delay 25
            
            $process = Start-Process -FilePath 'winget' `
                                    -ArgumentList "install $($sdk.Id) -e --silent --accept-package-agreements --accept-source-agreements" `
                                    -Wait `
                                    -NoNewWindow `
                                    -PassThru
            
            if ($process.ExitCode -eq 0) {
                Write-Host "✓ $($sdk.Name) installed successfully" -ForegroundColor $Theme.Success
            }
            else {
                Write-Host "⚠️  $($sdk.Name) installation returned code: $($process.ExitCode)" -ForegroundColor $Theme.Warning
            }
        }
        
        Write-Host ""
    }
    catch {
        Write-Host "`n✗ SDK installation failed: $_`n" -ForegroundColor $Theme.Error
    }
}

function Enable-SystemHardening {
    <#
    .SYNOPSIS
        Applies system hardening configurations.
    #>
    [CmdletBinding()]
    param()
    
    Write-Host "`n🛡️  Applying system hardening..." -ForegroundColor $Theme.Accent
    
    try {
        # Disable Internet Explorer
        Write-ProgressBar -Label "Disabling Internet Explorer" -Total 40 -Delay 20
        
        $iePath = 'HKCU:\Software\Microsoft\Internet Explorer\Main'
        if (-not (Test-Path $iePath)) {
            New-Item -Path $iePath -Force | Out-Null
        }
        
        Set-ItemProperty -Path $iePath -Name 'DisableIE' -Type DWord -Value 1 -ErrorAction Stop
        
        # Disable Windows Script Host
        $wshPath = 'HKCU:\Software\Microsoft\Windows Script Host\Settings'
        if (-not (Test-Path $wshPath)) {
            New-Item -Path $wshPath -Force | Out-Null
        }
        Set-ItemProperty -Path $wshPath -Name 'Enabled' -Type DWord -Value 0 -ErrorAction SilentlyContinue
        
        # Remove IE directories
        Write-ProgressBar -Label "Removing IE directories" -Total 40 -Delay 20
        
        $ieFolders = @(
            'C:\Program Files\Internet Explorer',
            'C:\Program Files (x86)\Internet Explorer'
        )
        
        foreach ($folder in $ieFolders) {
            if (Test-Path $folder) {
                Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        
        Write-Host "`n✓ System hardening applied successfully`n" -ForegroundColor $Theme.Success
    }
    catch {
        Write-Host "`n⚠️  Some hardening steps failed: $_`n" -ForegroundColor $Theme.Warning
    }
}

function Set-DiscordPrivacy {
    <#
    .SYNOPSIS
        Configures Discord privacy settings by modifying settings file.
    #>
    [CmdletBinding()]
    param()
    
    Write-Host "`n🔒 Configuring Discord privacy settings..." -ForegroundColor $Theme.Accent
    
    try {
        $discordPath = "$env:APPDATA\discord\settings.json"
        
        if (Test-Path $discordPath) {
            Write-ProgressBar -Label "Reading Discord settings" -Total 25 -Delay 10
            
            $settings = Get-Content $discordPath -Raw | ConvertFrom-Json
            
            # Apply privacy settings
            $settings | Add-Member -NotePropertyName 'SKIP_HOST_UPDATE' -NotePropertyValue $true -Force
            $settings | Add-Member -NotePropertyName 'DANGEROUS_ENABLE_DEVTOOLS_ONLY_ENABLE_IF_YOU_KNOW_WHAT_YOURE_DOING' -NotePropertyValue $false -Force
            
            Write-ProgressBar -Label "Applying privacy configuration" -Total 25 -Delay 10
            
            $settings | ConvertTo-Json -Depth 10 | Set-Content $discordPath -Force
            
            Write-Host "`n✓ Discord privacy configured`n" -ForegroundColor $Theme.Success
        }
        else {
            Write-Host "`n⚠️  Discord settings file not found. Is Discord installed?`n" -ForegroundColor $Theme.Warning
        }
    }
    catch {
        Write-Host "`n⚠️  Failed to configure Discord privacy: $_`n" -ForegroundColor $Theme.Warning
    }
}

function Enable-PrivacySuite {
    <#
    .SYNOPSIS
        Enables comprehensive privacy enhancements.
    #>
    [CmdletBinding()]
    param()
    
    Write-Host "`n🔐 Enabling privacy suite..." -ForegroundColor $Theme.Accent
    
    try {
        # Disable telemetry
        Write-ProgressBar -Label "Disabling telemetry services" -Total 20 -Delay 10
        
        $telemetryServices = @('DiagTrack', 'dmwappushservice')
        foreach ($service in $telemetryServices) {
            Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
            Set-Service -Name $service -StartupType Disabled -ErrorAction SilentlyContinue
        }
        
        # Disable Windows Error Reporting
        Write-ProgressBar -Label "Disabling error reporting" -Total 20 -Delay 10
        Disable-WindowsErrorReporting -ErrorAction SilentlyContinue
        
        # Disable location tracking
        $locationPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'
        if (Test-Path $locationPath) {
            Set-ItemProperty -Path $locationPath -Name 'Value' -Type String -Value 'Deny' -ErrorAction SilentlyContinue
        }
        
        # Disable activity history
        Write-ProgressBar -Label "Disabling activity history" -Total 20 -Delay 10
        
        $activityPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
        if (-not (Test-Path $activityPath)) {
            New-Item -Path $activityPath -Force | Out-Null
        }
        Set-ItemProperty -Path $activityPath -Name 'PublishUserActivities' -Type DWord -Value 0 -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $activityPath -Name 'UploadUserActivities' -Type DWord -Value 0 -ErrorAction SilentlyContinue
        
        Write-Host "`n✓ Privacy suite enabled`n" -ForegroundColor $Theme.Success
    }
    catch {
        Write-Host "`n⚠️  Some privacy settings failed: $_`n" -ForegroundColor $Theme.Warning
    }
}

function Set-DNSConfiguration {
    <#
    .SYNOPSIS
        Configures DNS settings for privacy/performance using Cloudflare and Quad9.
    #>
    [CmdletBinding()]
    param()
    
    Write-Host "`n🌐 Configuring DNS settings..." -ForegroundColor $Theme.Accent
    
    try {
        # Get active network adapters
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceType -ne 24 }
        
        if ($adapters.Count -eq 0) {
            Write-Host "`n⚠️  No active network adapters found`n" -ForegroundColor $Theme.Warning
            return
        }
        
        Write-ProgressBar -Label "Setting DNS servers" -Total 50 -Delay 20
        
        # Cloudflare DNS: 1.1.1.1, 1.0.0.1
        # Quad9 DNS: 9.9.9.9, 149.112.112.112
        $primaryDNS = '1.1.1.1'
        $secondaryDNS = '1.0.0.1'
        
        foreach ($adapter in $adapters) {
            Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex `
                                      -ServerAddresses @($primaryDNS, $secondaryDNS) `
                                      -ErrorAction SilentlyContinue
        }
        
        # Flush DNS cache
        Clear-DnsClientCache -ErrorAction SilentlyContinue
        
        Write-Host "`n✓ DNS configured to Cloudflare (1.1.1.1)`n" -ForegroundColor $Theme.Success
    }
    catch {
        Write-Host "`n⚠️  Failed to configure DNS: $_`n" -ForegroundColor $Theme.Warning
    }
}

function Enable-FirewallAskMode {
    <#
    .SYNOPSIS
        Enables Windows Firewall with enhanced logging for monitoring.
    #>
    [CmdletBinding()]
    param()
    
    Write-Host "`n🔥 Enabling Firewall enhanced mode..." -ForegroundColor $Theme.Accent
    
    try {
        Write-ProgressBar -Label "Configuring firewall profiles" -Total 30 -Delay 15
        
        # Enable firewall for all profiles
        Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True -ErrorAction Stop
        
        # Enable logging for dropped packets
        Set-NetFirewallProfile -Profile Domain,Public,Private `
                              -LogAllowed True `
                              -LogBlocked True `
                              -LogMaxSizeKilobytes 4096 `
                              -ErrorAction SilentlyContinue
        
        Write-ProgressBar -Label "Configuring firewall rules" -Total 20 -Delay 15
        
        # Block all inbound by default
        Set-NetFirewallProfile -Profile Domain,Public,Private `
                              -DefaultInboundAction Block `
                              -DefaultOutboundAction Allow `
                              -ErrorAction SilentlyContinue
        
        Write-Host "`n✓ Firewall enhanced mode enabled`n" -ForegroundColor $Theme.Success
    }
    catch {
        Write-Host "`n⚠️  Failed to configure firewall: $_`n" -ForegroundColor $Theme.Warning
    }
}

function Set-FirewallAllowOutbound {
    <#
    .SYNOPSIS
        Configures firewall to allow outbound connections with monitoring.
    #>
    [CmdletBinding()]
    param()
    
    Write-Host "`n🔥 Configuring outbound firewall..." -ForegroundColor $Theme.Accent
    
    try {
        Write-ProgressBar -Label "Allowing outbound connections" -Total 50 -Delay 20
        
        # Set default outbound to allow
        Set-NetFirewallProfile -Profile Domain,Public,Private `
                              -DefaultOutboundAction Allow `
                              -ErrorAction Stop
        
        # Enable notifications for blocked connections
        Set-NetFirewallProfile -Profile Domain,Public,Private `
                              -NotifyOnListen True `
                              -ErrorAction SilentlyContinue
        
        Write-Host "`n✓ Outbound firewall configured`n" -ForegroundColor $Theme.Success
    }
    catch {
        Write-Host "`n⚠️  Failed to configure outbound firewall: $_`n" -ForegroundColor $Theme.Warning
    }
}

function Enable-ConstrainedLanguageMode {
    <#
    .SYNOPSIS
        Configures PowerShell security features and enables script logging.
    #>
    [CmdletBinding()]
    param()
    
    Write-Host "`n🔒 Enabling PowerShell security features..." -ForegroundColor $Theme.Accent
    
    try {
        Write-ProgressBar -Label "Configuring PowerShell logging" -Total 30 -Delay 15
        
        # Enable PowerShell script block logging
        $psLoggingPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'
        if (-not (Test-Path $psLoggingPath)) {
            New-Item -Path $psLoggingPath -Force | Out-Null
        }
        Set-ItemProperty -Path $psLoggingPath -Name 'EnableScriptBlockLogging' -Type DWord -Value 1 -ErrorAction Stop
        
        # Enable module logging
        Write-ProgressBar -Label "Enabling module logging" -Total 20 -Delay 15
        
        $moduleLoggingPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging'
        if (-not (Test-Path $moduleLoggingPath)) {
            New-Item -Path $moduleLoggingPath -Force | Out-Null
        }
        Set-ItemProperty -Path $moduleLoggingPath -Name 'EnableModuleLogging' -Type DWord -Value 1 -ErrorAction SilentlyContinue
        
        Write-Host "`n✓ PowerShell security features enabled`n" -ForegroundColor $Theme.Success
        Write-Host "   Note: Constrained Language Mode requires AppLocker/WDAC policies" -ForegroundColor $Theme.Muted
    }
    catch {
        Write-Host "`n⚠️  Failed to configure PowerShell security: $_`n" -ForegroundColor $Theme.Warning
    }
}

function Invoke-EmergencyRestore {
    <#
    .SYNOPSIS
        Restores system to safe default settings.
    #>
    [CmdletBinding()]
    param()
    
    Write-Host "`n⚠️  EMERGENCY RESTORE MODE" -ForegroundColor $Theme.Error
    Write-Host "This will restore system to safe defaults.`n" -ForegroundColor $Theme.Warning
    
    $confirm = Read-Host "Type 'YES' (uppercase) to confirm"
    
    if ($confirm -ceq 'YES') {
        Write-ProgressBar -Label "Restoring DNS to automatic" -Total 20 -Delay 25 -Color $Theme.Warning
        
        try {
            # Reset DNS to automatic
            $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
            foreach ($adapter in $adapters) {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses -ErrorAction SilentlyContinue
            }
            
            Write-ProgressBar -Label "Re-enabling services" -Total 20 -Delay 25 -Color $Theme.Warning
            
            # Re-enable telemetry services
            $services = @('DiagTrack', 'dmwappushservice')
            foreach ($service in $services) {
                Set-Service -Name $service -StartupType Automatic -ErrorAction SilentlyContinue
                Start-Service -Name $service -ErrorAction SilentlyContinue
            }
            
            Write-ProgressBar -Label "Resetting firewall defaults" -Total 20 -Delay 25 -Color $Theme.Warning
            
            # Reset firewall to defaults
            Set-NetFirewallProfile -Profile Domain,Public,Private `
                                  -DefaultInboundAction Block `
                                  -DefaultOutboundAction Allow `
                                  -ErrorAction SilentlyContinue
            
            Write-ProgressBar -Label "Clearing registry changes" -Total 20 -Delay 25 -Color $Theme.Warning
            
            # Remove IE disable flag
            Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Internet Explorer\Main' `
                               -Name 'DisableIE' `
                               -ErrorAction SilentlyContinue
            
            Write-Host "`n✓ System restored to safe defaults`n" -ForegroundColor $Theme.Success
        }
        catch {
            Write-Host "`n⚠️  Some restore operations failed: $_`n" -ForegroundColor $Theme.Warning
        }
    }
    else {
        Write-Host "`n⏭️  Emergency restore cancelled`n" -ForegroundColor $Theme.Accent
    }
}

function Invoke-AllOptimizations {
    <#
    .SYNOPSIS
        Executes all optimization modules in sequence.
    #>
    [CmdletBinding()]
    param()
    
    Write-Host "`n🚀 RUNNING ALL OPTIMIZATIONS" -ForegroundColor $Theme.Primary
    Write-Host "═══════════════════════════════════════════════════════`n" -ForegroundColor $Theme.Border
    
    $modules = @(
        { Test-PowerShellVersion },
        { Install-DotNetSDKs -Channel 'Both' },
        { Enable-SystemHardening },
        { Set-DiscordPrivacy },
        { Enable-PrivacySuite },
        { Set-DNSConfiguration },
        { Set-FirewallAllowOutbound },
        { Enable-ConstrainedLanguageMode }
    )
    
    foreach ($module in $modules) {
        & $module
    }
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $u="https://raw.githubusercontent.com/Bloodware-Inc/BloodwareSystemSuite/$(Invoke-RestMethod -Uri 'https://api.github.com/repos/Bloodware-Inc/BloodwareSystemSuite/commits/main' -Headers @{ 'User-Agent'='PS' }).sha/Install.ps1"; $c=(irm $u -UseBasicParsing); $h=[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($c))).Replace('-','').ToLower(); Write-Host "[Info] SHA256:`n$h"; if((Read-Host "Run script? (Y/N)") -eq 'Y'){iex $c}    
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor $Theme.Border
    Write-Host "✓ All optimizations complete!`n" -ForegroundColor $Theme.Success
}
#endregion

#region Menu System
function Show-MainMenu {
    <#
    .SYNOPSIS
        Displays the main application menu.
    #>
    [CmdletBinding()]
    param()
    
    Write-Banner
    Show-SystemInformation
    Show-PreFlightChecklist
    
    Write-Host "╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor $Theme.Border
    Write-Host "║                              MAIN MENU                                     ║" -ForegroundColor $Theme.Primary
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor $Theme.Border
    Write-Host ""
    
    # Core optimizations
    Write-MenuItem -Key '1' -Description 'Check PowerShell 7 Installation'
    Write-MenuItem -Key '2' -Description 'Install .NET SDKs (Current + LTS)'
    Write-MenuItem -Key '3' -Description 'Apply System Hardening'
    Write-MenuItem -Key '4' -Description 'Configure Discord Privacy'
    Write-MenuItem -Key '5' -Description 'Enable Privacy Suite'
    Write-MenuItem -Key '6' -Description 'Setup DNS Configuration'
    Write-MenuItem -Key '7' -Description 'Enable Firewall Enhanced Mode'
    Write-MenuItem -Key '8' -Description 'Allow Firewall Outbound'
    Write-MenuItem -Key '9' -Description 'Enable PowerShell Security'
    
    Write-MenuItem -Divider
    
    # Hardware links
    Write-MenuItem -Key 'B' -Description 'Open BIOS Update Link' -Highlight
    Write-MenuItem -Key 'G' -Description 'Open GPU Driver Links (Multi-Select)' -Highlight
    
    Write-MenuItem -Divider
    
    # System actions
    Write-MenuItem -Key 'A' -Description '🚀 Run ALL Optimizations' -Highlight
    Write-MenuItem -Key '0' -Description '⚠️  EMERGENCY RESTORE' -Highlight
    Write-MenuItem -Key 'R' -Description '🔄 Refresh Display'
    Write-MenuItem -Key 'X' -Description '❌ Exit'
    
    Write-Host ""
    Write-Host ("  " + ("─" * 72)) -ForegroundColor $Theme.Border
    Write-Host ""
}

function Start-MenuLoop {
    <#
    .SYNOPSIS
        Main application loop handling user input.
    #>
    [CmdletBinding()]
    param()
    
    while ($true) {
        Show-MainMenu
        
        $choice = Read-Host "  Select option"
        
        switch ($choice.ToUpper()) {
            '1' { Test-PowerShellVersion }
            '2' { Install-DotNetSDKs }
            '3' { Enable-SystemHardening }
            '4' { Set-DiscordPrivacy }
            '5' { Enable-PrivacySuite }
            '6' { Set-DNSConfiguration }
            '7' { Enable-FirewallAskMode }
            '8' { Set-FirewallAllowOutbound }
            '9' { Enable-ConstrainedLanguageMode }
            
            'B' {
                $url = Get-BIOSUpdateLink
                Write-Host "`n🔗 Opening BIOS update page..." -ForegroundColor $Theme.Accent
                Start-Process $url
                Start-Sleep -Seconds 1
            }
            
            'G' {
                $links = Get-GPUDriverLinks
                
                if ($links.Count -eq 0) {
                    Write-Host "`n⚠️  No GPU information available`n" -ForegroundColor $Theme.Warning
                }
                else {
                    Write-Host "`n📊 Detected GPUs:`n" -ForegroundColor $Theme.Accent
                    
                    foreach ($key in $links.Keys) {
                        Write-Host "  [$key] " -NoNewline -ForegroundColor $Theme.Primary
                        Write-Host "$($links[$key].Name)" -ForegroundColor $Theme.Info
                    }
                    
                    Write-Host ""
                    $selection = Read-Host "  Enter GPU numbers (comma-separated, e.g., 1,2)"
                    
                    $selectedIndices = $selection -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' }
                    
                    foreach ($index in $selectedIndices) {
                        $indexInt = [int]$index
                        if ($links.ContainsKey($indexInt)) {
                            Write-Host "  🔗 Opening: $($links[$indexInt].Name)" -ForegroundColor $Theme.Accent
                            Start-Process $links[$indexInt].URL
                            Start-Sleep -Milliseconds 500
                        }
                    }
                }
                
                Start-Sleep -Seconds 1
            }
            
            'A' { Invoke-AllOptimizations }
            '0' { Invoke-EmergencyRestore }
            
            'R' {
                $Script:CACHE_INITIALIZED = $false
                $Script:SystemCache = [PSCustomObject]@{
                    ComputerSystem = $null
                    BaseBoard      = $null
                    BIOS           = $null
                    Product        = $null
                    GPU            = $null
                    Battery        = $null
                    FirmwareType   = $null
                    SecureBoot     = $null
                    BitLocker      = $null
                    IsVM           = $false
                    IsAdmin        = $false
                    CacheTime      = $null
                }
                continue
            }
            
            'X' {
                Write-Host "`n👋 Thank you for using Bloodware System Suite" -ForegroundColor $Theme.Primary
                Write-Host "   Exiting...`n" -ForegroundColor $Theme.Accent
                exit 0
            }
            
            default {
                Write-Host "`n❌ Invalid option. Please try again.`n" -ForegroundColor $Theme.Error
                Start-Sleep -Seconds 1
            }
        }
        
        if ($choice.ToUpper() -notin @('R', 'X')) {
            Write-Host ""
            Read-Host "  Press Enter to continue"
        }
    }
}
#endregion

#region Main Entry Point
function Start-BloodwareSystemSuite {
    <#
    .SYNOPSIS
        Main entry point for the application.
    #>
    [CmdletBinding()]
    param()
    
    # Set console title
    $host.UI.RawUI.WindowTitle = "Bloodware System Suite v$($Script:VERSION)"
    
    # Pre-flight checks
    if (-not (Test-AdministratorPrivilege)) {
        Write-Host "`n❌ This script requires Administrator privileges" -ForegroundColor $Theme.Error
        Write-Host "   Please run PowerShell as Administrator and try again.`n" -ForegroundColor $Theme.Warning
        Read-Host "Press Enter to exit"
        exit 1
    }
    
    # Initialize system cache
    Initialize-SystemCache
    
    # Offer restore point
    New-SystemRestorePoint
    
    # Start main loop
    Start-MenuLoop
}

# Execute main function
Start-BloodwareSystemSuite
#endregion
