const std = @import("std");

const aec3_common = @import("audio_processing/aec3/aec3_common.zig");
const delay_estimate = @import("audio_processing/aec3/delay_estimate.zig");
const echo_path = @import("audio_processing/aec3/echo_path_variability.zig");
const stream_config = @import("audio_processing/stream_config.zig");
const audio_util = @import("audio_processing/audio_util.zig");
const audio_frame = @import("audio_processing/audio_frame.zig");
const channel_buffer = @import("audio_processing/channel_buffer.zig");
const config = @import("api/config.zig");
const control = @import("api/control.zig");
const apm_dumper = @import("audio_processing/logging/apm_data_dumper.zig");

test "aec3_common edge inputs" {
    try std.testing.expectEqual(@as(usize, 0), aec3_common.num_bands_for_rate(-16_000));
    try std.testing.expect(!aec3_common.valid_full_band_rate(44_100));
    try std.testing.expectEqual(@as(usize, 0), aec3_common.get_time_domain_length(0));
}

test "delay estimate constructor preserves inputs" {
    const d = delay_estimate.DelayEstimate.new(.refined, 0);
    try std.testing.expectEqual(delay_estimate.DelayEstimateQuality.refined, d.quality);
    try std.testing.expectEqual(@as(usize, 0), d.delay);
}

test "echo path constructor preserves clock drift" {
    const v = echo_path.EchoPathVariability.new(false, .none, true);
    try std.testing.expect(v.clock_drift);
}

test "stream config zero rate boundary" {
    var cfg = stream_config.StreamConfig.new(0, 2, false);
    try std.testing.expectEqual(@as(usize, 0), cfg.num_frames());
    try std.testing.expectEqual(@as(usize, 0), cfg.num_samples());
    cfg.set_sample_rate_hz(16_000);
    try std.testing.expectEqual(@as(usize, 160), cfg.num_frames());
}

test "audio_util scalar boundary conversions" {
    try std.testing.expectEqual(@as(i16, 32767), audio_util.float_s16_to_s16(100000.0));
    try std.testing.expectEqual(@as(i16, -32768), audio_util.float_s16_to_s16(-100000.0));
    try std.testing.expectEqual(@as(f32, 32768.0), audio_util.float_to_float_s16(100.0));
    try std.testing.expectEqual(@as(f32, -32768.0), audio_util.float_to_float_s16(-100.0));
    try std.testing.expectEqual(@as(f32, 1.0), audio_util.float_s16_to_float(1.0e9));
    try std.testing.expectEqual(@as(f32, -1.0), audio_util.float_s16_to_float(-1.0e9));
}

test "audio_util slice conversion APIs" {
    const s16 = [_]i16{ -1, 0, 1 };
    var f32_s16 = [_]f32{ 0, 0, 0 };
    audio_util.s16_slice_to_float_s16(&s16, &f32_s16);
    try std.testing.expectEqual(@as(f32, -1), f32_s16[0]);

    var s16_back = [_]i16{ 0, 0, 0 };
    audio_util.float_s16_slice_to_s16(&f32_s16, &s16_back);
    try std.testing.expectEqualSlices(i16, &s16, &s16_back);

    const norm = [_]f32{ -1.0, 0.0, 1.0 };
    var norm_to_s16 = [_]f32{ 0, 0, 0 };
    audio_util.float_slice_to_float_s16(&norm, &norm_to_s16);
    try std.testing.expectEqual(@as(f32, -32768.0), norm_to_s16[0]);
    audio_util.float_slice_to_float_s16_in_place(&norm_to_s16);
    try std.testing.expectEqual(@as(f32, -32768.0), norm_to_s16[0]);

    var back_norm = [_]f32{ 0, 0, 0 };
    audio_util.float_s16_slice_to_float(&norm_to_s16, &back_norm);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), back_norm[0], 1e-6);
    audio_util.float_s16_slice_to_float_in_place(&norm_to_s16);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), norm_to_s16[0], 1e-6);
}

test "audio_util copy_audio_if_needed and integer downmix" {
    var src0 = [_]i16{ 1, 2, 3, 4 };
    var src1 = [_]i16{ 9, 10, 11, 12 };
    var dst0 = [_]i16{ 0, 0, 0, 0 };
    var dst1 = [_]i16{ 0, 0, 0, 0 };
    const src = [_][]const i16{ src0[0..], src1[0..] };
    const dst = [_][]i16{ dst0[0..], dst1[0..] };
    audio_util.copy_audio_if_needed(i16, &src, 4, &dst);
    try std.testing.expectEqualSlices(i16, src0[0..], dst0[0..]);
    try std.testing.expectEqualSlices(i16, src1[0..], dst1[0..]);

    const mono_in = [_][]const i16{ src0[0..2], src1[0..2] };
    var mono_out = [_]i16{ 0, 0 };
    audio_util.downmix_to_mono_i16(&mono_in, 2, &mono_out);
    try std.testing.expectEqual(@as(i16, 5), mono_out[0]);

    const inter = [_]i16{ 2, 4, 6, 8 };
    var inter_mono = [_]i16{ 0, 0 };
    audio_util.downmix_interleaved_to_mono_i16(&inter, 2, 2, &inter_mono);
    try std.testing.expectEqual(@as(i16, 3), inter_mono[0]);
    try std.testing.expectEqual(@as(i16, 7), inter_mono[1]);
}

test "audio_frame reset/copy/profile/mutable_data" {
    var frame = audio_frame.AudioFrame.new();
    const data = [_]i16{ 5, 6, 7, 8 };
    frame.update_frame(9, &data, 2, 16_000, .normal_speech, .active, 2);
    frame.update_profile_timestamp();
    try std.testing.expect(frame.elapsed_profile_time_ms() >= 0);

    var copy = audio_frame.AudioFrame.new();
    copy.copy_from(&frame);
    try std.testing.expectEqual(@as(u32, 9), copy.timestamp);

    copy.mute();
    _ = copy.mutable_data();
    try std.testing.expect(!copy.muted());

    copy.reset_without_muting();
    try std.testing.expect(!copy.muted());
    copy.reset();
    try std.testing.expect(copy.muted());
}

test "channel buffer metadata and IF conversion" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var buf = try channel_buffer.ChannelBuffer(f32).new(arena.allocator(), 8, 2, 2);
    defer buf.deinit();
    try std.testing.expectEqual(@as(usize, 8), buf.num_frames());
    try std.testing.expectEqual(@as(usize, 4), buf.num_frames_per_band());
    try std.testing.expectEqual(@as(usize, 2), buf.num_channels());
    try std.testing.expectEqual(@as(usize, 2), buf.num_bands());
    buf.set_num_channels(1);
    try std.testing.expectEqual(@as(usize, 1), buf.num_channels());
    _ = buf.data();
    _ = buf.data_mut();

    var ifbuf = try channel_buffer.IFChannelBuffer.new(arena.allocator(), 4, 1, 1);
    defer ifbuf.deinit();
    ifbuf.ibuf().channel_mut(0)[0] = 123;
    const fconst = ifbuf.fbuf_const();
    try std.testing.expectEqual(@as(f32, 123), fconst.channel(0)[0]);
    ifbuf.fbuf().channel_mut(0)[1] = 77.0;
    const iconst = ifbuf.ibuf_const();
    try std.testing.expectEqual(@as(i16, 77), iconst.channel(0)[1]);
    ifbuf.set_num_channels(1);
}

test "config init methods and defaults" {
    const b = config.Buffering.default();
    try std.testing.expectEqual(@as(usize, 250), b.excess_render_detection_interval_blocks);
    _ = config.Delay.default();
    _ = config.Filter.default();
    _ = config.Erle.default();
    _ = config.EpStrength.default();
    _ = config.EchoAudibility.default();
    _ = config.RenderLevels.default();
    _ = config.EchoRemovalControl.default();
    _ = config.TransparentModeConfig.default();
    _ = config.EchoModel.default();
    _ = config.Suppressor.default();

    const mask = config.MaskingThresholds.init(0.1, 0.2, 0.3);
    try std.testing.expectEqual(@as(f32, 0.1), mask.enr_transparent);
    const tuning = config.Tuning.init(mask, mask, 1.2, 0.8);
    try std.testing.expectEqual(@as(f32, 1.2), tuning.max_inc_factor);
}

test "control vtable wrapper calls through" {
    const Buffer = [4]f32;
    const Ctl = control.EchoControl(Buffer);

    const State = struct {
        count: usize = 0,
        delay: i32 = 0,
    };

    const Impl = struct {
        fn analyze_render(ctx: *anyopaque, _: *Buffer) void {
            const s: *State = @ptrCast(@alignCast(ctx));
            s.count += 1;
        }
        fn analyze_capture(ctx: *anyopaque, _: *Buffer) void {
            const s: *State = @ptrCast(@alignCast(ctx));
            s.count += 1;
        }
        fn process_capture(ctx: *anyopaque, _: *Buffer, _: bool) void {
            const s: *State = @ptrCast(@alignCast(ctx));
            s.count += 1;
        }
        fn process_capture_with_linear_output(ctx: *anyopaque, _: *Buffer, _: *Buffer, _: bool) void {
            const s: *State = @ptrCast(@alignCast(ctx));
            s.count += 1;
        }
        fn metrics(_: *const anyopaque) control.Metrics {
            return .{};
        }
        fn set_audio_buffer_delay(ctx: *anyopaque, delay_ms: i32) void {
            const s: *State = @ptrCast(@alignCast(ctx));
            s.delay = delay_ms;
        }
        fn active_processing(_: *const anyopaque) bool {
            return true;
        }
    };

    var state = State{};
    const vt = Ctl.VTable{
        .analyze_render = Impl.analyze_render,
        .analyze_capture = Impl.analyze_capture,
        .process_capture = Impl.process_capture,
        .process_capture_with_linear_output = Impl.process_capture_with_linear_output,
        .metrics = Impl.metrics,
        .set_audio_buffer_delay = Impl.set_audio_buffer_delay,
        .active_processing = Impl.active_processing,
    };
    const ec = Ctl{ .ctx = &state, .vtable = &vt };

    var b0: Buffer = .{ 0, 0, 0, 0 };
    var b1: Buffer = .{ 0, 0, 0, 0 };
    ec.analyze_render(&b0);
    ec.analyze_capture(&b0);
    ec.process_capture(&b0, false);
    ec.process_capture_with_linear_output(&b0, &b1, true);
    const m = ec.metrics();
    ec.set_audio_buffer_delay(55);
    try std.testing.expect(ec.active_processing());
    try std.testing.expectEqual(@as(usize, 4), state.count);
    try std.testing.expectEqual(@as(i32, 55), state.delay);
    try std.testing.expectEqual(@as(i32, 0), m.delay_ms);
}

test "apm data dumper instance index accessor" {
    const d = apm_dumper.ApmDataDumper.new(42);
    try std.testing.expectEqual(@as(usize, 42), d.instance_index());
}
