//! 封闭数值模式 - 只允许两种合法模式
//! fixed-point-first: 默认路径为 fixed_mcu_q15

/// 封闭数值模式枚举
/// 只允许 float32 和 fixed_mcu_q15 两种模式
/// 禁止外部自定义参数组合，防止非法配置
pub const NumericMode = enum {
    /// 32位浮点 - 仅用于 oracle/对照验证
    float32,
    /// Q15定点 - 默认实现路径(MCU目标)
    fixed_mcu_q15,
};
