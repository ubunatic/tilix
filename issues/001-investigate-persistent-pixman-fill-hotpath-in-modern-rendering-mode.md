# 001 — Investigate persistent Pixman fill hotpath in modern rendering mode

**Status**: Open
**Priority**: P2 (Medium)
**Severity**: Moderate
**Category**: Performance
**Related**: [Rendering pipeline study](../docs/studies/rendering_pipeline_4k.md), commit `302f4962`

---

## 1. Problem & Motivation

Tilix remains CPU-bound in Pixman while running the repaint probe in the experimental modern mode. A roughly 20-second `perf` capture of maximized Tilix running `loom-repaint-probe --fps 120` attributed 89.22% of sampled CPU time to Pixman `sse2_fill`. The call chain passes through Cairo into GTK background drawing and repaint scheduling. VTE `Terminal::get_text` was the next largest symbol at 1.60%.

An earlier legacy-mode capture attributed 89.41% to the same Pixman function. These runs were separate and do not establish a before/after difference. The modern preference selects an alternate Cairo overlay callback; it has not removed the dominant software fill work or produced a measurable improvement in the probe.

**Goal**: `/goal` Identify and address the dominant Pixman fill work in the modern-mode repaint workload, demonstrating a repeatable improvement against a controlled baseline, or document a concrete blocker and next experiment; stop and report if the workload or measurements cannot be reproduced.

## 2. Technical Specification / Findings

The modern-mode capture contained 1,554 samples. Other leading symbols were Pixman `sse2_composite_over_n_8_8888` (1.55%) and VTE `process_incoming_utf8` (0.76%). The legacy capture had 1,920 samples over about 25 seconds. Since capture lengths, sample counts, and runs differ, compare new measurements only after matching the binary revision, window/probe setup, and capture method. `GDK_GL=always` was reported slower by the user and is not an established fix.

## 3. Implementation & Verification Plan

Trace the fill call chain to identify avoidable work in Tilix, GTK, or VTE. If a change is warranted, compare repeated before/after runs with the same probe settings and record FPS plus profile data. If the work is outside Tilix or cannot be changed safely, document the evidence and a concrete next step.
