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

## 3. Implementation & Verification Plan

Confirm the active draw callback and effective preference. Attribute fills to GTK, Tilix background drawing, and VTE, including call counts, clip area, absolute CPU cost, and achieved repaint rate (`--fps 120` is only the requested probe rate). Compare repeated runs with the same binary, window, probe update pattern, display, and library versions. If a background image is enabled, compare with it disabled and inspect the per-draw temporary surface and clip handling in `session.d`; if VTE row fills dominate, reproduce in a minimal VTE application. Count an optimization as successful only when matched runs exceed run-to-run variation and rendering remains correct; otherwise record the external blocker and next experiment.
