$cachePath = 'C:\Users\19173\.hvigor\project_caches\3469d67c80712db8c21e591235db270f'
if (Test-Path $cachePath) {
    Write-Host "Removing cache: $cachePath"
    Remove-Item -Path $cachePath -Recurse -Force -ErrorAction Continue
}
Write-Host "Exists after removal: $(Test-Path $cachePath)"