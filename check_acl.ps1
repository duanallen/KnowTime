$path = 'C:\Users\19173\.hvigor\project_caches\3469d67c80712db8c21e591235db270f'
$acl = Get-Acl $path
Write-Host "Owner: $($acl.Owner)"
Write-Host "Access rules:"
foreach ($rule in $acl.Access) {
    Write-Host "  $($rule.IdentityReference): $($rule.FileSystemRights) ($($rule.AccessControlType))"
}

# Check parent
$parentPath = 'C:\Users\19173\.hvigor\project_caches'
$parentAcl = Get-Acl $parentPath
Write-Host "`nParent Owner: $($parentAcl.Owner)"
Write-Host "Parent Access rules:"
foreach ($rule in $parentAcl.Access) {
    Write-Host "  $($rule.IdentityReference): $($rule.FileSystemRights) ($($rule.AccessControlType))"
}

# Try with New-Item
Write-Host "`nTrying New-Item on problem dir:"
try {
    $result = New-Item -Path "$path\test_newitem" -ItemType Directory -ErrorAction Stop
    Write-Host "New-Item SUCCESS: $($result.FullName)"
    Remove-Item $result.FullName -Force
} catch {
    Write-Host "New-Item FAILED: $($_.Exception.Message)"
}