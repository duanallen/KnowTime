// 简单的语法测试文件
// 模拟 ArkTS 的类型检查

class TestHourglass {
    getSandRatio() {
        return 0.5;
    }

    getUpperSandData() {
        const count = Math.floor(80 * (1 - this.getSandRatio()));
        const result = [];
        for (let i = 0; i < count; i++) {
            result.push(i);
        }
        return result;
    }

    getLowerSandData() {
        const count = Math.floor(80 * this.getSandRatio());
        const result = [];
        for (let i = 0; i < count; i++) {
            result.push(i);
        }
        return result;
    }

    getFlowingSandData() {
        const result = [];
        for (let i = 0; i < 2; i++) {
            result.push({
                x: 100 + (Math.random() - 0.5) * 8,
                y: 100,
                delay: i * 1000
            });
        }
        return result;
    }
}

// 测试代码
const test = new TestHourglass();
console.log('Upper sand data:', test.getUpperSandData());
console.log('Lower sand data:', test.getLowerSandData());
console.log('Flowing sand data:', test.getFlowingSandData());

// 测试代码
const test = new TestHourglass();
console.log('Upper sand data:', test.getUpperSandData());
console.log('Lower sand data:', test.getLowerSandData());
console.log('Flowing sand data:', test.getFlowingSandData());