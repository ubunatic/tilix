# Tilix rendering and 4K performance investigation

## Status

This document records source review and a short local profile taken on 2026-10-04. It is an investigation, not a controlled benchmark. No before/after FPS result has been established for the recent damage-clip or badge-position changes.

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

## OpenGL setting experiment

The installed GTK 3 library recognizes `GDK_GL=always`; upstream GTK describes that value as forcing OpenGL rendering ([GTK change](https://mail.gnome.org/archives/commits-list/2014-November/msg00895.html)). This must be set before GTK starts, so it requires a new Tilix process. The machine's Mesa GLX information reported the AMD Radeon integrated GPU as accelerated.

A separate roughly 20-second profile with `GDK_GL=always` still showed Pixman `sse2_fill` at 53.41% of sampled cycles, alongside VTE processing and memory copies. The user measured this mode as slower. The two captures were not controlled or directly comparable, so their percentages do not quantify a speedup or slowdown. The observation is that forcing GDK's GL path did not remove VTE's Cairo/Pixman work and did not improve the user's probe result.

Do not recommend `GDK_GL=always` as a Tilix performance fix based on this evidence. GTK 3's `GDK_RENDERING=similar` is already the default; `GDK_RENDERING=image` explicitly disables GTK hardware acceleration. [GTK 3 runtime options](https://docs.gtk.org/gtk3/running.html).

## Benchmarking guidance

Performance claims need repeatable measurements. For an optimization, record the exact Tilix binary/revision, GTK/VTE versions, display/backend, window size, probe command, run duration, and FPS or CPU result. Compare before and after under the same setup, with repeated runs. A profiler's hottest symbol identifies where CPU samples landed; it does not prove that a particular source change improved FPS.

GTK 4 has GSK renderers for Cairo, OpenGL, and Vulkan, but moving Tilix to GTK 4 alone does not prove VTE's terminal content will be GPU-rendered. GTK 4 widgets can still add Cairo drawing nodes, and GTK documents `gtk_snapshot_append_cairo()` for custom drawing. Verify the GTK4 VTE rendering path and measure it before treating migration as a hardware-acceleration solution. [GSK renderer overview](https://gnome.pages.gitlab.gnome.org/gtk/gsk4/), [GTK 4 Cairo guidance](https://gnome.pages.gitlab.gnome.org/gtk/gtk4/question_index.html).
