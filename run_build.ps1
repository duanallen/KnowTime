$env:DEVECO_SDK_HOME = 'D:\software\toolInstall\DevEcoStudio6.1.1Release\DevEco Studio\sdk'
$env:HARMONYOS_SDK_HOME = 'D:\software\toolInstall\DevEcoStudio6.1.1Release\DevEco Studio\sdk'
Set-Location 'D:\work\code\AICode\HarmonyOS\KnowTime'
$output = & 'D:\software\toolInstall\DevEcoStudio6.1.1Release\DevEco Studio\tools\node\node.exe' 'D:\software\toolInstall\DevEcoStudio6.1.1Release\DevEco Studio\tools\hvigor\bin\hvigorw.js' assembleHap --mode module -p module=entry --no-daemon 2>&1
$output | Out-File -FilePath 'D:\work\code\AICode\HarmonyOS\KnowTime\build-output-latest.log' -Encoding UTF8
Write-Output $output
