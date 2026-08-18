#!/bin/bash
# Issue 1 复现执行脚本 - 专注页面熄屏停止计时
# 运行 HarmonyOS 单元测试
cd "D:\work\code\AICode\HarmonyOS\KnowTime"
hvigorw ohosTest 2>&1
echo "EXIT_CODE=$?"