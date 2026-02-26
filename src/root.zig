//! AEC3 - Acoustic Echo Canceller 3 (Zig port)
//! Fixed-point-first implementation

// 数值模式与配置
pub const NumericMode = @import("numeric_mode.zig").NumericMode;
pub const profileFor = @import("numeric_profile.zig").profileFor;

// 核心数值类型
pub const SampleOps = @import("sample_ops.zig").SampleOps;
pub const FixedPoint = @import("fixed_point.zig").FixedPoint;
pub const Complex = @import("complex.zig").Complex;

// FFT 子系统
pub const FftCore = @import("audio_processing/fft_core.zig").FftCore;
pub const isPowerOfTwo = @import("audio_processing/fft_core.zig").isPowerOfTwo;
pub const Aec3Fft = @import("audio_processing/aec3/aec3_fft.zig").Aec3Fft;
pub const Aec3Window = @import("audio_processing/aec3/aec3_fft.zig").Window;
pub const Aec3FftData = @import("audio_processing/aec3/fft_data.zig").FftData;
pub const NrFft = @import("audio_processing/ns/ns_fft.zig").NrFft;

// 测试入口（仅测试时编译）
test {
    _ = @import("numeric_mode.zig");
    _ = @import("numeric_profile.zig");
    _ = @import("sample_ops.zig");
    _ = @import("fixed_point.zig");
    _ = @import("complex.zig");
    _ = @import("test.zig");
    _ = @import("fft_test.zig");
    _ = @import("test_support/smoke_fir.zig");
}
