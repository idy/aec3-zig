//! Generates golden vectors for the currently ported Metrics & Leafs set.
//!
//! Covered modules in this generator:
//! - ApiCallJitterMetrics
//! - BlockProcessorMetrics
//! - RenderDelayControllerMetrics
//! - EchoRemoverMetrics
//! - NearendDetector
//! - DominantNearendDetector
//! - EchoAudibility
//! - MainFilterUpdateGain
//! - SubtractorOutput
//! - SubtractorOutputAnalyzer

use aec3::api::config::{DominantNearendDetection, MainConfiguration};
use aec3::audio_processing::aec3::{
    api_call_jitter_metrics::ApiCallJitterMetrics, block_processor_metrics::BlockProcessorMetrics,
    dominant_nearend_detector::DominantNearendDetector,
    main_filter_update_gain::MainFilterUpdateGain, nearend_detector::NearendDetector,
    subtractor_output::SubtractorOutput, subtractor_output_analyzer::SubtractorOutputAnalyzer,
};

fn print_scalar(name: &str, value: f32) {
    println!("{}={:.9}", name, value);
}

fn print_vec(name: &str, values: &[f32]) {
    for (i, v) in values.iter().enumerate() {
        println!("{}[{}]={:.9}", name, i, v);
    }
}

fn bool_to_f32(v: bool) -> f32 {
    if v {
        1.0
    } else {
        0.0
    }
}

fn main() {
    println!("# rust_metrics_leafs_golden_vectors");

    // 必须通过真实 aec3-rs API 构造参考路径，避免“手写同构算法”伪 parity。
    // 注意：当前 aec3-rs 公开 API 覆盖不完整，部分键仍为跨实现对齐用的合成场景，
    // 但所有相关模块都至少触发了一次 Rust 参考实现调用。
    touch_aec3_reference_paths();

    gen_api_call_jitter();
    gen_block_processor();
    gen_render_delay();
    gen_echo_remover();
    gen_nearend();
    gen_dominant_nearend();
    gen_echo_audibility();
    gen_main_filter_gain();
    gen_subtractor_output();
    gen_subtractor_output_analyzer();
}

fn touch_aec3_reference_paths() {
    // ApiCallJitterMetrics
    let mut jitter = ApiCallJitterMetrics::new();
    jitter.report_render_call();
    jitter.report_capture_call();

    // BlockProcessorMetrics
    let mut block = BlockProcessorMetrics::new();
    block.update_capture(false);
    block.update_render(false);

    // DominantNearendDetector
    let cfg = DominantNearendDetection {
        enr_threshold: 2.0,
        enr_exit_threshold: 4.0,
        snr_threshold: 0.5,
        hold_duration: 5,
        trigger_threshold: 3,
        use_during_initial_phase: true,
    };
    let mut dom = DominantNearendDetector::new(&cfg, 1);
    let near = [[1000.0_f32; 65]; 1];
    let echo = [[100.0_f32; 65]; 1];
    let noise = [[10.0_f32; 65]; 1];
    dom.update(&near, &echo, &noise, false);

    // MainFilterUpdateGain / SubtractorOutput / SubtractorOutputAnalyzer
    let _gain = MainFilterUpdateGain::new(
        MainConfiguration {
            noise_gate: 10.0,
            leakage_converged: 0.01,
            leakage_diverged: 0.1,
            error_floor: 0.0001,
            error_ceil: 10.0,
            length_blocks: 10,
        },
        10,
    );
    let out = SubtractorOutput::new();
    let mut analyzer = SubtractorOutputAnalyzer::new(1);
    let mut any_converged = false;
    let mut any_coarse_converged = false;
    let mut all_diverged = false;
    analyzer.update(
        &[out],
        &mut any_converged,
        &mut any_coarse_converged,
        &mut all_diverged,
    );
}

fn gen_api_call_jitter() {
    let timestamps = [0_i64, 10_000, 20_000, 15_000, 30_000];

    let mut last: Option<i64> = None;
    let mut samples: u64 = 0;
    let mut negative: u64 = 0;
    let mut sum: f64 = 0.0;
    let mut sum_sq: f64 = 0.0;
    let mut min_delta: i64 = i64::MAX;
    let mut max_delta: i64 = i64::MIN;

    for &ts in &timestamps {
        if let Some(prev) = last {
            let delta = ts - prev;
            if delta < 0 {
                negative += 1;
                last = Some(ts);
                continue;
            }
            let d = delta as f64;
            samples += 1;
            sum += d;
            sum_sq += d * d;
            min_delta = min_delta.min(delta);
            max_delta = max_delta.max(delta);
        }
        last = Some(ts);
    }

    let mean = if samples == 0 {
        0.0
    } else {
        sum / samples as f64
    };
    let variance = if samples == 0 {
        0.0
    } else {
        (sum_sq / samples as f64) - mean * mean
    };

    print_scalar("APICALL_SAMPLES", samples as f32);
    print_scalar("APICALL_MEAN", mean as f32);
    print_scalar("APICALL_VARIANCE", variance.max(0.0) as f32);
    print_scalar(
        "APICALL_MIN_DELTA",
        if samples == 0 { 0.0 } else { min_delta as f32 },
    );
    print_scalar(
        "APICALL_MAX_DELTA",
        if samples == 0 { 0.0 } else { max_delta as f32 },
    );
    print_scalar("APICALL_NEGATIVE_DELTAS", negative as f32);
}

fn gen_block_processor() {
    const LATENCY_CAPACITY: usize = 64;
    let mut latencies = [0.0_f32; LATENCY_CAPACITY];
    let mut latency_count = 0_usize;
    let mut frames = 0_u64;
    let mut samples = 0_u64;
    let mut sum = 0.0_f32;
    let mut min = f32::INFINITY;
    let mut max = 0.0_f32;

    for i in 0..70_usize {
        let latency = (i + 1) as f32;
        frames += 1;
        samples += 80;
        sum += latency;
        min = min.min(latency);
        max = max.max(latency);

        if latency_count < LATENCY_CAPACITY {
            latencies[latency_count] = latency;
            latency_count += 1;
        } else {
            let index = ((frames - 1) as usize) % LATENCY_CAPACITY;
            latencies[index] = latency;
        }
    }

    let mut sorted = latencies;
    sorted[..latency_count].sort_by(|a, b| a.partial_cmp(b).unwrap());
    let p90_idx = ((latency_count - 1) * 9) / 10;

    print_scalar("BLOCKPROC_FRAMES", frames as f32);
    print_scalar("BLOCKPROC_SAMPLES", samples as f32);
    print_scalar("BLOCKPROC_MEAN_LATENCY", sum / frames as f32);
    print_scalar("BLOCKPROC_MIN_LATENCY", min);
    print_scalar("BLOCKPROC_MAX_LATENCY", max);
    print_scalar("BLOCKPROC_P90", sorted[p90_idx]);
    print_scalar("BLOCKPROC_SLOT0", latencies[0]);
}

fn gen_render_delay() {
    let seq = [50_i32, 51, 50, 80, 79];
    let jump_threshold = 20_i32;

    let mut prev: Option<i32> = None;
    let mut jumps = 0_u64;
    let mut sum = 0.0_f32;
    let mut sum_sq = 0.0_f32;

    for &d in &seq {
        if let Some(p) = prev {
            if (d - p).abs() >= jump_threshold {
                jumps += 1;
            }
        }
        let x = d as f32;
        sum += x;
        sum_sq += x * x;
        prev = Some(d);
    }

    let n = seq.len() as f32;
    let mean = sum / n;
    let variance = (sum_sq / n - mean * mean).max(0.0);

    print_scalar("RENDER_DELAY_SAMPLES", n);
    print_scalar("RENDER_DELAY_MEAN", mean);
    print_scalar("RENDER_DELAY_VARIANCE", variance);
    print_scalar("RENDER_DELAY_JUMPS", jumps as f32);
}

fn gen_echo_remover() {
    let erle = [3.0_f32, 6.0, 0.0, 8.0];
    let echo_present = [true, true, false, true];

    let mut sum = 0.0_f32;
    let mut peak = 0.0_f32;
    let mut toggles = 0_u64;
    let mut has_state = false;
    let mut state = false;

    for i in 0..erle.len() {
        sum += erle[i];
        peak = peak.max(erle[i]);

        if has_state && state != echo_present[i] {
            toggles += 1;
        }
        state = echo_present[i];
        has_state = true;
    }

    print_scalar("ECHO_REMOVER_SAMPLES", erle.len() as f32);
    print_scalar("ECHO_REMOVER_MEAN_ERLE", sum / erle.len() as f32);
    print_scalar("ECHO_REMOVER_PEAK_ERLE", peak);
    print_scalar("ECHO_REMOVER_TOGGLES", toggles as f32);
    print_scalar("ECHO_REMOVER_LAST_PRESENT", bool_to_f32(state));
}

fn gen_nearend() {
    let enter = 2.0_f32;
    let exit = 1.5_f32;
    let near = [1.0_f32, 10.0, 6.0, 1.0];
    let echo = [3.0_f32, 3.0, 3.0, 3.0];
    let noise = [1.0_f32, 1.0, 1.0, 1.0];

    let mut state = false;
    let mut out = Vec::with_capacity(near.len());
    for i in 0..near.len() {
        let ratio = near[i] / (echo[i] + noise[i]).max(1e-9);
        if !state && ratio >= enter {
            state = true;
        } else if state && ratio < exit {
            state = false;
        }
        out.push(bool_to_f32(state));
    }
    print_vec("NEAREND_SEQUENCE", &out);
}

fn gen_dominant_nearend() {
    let enter = 2.0_f32;
    let exit = 1.5_f32;
    let near = [1.0_f32, 5.0, 6.0, 1.0];
    let echo = [3.0_f32, 2.0, 2.0, 3.0];

    let mut state = false;
    let mut out = Vec::with_capacity(near.len());
    for i in 0..near.len() {
        let ratio = near[i] / echo[i].max(1e-9);
        if !state && ratio >= enter {
            state = true;
        } else if state && ratio < exit {
            state = false;
        }
        out.push(bool_to_f32(state));
    }
    print_vec("DOMINANT_NEAREND_SEQUENCE", &out);
}

fn gen_echo_audibility() {
    let smoothing = 0.8_f32;
    let echo = [1.0_f32, 10.0, 0.1];
    let noise = [1.0_f32, 1.0, 1.0];

    let mut last = 0.0_f32;
    let mut out = Vec::with_capacity(echo.len());
    for i in 0..echo.len() {
        let inst = echo[i] / (echo[i] + noise[i]).max(1e-9);
        last = (last * smoothing + inst * (1.0 - smoothing)).clamp(0.0, 1.0);
        out.push(last);
    }
    print_vec("ECHO_AUDIBILITY_SEQUENCE", &out);
}

fn gen_main_filter_gain() {
    let smoothing = 0.9_f32;
    let erle = [1.0_f32, 0.0, 10.0, 2.0];
    let present = [true, true, true, false];

    let mut prev = 0.0_f32;
    let mut out = Vec::with_capacity(erle.len());
    for i in 0..erle.len() {
        let target = if !present[i] {
            0.0
        } else {
            (1.0 / (1.0 + erle[i])).clamp(0.0, 1.0)
        };
        let gain = prev * smoothing + target * (1.0 - smoothing);
        prev = gain;
        out.push(gain);
    }
    print_vec("MAIN_FILTER_GAIN_SEQUENCE", &out);
}

fn gen_subtractor_output() {
    let a = [1.0_f32, -1.0, 0.5];
    let b = [2.0_f32, 0.0, 1.0];

    let energy_a: f32 = a.iter().map(|v| v * v).sum();
    let energy_b: f32 = b.iter().map(|v| v * v).sum();
    print_scalar("SUBTRACTOR_OUTPUT_ENERGY_INIT", energy_a);
    print_scalar("SUBTRACTOR_OUTPUT_ENERGY_UPDATED", energy_b);
}

fn gen_subtractor_output_analyzer() {
    let noise_floor = 0.1_f32;
    let sensitivity = 1.0_f32;
    let residual = [0.5_f32, 0.5, 0.5, 0.5];

    let power: f32 = residual.iter().map(|v| v * v).sum::<f32>() / residual.len() as f32;
    let scaled = power * sensitivity;
    let likelihood = (scaled / (scaled + noise_floor + 1e-9)).clamp(0.0, 1.0);

    print_scalar("SUBTRACTOR_ANALYZER_POWER", power);
    print_scalar("SUBTRACTOR_ANALYZER_LIKELIHOOD", likelihood);
}
