# 001 — Investigate persistent Pixman fill hotpath in modern rendering mode

**Status**: Open
**Priority**: P2 (Medium)
**Severity**: Moderate
**Category**: Performance
**Related**: [Rendering pipeline study](../docs/studies/rendering_pipeline_4k.md), commit `302f4962`

---

## 1. Problem & Motivation

Tilix remains CPU-bound in Pixman while running the repaint probe in the experimental modern mode. A roughly 20-second `perf` capture of maximized Tilix running `loom-repaint-probe --fps 120` attributed 89.22% of sampled CPU time to Pixman `sse2_fill`. The call chain passes through Cairo into GTK background drawing and repaint scheduling. VTE `Terminal::get_text` was the next largest symbol at 1.60%.

An earlier legacy-mode capture attributed 89.41% to the same Pixman function. These runs were separate and do not establish a before/after difference. The modern-mode profile still shows software fills dominating, but no controlled benchmark isolates the callback's performance effect.

**Goal**: `/goal` Attribute the dominant software fills in the modern-mode repaint workload, then make the smallest supported change that improves measured CPU cost or repaint rate; if the work is outside Tilix or cannot be reproduced, document the evidence and next experiment.

## 2. Technical Specification / Findings

The modern-mode capture contained 1,554 samples. Other leading symbols were Pixman `sse2_composite_over_n_8_8888` (1.55%) and VTE `process_incoming_utf8` (0.76%). The legacy capture had 1,920 samples over about 25 seconds. These separate captures do not establish a before/after difference. Source review shows both draw callbacks still use Cairo `SOURCE` background paint; the experimental callback mainly changes badge drawing and layout caching. `GDK_GL=always` was reported slower by the user and is not an established fix.

A follow-up capture explicitly selected modern mode and sampled the checkout Tilix process for 22.48 seconds (1,470 samples, no lost samples). Pixman `sse2_fill` accounted for 83.46% of sampled cycles. `perf report --call-graph=graph` attributes 12.71% of all sampled cycles to Tilix's `Terminal::onVTEDrawBadge` → `renderModernPath` → Cairo `paint` → Pixman `sse2_fill` chain. Other chains pass through GTK CSS widget backgrounds, GDK backing-area clearing, and VTE `Terminal::draw_rows` / `DrawingCairo::fill_rectangle`. This gives a concrete Tilix-owned paint candidate; the trace does not report its clip area or establish that the fill is redundant. The raw profile and reports are in `/tmp/tilix-perf-20261004-modern/` on the capture machine.

## 3. Implementation & Verification Plan

The modern preference was explicitly enabled for the follow-up capture and restored afterward. An opaque-background experiment skipped `renderModernPath`'s base `paint()` while preserving badge and margin drawing. That call chain disappeared, but an exploratory comparison showed only about 1.6% lower total cycles per second, so this alone does not meet the 20% target.

The stronger change omits the `.tilix-background` CSS class from session and stack containers when the global transparency capability is disabled. With transparency disabled in both arms and the opaque-paint change present in both, two matched 20.17-second `perf stat` A/B pairs showed 30.5% and 27.0% less Tilix task-clock time; cycle counts fell 31.8% and 31.0%. The change retains these CSS fills when transparency is enabled. This demonstrates more than 20% lower Tilix CPU cost under the fixed `--fps 120` repaint workload; `perf stat` does not measure delivered display FPS. The capture machine's prior global setting was `enable-transparency=true` and was restored after testing. The optimized behavior is selected when users disable that unused transparency capability.

The A/B outputs are in `/tmp/tilix-ab-20261004/`; the source change is in `appwindow.d`, `session.d`, and `terminal.d`. Build and install succeeded. Before treating this as a general throughput claim, record delivered frame rate separately and validate the opaque UI visually; the current result establishes lower CPU work for the same requested repaint load.

## 4. Delivered FPS follow-up

The user reports seeing roughly 60–70 FPS in the demo with transparency support enabled and roughly 90–99 FPS after disabling it. These are useful observations but were not captured as controlled measurements. The agent's temporary `TILIX_RENDER_STATS=1` output counted Tilix GDK frame-clock ticks, not the demo's displayed FPS; its 14–18 values on some large-screen runs and 52.13 on a laptop-screen run are not valid substitutes. Exclude those values from performance claims.

A repeat on the large display reported 17.36 GDK ticks/s for the baseline and 17.82 for the optimized variant, which does not establish the user's reported demo-FPS change. The laptop-screen run is also excluded from the large-display comparison. A local launcher now offers `scripts/run-local-tilix.sh --mode baseline|optimized`; it selects modern mode for the default profile, toggles `enable-transparency`, and restores the prior global and profile values after the Tilix process exits. A 0% transparency slider does not disable this separate capability setting.

Keep this issue open until the next matched large-display A/B records the demo's own FPS for repeated runs and confirms the window is on the intended monitor. Capture Tilix CPU separately. The launcher was syntax/help checked only; its mode behavior and the user's displayed FPS still need direct verification.
