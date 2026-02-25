//! AEC3 - Acoustic Echo Canceller 3 (Zig port)
//! Fixed-point-first implementation

// 数值模式与配置
pub const NumericMode = @import("numeric_mode.zig").NumericMode;
pub const profileFor = @import("numeric_profile.zig").profileFor;

// 核心数值类型
pub const SampleOps = @import("sample_ops.zig").SampleOps;
pub const FixedPoint = @import("fixed_point.zig").FixedPoint;
pub const Complex = @import("complex.zig").Complex;

// 测试入口（仅测试时编译）
test {
    _ = @import("numeric_mode.zig");
    _ = @import("numeric_profile.zig");
    _ = @import("sample_ops.zig");
    _ = @import("fixed_point.zig");
    _ = @import("complex.zig");
    _ = @import("test.zig");
    _ = @import("test_support/smoke_fir.zig");
}
