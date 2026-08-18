$nodeExe = 'D:\software\toolInstall\DevEcoStudio6.1.1Release\DevEco Studio\tools\node\node.exe'
$testScript = @'
const fs = require('fs');
const path = 'C:\\Users\\19173\\.hvigor\\project_caches\\3469d67c80712db8c21e591235db270f\\workspace\\node_modules\\@ohos';
try {
  fs.mkdirSync(path, { recursive: true });
  console.log('mkdir SUCCESS');
} catch (e) {
  console.log('mkdir FAILED:', e.code, e.message);
}
'@
$testScript | Out-File -FilePath 'D:\work\code\AICode\HarmonyOS\KnowTime\test_mkdir.js' -Encoding UTF8
& $nodeExe 'D:\work\code\AICode\HarmonyOS\KnowTime\test_mkdir.js'