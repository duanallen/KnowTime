$tests = @(
    'C:\Users\19173\.hvigor\test_dir_1',
    'C:\Users\19173\.hvigor\project_caches\test_dir_2',
    'C:\Users\19173\.hvigor\project_caches\3469d67c80712db8c21e591235db270f\test_dir_3',
    'C:\Users\19173\test_dir_4'
)

foreach ($t in $tests) {
    try {
        $result = New-Item -Path $t -ItemType Directory -ErrorAction Stop
        Write-Host "SUCCESS: $t"
        Remove-Item $result.FullName -Force
    } catch {
        Write-Host "FAILED: $t - $($_.Exception.Message)"
    }
}