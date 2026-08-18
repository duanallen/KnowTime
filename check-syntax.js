// 简单的语法检查脚本
const fs = require('fs');
const path = require('path');

// 检查关键文件是否存在
const keyFiles = [
  'entry/src/main/ets/pages/FocusPage.ets',
  'entry/src/main/ets/viewmodel/FocusViewModel.ets',
  'entry/src/main/ets/models/FocusSession.ets'
];

console.log('=== 检查文件是否存在 ===');
keyFiles.forEach(file => {
  const fullPath = path.join(__dirname, file);
  if (fs.existsSync(fullPath)) {
    console.log(`✓ ${file} 存在`);
  } else {
    console.log(`✗ ${file} 不存在`);
  }
});

console.log('\n=== 检查主要语法问题 ===');

// 检查FocusPage是否有明显的语法错误
const focusPagePath = path.join(__dirname, 'entry/src/main/ets/pages/FocusPage.ets');
try {
  const content = fs.readFileSync(focusPagePath, 'utf-8');
  
  // 检查是否有未闭合的括号
  const openBraces = (content.match(/\{/g) || []).length;
  const closeBraces = (content.match(/\}/g) || []).length;
  
  // 检查是否有未闭合的括号
  const openParens = (content.match(/\(/g) || []).length;
  const closeParens = (content.match(/\)/g) || []).length;
  
  console.log(`FocusPage 大括号匹配: ${openBraces} 开启, ${closeBraces} 关闭`);
  console.log(`FocusPage 圆括号匹配: ${openParens} 开启, ${closeParens} 关闭`);
  
  // 检查是否有明显的语法错误
  if (openBraces !== closeBraces) {
    console.log('⚠️  FocusPage 大括号可能不匹配');
  }
  if (openParens !== closeParens) {
    console.log('⚠️  FocusPage 圆括号可能不匹配');
  }
  
  // 检查是否有明显的API问题
  const deprecatedAPIs = [
    'media.SoundUsage.NOTIFICATION',
    'media.StreamUsage.STREAM_USAGE_MEDIA',
    'vibrator.getVibratorInfo()',
    'vibrator.cancelVibration'
  ];
  
  deprecatedAPIs.forEach(api => {
    if (content.includes(api)) {
      console.log(`⚠️  发现可能的问题API: ${api}`);
    }
  });
  
} catch (error) {
  console.error('无法读取FocusPage文件:', error.message);
}

// 检查FocusViewModel
const focusViewModelPath = path.join(__dirname, 'entry/src/main/ets/viewmodel/FocusViewModel.ets');
try {
  const content = fs.readFileSync(focusViewModelPath, 'utf-8');
  
  const openBraces = (content.match(/\{/g) || []).length;
  const closeBraces = (content.match(/\}/g) || []).length;
  
  const openParens = (content.match(/\(/g) || []).length;
  const closeParens = (content.match(/\)/g) || []).length;
  
  console.log(`\nFocusViewModel 大括号匹配: ${openBraces} 开启, ${closeBraces} 关闭`);
  console.log(`FocusViewModel 圆括号匹配: ${openParens} 开启, ${closeParens} 关闭`);
  
  if (openBraces !== closeBraces) {
    console.log('⚠️  FocusViewModel 大括号可能不匹配');
  }
  if (openParens !== closeParens) {
    console.log('⚠️  FocusViewModel 圆括号可能不匹配');
  }
  
} catch (error) {
  console.error('无法读取FocusViewModel文件:', error.message);
}

console.log('\n=== 检查完成 ===');