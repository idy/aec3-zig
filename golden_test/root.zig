//! Golden vector test entrypoint

test {
    _ = @import("zig/test_utils.zig");
    _ = @import("zig/foundation.zig");
    _ = @import("zig/ns.zig");
    _ = @import("zig/audio_infra.zig");
    _ = @import("zig/fft.zig");
    _ = @import("zig/erle_reverb.zig");
    _ = @import("zig/metrics_leafs.zig");
    _ = @import("zig/aec3_blocks.zig");
}
