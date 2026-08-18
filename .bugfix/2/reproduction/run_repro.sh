#!/bin/bash
# Issue 2 复现执行脚本 - 成就勋章未实现功能
# 运行 HarmonyOS 单元测试
cd "D:\work\code\AICode\HarmonyOS\KnowTime"
hvigorw ohosTest 2>&1
echo "EXIT_CODE=$?"