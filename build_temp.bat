@echo off
set "DEVECO_SDK_HOME=D:\software\toolInstall\DevEcoStudio6.1.1Release\DevEco Studio\sdk"
set "HARMONYOS_SDK_HOME=D:\software\toolInstall\DevEcoStudio6.1.1Release\DevEco Studio\sdk"
cd /d "D:\work\code\AICode\HarmonyOS\KnowTime"
"D:\software\toolInstall\DevEcoStudio6.1.1Release\DevEco Studio\tools\node\node.exe" "D:\software\toolInstall\DevEcoStudio6.1.1Release\DevEco Studio\tools\hvigor\bin\hvigorw.js" assembleHap --mode module -p module=entry --no-daemon