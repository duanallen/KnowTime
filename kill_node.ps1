$procs = Get-Process | Where-Object { $_.ProcessName -eq 'node' }
foreach ($p in $procs) {
    Write-Host "Killing PID $($p.Id)"
    Stop-Process -Id $p.Id -Force
}
Start-Sleep -Seconds 2
Write-Host "Done. Remaining node processes:"
Get-Process | Where-Object { $_.ProcessName -eq 'node' } | Select-Object Id, ProcessName, StartTime