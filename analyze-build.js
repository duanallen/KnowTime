const fs = require('fs');

const content = fs.readFileSync('entry/src/main/ets/pages/FocusPage.ets', 'utf-8');
const lines = content.split('\n');

let buildStart = -1;
let buildEnd = -1;
let braceStack = [];

// 找到build方法的位置
for (let i = 0; i < lines.length; i++) {
  if (lines[i].trim() === 'build() {') {
    buildStart = i;
  }
  if (buildStart !== -1 && lines[i].trim() === '}' && lines[i + 1] && !lines[i + 1].startsWith(' ') && !lines[i + 1].startsWith('\t')) {
    buildEnd = i;
    break;
  }
}

console.log(`Build方法位置: ${buildStart} - ${buildEnd}`);

// 分析build方法内的括号匹配
for (let i = buildStart; i <= buildEnd; i++) {
  const line = lines[i];
  let inString = false;
  let stringChar = '';
  
  for (let j = 0; j < line.length; j++) {
    const char = line[j];
    
    // 处理字符串状态
    if (!inString && (char === '"' || char === "'")) {
      inString = true;
      stringChar = char;
    } else if (inString && char === stringChar) {
      inString = false;
      stringChar = '';
    }
    
    // 只统计不在字符串中的括号
    if (!inString) {
      if (char === '{') {
        braceStack.push({ line: i, char: '{' });
      } else if (char === '}') {
        if (braceStack.length > 0 && braceStack[braceStack.length - 1].char === '{') {
          braceStack.pop();
        } else {
          console.log(`错误: 第${i + 1}行有多余的 }`);
        }
      }
    }
  }
}

if (braceStack.length === 0) {
  console.log('✓ Build方法内的括号匹配正确');
} else {
  console.log(`⚠️ Build方法内有未闭合的括号:`);
  braceStack.forEach(item => {
    console.log(`  第${item.line + 1}行的 {`);
  });
}