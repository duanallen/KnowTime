$path = 'C:\Users\19173\.hvigor\project_caches'
$item = Get-Item $path -Force
Write-Host "Path: $path"
Write-Host "Attributes: $($item.Attributes)"
Write-Host "LinkType: $($item.LinkType)"
Write-Host "Target: $($item.Target)"

# Check if it's a reparse point
$attrs = $item.Attributes
Write-Host "IsReparsePoint: $($attrs -band [System.IO.FileAttributes]::ReparsePoint)"

# Check subdirectory
$subPath = 'C:\Users\19173\.hvigor\project_caches\3469d67c80712db8c21e591235db270f'
$subItem = Get-Item $subPath -Force
Write-Host "`nSubPath: $subPath"
Write-Host "Attributes: $($subItem.Attributes)"
Write-Host "LinkType: $($subItem.LinkType)"
Write-Host "Target: $($subItem.Target)"

# Try creating with .NET directly
Write-Host "`nTrying .NET Directory.CreateDirectory:"
try {
    [System.IO.Directory]::CreateDirectory('C:\Users\19173\.hvigor\project_caches\3469d67c80712db8c21e591235db270f\workspace2') | Out-Null
    Write-Host ".NET CreateDirectory SUCCESS"
    Remove-Item 'C:\Users\19173\.hvigor\project_caches\3469d67c80712db8c21e591235db270f\workspace2' -Force
} catch {
    Write-Host ".NET CreateDirectory FAILED: $($_.Exception.Message)"
}