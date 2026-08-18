# Check current user context
$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host "Current user: $($identity.Name)"
Write-Host "Is Admin: $isAdmin"

# Check Windows Defender real-time protection
try {
    $mpStatus = Get-MpComputerStatus
    Write-Host "`nDefender RealTimeProtection: $($mpStatus.RealTimeProtectionEnabled)"
    Write-Host "Defender AntivirusEnabled: $($mpStatus.AntivirusEnabled)"
    Write-Host "Defender AntivirusRunning: $($mpStatus.AntivirusRunning)"
} catch {
    Write-Host "Cannot get Defender status: $($_.Exception.Message)"
}

# Check exclusions
try {
    $prefs = Get-MpPreference
    Write-Host "`nExclusion Paths:"
    foreach ($p in $prefs.ExclusionPath) { Write-Host "  $p" }
} catch {
    Write-Host "Cannot get exclusions"
}

# Check for other security software
Write-Host "`nSecurity-related processes:"
Get-Process | Where-Object { $_.ProcessName -match 'av|defender|kasper|norton|mcafee|avg|bitdef|trend|symantec|f-secure|sophos|360|huorong|zhudongfangyu' } | Select-Object Id, ProcessName