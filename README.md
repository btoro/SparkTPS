# SparkTPS

SparkTPS is a lightweight native macOS menu-bar monitor for live LLM inference throughput on a remote NVIDIA DGX Spark or another SGLang/vLLM host.

The menu bar itself always shows a five-second rolling average of aggregate output TPS and the number of requests actively being served, including zero values while idle:

```text
48.2 t/s · 2r
```

The popover adds input/output/total TPS, one-minute average and peak, active and queued requests, recent and engine-lifetime processed request counts, and a 60-second throughput chart.

An optional idle alert flashes the menu-bar text after a configurable period without inference activity. It is enabled by default at 10 minutes. The bell in the popover header switches it on or off, while the threshold remains in Settings. Opening the menu item dismisses the alert until new activity resumes.

## Why direct metrics instead of Grafana?

SparkTPS reads the inference engine's Prometheus-compatible `/metrics` endpoint directly. This avoids requiring Grafana credentials, data-source IDs, PromQL proxy calls, or a separate Prometheus/Grafana installation. Requests advertise gzip compression and adapt between one-second polling while busy and five-second polling while idle.

## Supported engines

- SGLang: native `gen_throughput`, live `realtime_tokens_total` decode/prefill counters, request gauges, and processed-request counters.
- vLLM: `generation_tokens_total`, `prompt_tokens_total`, `num_requests_running`, `num_requests_waiting`, and `request_success_total`.

Counters are summed across labels such as streaming mode and finish reason. SGLang's output headline smooths its native live-throughput gauge; input TPS uses its real-time `prefill_compute` counter. vLLM uses rolling counter deltas.

## Build and run

Requirements: macOS 13 or newer and Xcode 16 or a compatible Swift 6 toolchain.

```bash
swift test
./scripts/package.sh
open dist/SparkTPS.app
```

On first launch, click `Spark · Setup` in the menu bar and enter the engine's metrics URL, for example:

```text
http://spark-host:8000/metrics
```

If the path is omitted, SparkTPS adds `/metrics` automatically.

## Networking and security

Keep the metrics endpoint private. A tailnet address or private LAN is recommended. SparkTPS does not need the inference API key and does not send prompts, completions, or telemetry anywhere.

The packaged app permits HTTP because many private inference endpoints do not use TLS. Prefer a private network or HTTPS; do not expose an unauthenticated metrics endpoint publicly.

## Metric semantics

The headline TPS is aggregate output throughput across the engine, not per-request speed. With two active requests and `48 t/s`, the engine is producing 48 output tokens per second across both requests. Exact per-request TPS requires request-level tracing and is intentionally not estimated.

## License

MIT
