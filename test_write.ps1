$testDir = 'C:\Users\19173\.hvigor\project_caches\3469d67c80712db8c21e591235db270f\workspace\node_modules\@ohos'
$testFile = Join-Path $testDir 'test_write.txt'
try {
    if (-not (Test-Path $testDir)) {
        New-Item -Path $testDir -ItemType Directory -Force | Out-Null
    }
    Set-Content -Path $testFile -Value 'test' -Encoding UTF8
    Write-Host "Write test PASSED"
    Remove-Item $testFile -Force
} catch {
    Write-Host "Write test FAILED: $($_.Exception.Message)"
}