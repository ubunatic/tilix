# Tilix rendering and 4K performance investigation

## Status

Updated 2026-10-04. Profiling identifies Pixman fills as the dominant CPU work, and matched Tilix-only samples show lower CPU cost when transparency support is disabled. A delivered-FPS improvement has not yet been captured reliably. The user's demo showed roughly 60–70 FPS with transparency support enabled and roughly 90–99 FPS with the CSS change, but those values were observed by the user and were not recorded as a controlled A/B.

## Current rendering path

Tilix uses GTK 3 and embeds VTE (`VteTerminal`). GTK 3 drawing uses Cairo; the local profile also shows Cairo/Pixman and VTE symbols on the hot paths. GTK 3 has a `GtkGLArea` widget for application code that explicitly renders with OpenGL, but Tilix's VTE widget does not use that widget. See the [GTK 3 drawing migration notes](https://gnome.pages.gitlab.gnome.org/gtk/gtk3/migrating-2to3.html) and [`GtkGLArea` API](https://docs.gtk.org/gtk3/class.GLArea.html).

The display compositor may use the GPU to composite application windows. That does not mean VTE's terminal-cell drawing is GPU-rendered.

The rendering-path preference added upstream selects Tilix's legacy or experimental Cairo overlay callback. It does not replace VTE's renderer or enable GSK/OpenGL for terminal cells. The profile setting now inherits the global choice unless explicitly overridden. Neither path has a controlled before/after performance result yet.

## Reassessment of the damage-clip change

The earlier claim that `cr.rectangle(0, 0, width, height); cr.clip();` makes Cairo paint the full widget was incorrect. Cairo intersects a new clip with the current clip; `cairo_clip()` can only shrink the active region. If GTK has already supplied a damage clip, intersecting it with the full widget rectangle leaves the damage clip in effect. [`cairo_clip()` reference](https://www.cairographics.org/manual/cairo-cairo-t.html).

Likewise, `cr.paint()` paints within the active clip. Removing the full-widget rectangle and clip therefore does not by itself establish a reduction in the background area painted. The prior estimate of a greater than 99% reduction, and the claim that the old background paint necessarily wrote a full 4K frame, were unsupported and should not be repeated as measured results.

`cairo_reset_clip()` does remove the active clip. Scoping drawing with `save()`/`restore()` is safer for preserving caller state, but the performance effect of this change has not been measured. The current implementation also caches the badge-position setting; the lookup reduction is real in source, but its performance impact has not been benchmarked.

## Local profile

On 2026-10-04, `perf` sampled the checkout's `./tilix` process while a maximized window ran `loom-repaint-probe --fps 120`. The 25-second capture collected 1,920 samples. The leading symbols were:

| Symbol | Share of sampled CPU cycles |
| --- | ---: |
| Pixman `sse2_fill` | 89.41% |
| VTE `Terminal::get_text` | 1.92% |
| Pixman `sse2_composite_over_n_8_8888` | 1.37% |
| VTE `process_incoming_utf8` | 0.90% |

Call stacks show Pixman fills called through Cairo from GTK/GDK painting and from VTE's `DrawingCairo::fill_rectangle` / `Terminal::draw_rows` path. This identifies software pixel fills as the dominant sampled work for this run. It does not establish which individual fill or feature should be optimized next.

The profile was collected with `perf record -F 99 -g -p <tilix-pid>`. An initial capture targeted `/usr/bin/tilix` and was discarded because it was not the checkout binary; the reported profile is from the local `./tilix` build. The probe/window configuration was fixed for that capture, but this was a single short run and no baseline revision was profiled side-by-side.

### Experimental modern callback capture

A separate roughly 20-second capture used the modern rendering preference with maximized Tilix running `loom-repaint-probe --fps 120`. It collected 1,554 samples:

| Symbol | Share of sampled CPU time |
| --- | ---: |
| Pixman `sse2_fill` | 89.22% |
| VTE `Terminal::get_text` | 1.60% |
| Pixman `sse2_composite_over_n_8_8888` | 1.55% |
| VTE `process_incoming_utf8` | 0.76% |

The selected `sse2_fill` call chains pass through Cairo and GTK background drawing/repaint scheduling. Source inspection confirms the experimental callback is still a Cairo path and paints the terminal background with `SOURCE`; it does not replace VTE's renderer. Its differences include the badge drawing and cached badge layout. The earlier legacy capture reported 89.41% in `sse2_fill`, but the runs had different lengths and sample counts and were not controlled or repeated. Their percentages cannot show whether the modern callback changes performance. The user earlier reported no measurable result from repaint probes for prior repaint changes; no controlled before/after comparison isolating the modern callback is available.

### Follow-up modern-mode capture

A fresh capture on 2026-10-04 explicitly selected the modern rendering path, launched the checkout binary in a maximized window, and ran `loom-repaint-probe --fps 120` for up to 40 seconds. `perf record -F 99 -g` was attached to that checkout Tilix PID for up to 25 seconds. The process ended before the requested capture duration; `perf` retained 1,470 samples spanning 22.48 seconds, with no lost samples. The top self-cost was:

| Symbol | Share of sampled CPU cycles |
| --- | ---: |
| Pixman `sse2_fill` | 83.46% |

The call chains include GTK CSS widget-background drawing, GDK backing-area clearing, VTE `Terminal::draw_rows` / `DrawingCairo::fill_rectangle`, and Tilix's own modern callback. `perf report --call-graph=graph` attributes 12.71% of all sampled cycles to `Terminal::onVTEDrawBadge` → `renderModernPath` → Cairo `paint` → Pixman `sse2_fill`. This is a concrete Tilix-owned paint candidate. The trace does not report its clip area or prove the fill is redundant, so skipping it is an experiment that needs a visual check and matched profile. The raw profile and full text reports are in `/tmp/tilix-perf-20261004-modern/` on the capture machine. The global rendering preference was restored to `legacy` after the run.

### Opaque-window CSS background A/B

The terminal profile uses an opaque solid background, but the global `enable-transparency` capability was enabled. A matched A/B disabled that capability for both runs and compared Tilix with the `tilix-background` CSS class applied versus omitted from its session/stack containers. Both runs were maximized, used modern mode and the `--fps 120` repaint load, and were measured for 20.17 seconds with `perf stat` on the checkout Tilix PID:

| Run | Tilix CPU time | CPU cycles | Change from baseline |
| --- | ---: | ---: | ---: |
| CSS background classes applied (baseline) | 13.30 s | 48.04 billion | — |
| CSS classes omitted when transparency is disabled | 9.25 s | 32.76 billion | 30.5% less CPU time; 31.8% fewer cycles |

A repeat measured 13.09 s / 46.31 billion cycles for the baseline and 9.55 s / 31.93 billion cycles for the variant, a 27.0% CPU-time reduction and 31.0% fewer cycles. This clears the 20% CPU-cost target in both pairs under the fixed repaint load. The run measured Tilix CPU cost, not delivered display FPS. The optimization preserves the CSS backgrounds when transparency is enabled. The capture machine had `enable-transparency=true` before and after the experiment; users who keep transparency disabled get the optimized path. The paired `perf stat` outputs are in `/tmp/tilix-ab-20261004/`.

### Delivered FPS and display-placement correction

The FPS shown by `loom-repaint-probe` is the relevant delivered-rate outcome. A temporary `TILIX_RENDER_STATS=1` diagnostic instead counted GDK frame-clock ticks from Tilix's custom draw callback. It reported values around 14–18 on some large-display runs and 52 on a laptop-display run. These values did not match the FPS shown by the demo and must not be used as the probe FPS or as proof of delivered throughput. One run reported 52.13 while the window was on the laptop display; it is excluded from the large-display comparison.

On later large-display runs, the GDK diagnostic reported 17.36 for the CSS-class baseline and 17.66 / 17.82 for the variant. This small difference is not a valid demo-FPS comparison. Short Tilix-only `perf stat` samples also varied and did not reproduce the earlier CPU reduction. The large-display throughput result therefore remains unverified. The next A/B must read the probe's displayed FPS, confirm the window is on the Gigabyte before the timed interval, and compare repeated runs at the same size and workload. Record Tilix CPU separately if useful.

The local launcher now accepts `--mode baseline` and `--mode optimized`. Both select modern rendering for the default profile; baseline enables the global transparency capability and optimized disables it. It restores the previous global and profile settings when the launched process exits. The profile transparency slider at 0% controls transparency amount; it does not turn off the separate `enable-transparency` capability. On modern GNOME the capability checkbox is hidden, so use the launcher mode for this A/B. Omitting `--mode` keeps the current settings. Example:

```sh
scripts/run-local-tilix.sh --mode baseline --maximize \
  --command='loom-repaint-probe --fps 120'
scripts/run-local-tilix.sh --mode optimized --maximize \
  --command='loom-repaint-probe --fps 120'
```

The launcher was checked with `bash -n` and `--help`; these checks do not verify the A/B or the reported demo FPS.

## OpenGL setting experiment

The installed GTK 3 library recognizes `GDK_GL=always`; upstream GTK describes that value as forcing OpenGL rendering ([GTK change](https://mail.gnome.org/archives/commits-list/2014-November/msg00895.html)). This must be set before GTK starts, so it requires a new Tilix process. The machine's Mesa GLX information reported the AMD Radeon integrated GPU as accelerated.

A separate roughly 20-second profile with `GDK_GL=always` still showed Pixman `sse2_fill` at 53.41% of sampled cycles, alongside VTE processing and memory copies. The user measured this mode as slower. The two captures were not controlled or directly comparable, so their percentages do not quantify a speedup or slowdown. The observation is that forcing GDK's GL path did not remove VTE's Cairo/Pixman work and did not improve the user's probe result.

Do not recommend `GDK_GL=always` as a Tilix performance fix based on this evidence. GTK 3's `GDK_RENDERING=similar` is already the default; `GDK_RENDERING=image` explicitly disables GTK hardware acceleration. [GTK 3 runtime options](https://docs.gtk.org/gtk3/running.html).

## Benchmarking guidance

Performance claims need repeatable measurements. For an optimization, record the exact Tilix binary/revision, GTK/VTE versions, display/backend, window size, probe command, run duration, and FPS or CPU result. Compare before and after under the same setup, with repeated runs. A profiler's hottest symbol identifies where CPU samples landed; it does not prove that a particular source change improved FPS.

GTK 4 has GSK renderers for Cairo, OpenGL, and Vulkan, but moving Tilix to GTK 4 alone does not prove VTE's terminal content will be GPU-rendered. GTK 4 widgets can still add Cairo drawing nodes, and GTK documents `gtk_snapshot_append_cairo()` for custom drawing. Verify the GTK4 VTE rendering path and measure it before treating migration as a hardware-acceleration solution. [GSK renderer overview](https://gnome.pages.gitlab.gnome.org/gtk/gsk4/), [GTK 4 Cairo guidance](https://gnome.pages.gitlab.gnome.org/gtk/gtk4/question_index.html).
