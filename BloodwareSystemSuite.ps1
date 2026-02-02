#Requires -Version 5.1

$Host.UI.RawUI.WindowTitle = "VaporWareXE Lite v3.0"
if ($Host.UI.RawUI.BackgroundColor -ne $null) {
    $Host.UI.RawUI.BackgroundColor = "Black"
    $Host.UI.RawUI.ForegroundColor = "White"
}
Clear-Host

Write-Host ""
Write-Host "  VaporWareXE Lite v3.0" -ForegroundColor White
Write-Host ""
Write-Host "  NOTE: This is uncompleted, do not expect a lot." -ForegroundColor Yellow
Write-Host "  Preferred as administrator but non-admin is fine." -ForegroundColor Yellow
Write-Host "  Suggested to use PowerShell Version 5.1 or 7" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Press any key to continue..."
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
Clear-Host

# ------------------------
# RESOURCES & MENU DATA
# ------------------------

$script:Resources = @{
    "System Management" = @{
        "Bloodware Suite" = @{
            "Start Bloodware Suite" = "StartBloodware"
        }
    }
    # ... other categories remain the same, trimmed here for brevity ...
}

$script:UpcomingResources = @{
    "Krynet.ai (Coming 2030)" = "https://krynet.ai"
    "KrySearch (Under development at the moment)" = "https://krysearch.com"
}

# ------------------------
# BLOODWARE FUNCTIONS
# ------------------------

function Initialize-SystemCache { Write-Host "Initializing system cache..." -ForegroundColor Green; Start-Sleep 1 }
function Get-FirmwareType { Write-Host "Detecting firmware type..." -ForegroundColor Green; Start-Sleep 1; return "UEFI" }
function Enable-PrivacySuite { Write-Host "Enabling Privacy Suite..." -ForegroundColor Green; Start-Sleep 1 }
function Invoke-AllOptimizations { Write-Host "Running all optimizations..." -ForegroundColor Green; Start-Sleep 1 }

function StartBloodware {
    Clear-Host
    Write-Host "=== Starting Bloodware System Suite ===" -ForegroundColor Cyan
    Initialize-SystemCache
    Get-FirmwareType
    Enable-PrivacySuite
    Invoke-AllOptimizations
    Write-Host "=== Bloodware Suite Complete ===" -ForegroundColor Cyan
    Write-Host "Press any key to return to menu..."
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

# ------------------------
# MENU FUNCTIONS
# ------------------------

function Show-MainMenu {
    Clear-Host
    Write-Host ""
    Write-Host "  ███ VaporWareXE Lite v3.0 ███" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Pick a category:" -ForegroundColor White
    Write-Host ""
    
    $index = 1
    $script:CategoryMap = @{}
    
    foreach ($category in $script:Resources.Keys | Sort-Object) {
        $script:CategoryMap[$index] = $category
        Write-Host "    [$index] $category" -ForegroundColor Gray
        $index++
    }
    
    Write-Host ""
    Write-Host "    [U] Upcoming Resources" -ForegroundColor White
    Write-Host "    [S] System Information" -ForegroundColor White
    Write-Host "    [H] Help & Information" -ForegroundColor White
    Write-Host "    [Q] Quit" -ForegroundColor White
    Write-Host ""
}

function Show-CategoryMenu {
    param([string]$CategoryName)
    
    Clear-Host
    Write-Host ""
    Write-Host "  Category: $CategoryName" -ForegroundColor White
    Write-Host ""
    
    $category = $script:Resources[$CategoryName]
    $index = 1
    $script:SubCategoryMap = @{}
    
    foreach ($subCategoryName in $category.Keys | Sort-Object) {
        $script:SubCategoryMap[$index] = $subCategoryName
        Write-Host "    [$index] $subCategoryName" -ForegroundColor Gray
        $index++
    }
    
    Write-Host ""
    Write-Host "    [B] Back to Main Menu" -ForegroundColor White
    Write-Host ""
}

function Show-SubCategoryMenu {
    param([string]$CategoryName,[string]$SubCategoryName)
    
    Clear-Host
    Write-Host ""
    Write-Host "  $CategoryName > $SubCategoryName" -ForegroundColor White
    Write-Host ""
    
    $resources = $script:Resources[$CategoryName][$SubCategoryName]
    $index = 1
    $script:ResourceMap = @{}
    
    foreach ($name in $resources.Keys | Sort-Object) {
        $script:ResourceMap[$index] = @{
            Name = $name
            URL = $resources[$name]
        }
        Write-Host "    [$index] $name" -ForegroundColor Gray
        $index++
    }
    
    Write-Host ""
    Write-Host "    [B] Back to Category Menu" -ForegroundColor White
    Write-Host ""
}

function Start-SubCategoryBrowser {
    param([string]$CategoryName, [string]$SubCategoryName)
    
    while ($true) {
        Show-SubCategoryMenu -CategoryName $CategoryName -SubCategoryName $SubCategoryName
        $choice = Read-Host "  Select option"
        
        if ($choice -match '^\d+$') {
            $num = [int]$choice
            if ($script:ResourceMap.ContainsKey($num)) {
                $resource = $script:ResourceMap[$num]
                # If it's a function, call it
                if (Get-Command $resource.URL -ErrorAction SilentlyContinue) {
                    & $resource.URL
                }
                else {
                    Write-Host "No URL or function available." -ForegroundColor Red
                }
            }
            else { Write-Host "  Invalid selection" -ForegroundColor Red; Start-Sleep 1 }
        }
        elseif ($choice -eq 'B' -or $choice -eq 'b') { break }
        else { Write-Host "  Invalid option" -ForegroundColor Red; Start-Sleep 1 }
    }
}

function Start-CategoryBrowser {
    param([string]$CategoryName)
    
    while ($true) {
        Show-CategoryMenu -CategoryName $CategoryName
        $choice = Read-Host "  Select option"
        
        if ($choice -match '^\d+$') {
            $num = [int]$choice
            if ($script:SubCategoryMap.ContainsKey($num)) {
                Start-SubCategoryBrowser -CategoryName $CategoryName -SubCategoryName $script:SubCategoryMap[$num]
            }
            else { Write-Host "  Invalid selection" -ForegroundColor Red; Start-Sleep 1 }
        }
        elseif ($choice -eq 'B' -or $choice -eq 'b') { break }
        else { Write-Host "  Invalid option" -ForegroundColor Red; Start-Sleep 1 }
    }
}

# ------------------------
# MAIN LOOP
# ------------------------

while ($true) {
    Show-MainMenu
    $choice = Read-Host "  Select option"
    
    if ($choice -match '^\d+$') {
        $num = [int]$choice
        if ($script:CategoryMap.ContainsKey($num)) {
            Start-CategoryBrowser -CategoryName $script:CategoryMap[$num]
        }
        else { Write-Host "  Invalid selection" -ForegroundColor Red; Start-Sleep 1 }
    }
    elseif ($choice -eq 'U' -or $choice -eq 'u') { Start-UpcomingBrowser }
    elseif ($choice -eq 'S' -or $choice -eq 's') { Show-SystemInfo }
    elseif ($choice -eq 'H' -or $choice -eq 'h') { Show-Help }
    elseif ($choice -eq 'Q' -or $choice -eq 'q') { Write-Host "Closing..."; break }
    else { Write-Host "  Invalid option" -ForegroundColor Red; Start-Sleep 1 }
}
