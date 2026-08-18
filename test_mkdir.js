const fs = require('fs');
const path = require('path');

const basePath = 'C:\\Users\\19173\\.hvigor\\project_caches\\3469d67c80712db8c21e591235db270f';
const target = path.join(basePath, 'workspace');

console.log('node version: ' + process.version);
console.log('Trying mkdir: ' + target);
try {
  fs.mkdirSync(target);
  console.log('SUCCESS');
} catch (e) {
  console.log('FAILED: ' + e.code + ' ' + e.message);
}

// Try a different location
const altTarget = 'C:\\Users\\19173\\.hvigor\\project_caches\\test_alt_dir';
console.log('\nTrying alt mkdir: ' + altTarget);
try {
  fs.mkdirSync(altTarget);
  console.log('SUCCESS');
} catch (e) {
  console.log('FAILED: ' + e.code + ' ' + e.message);
}
