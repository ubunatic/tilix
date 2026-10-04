# Tilix: measuring the work behind a 4K terminal

Tilix is a tiling terminal emulator for Linux. It lets people arrange multiple VTE terminal sessions in split panes, move them between windows, save layouts, and tailor profiles. Its rendering stack combines GTK 3, GtkD, VTE, Cairo, and Pixman. The recent work began with a practical question: could the terminal feel smoother on a large 4K display, and could a rendering-path preference meaningfully improve it?

The investigation started with code changes aimed at reducing repaint work. One change preserved Cairo's damage clip instead of replacing it; another cached a badge-position preference in the draw loop. A later experiment added an optional “modern” callback for Tilix-owned drawing. The name could easily suggest a GPU renderer, but source inspection showed that it remained a Cairo callback and did not replace VTE's terminal-cell renderer. A follow-up fix made the preference inherit the global setting unless a profile explicitly overrides it.

The key episode was a correction to the performance story. An early explanation treated a rectangle covering the full widget as if it forced Cairo to paint the whole 4K surface. Reviewing Cairo's clipping rules showed the opposite: a new clip intersects the current clip, so it cannot expand GTK's existing damage region. The team corrected the study and withdrew the unsupported claim of a greater than 99% reduction. That mattered because an attractive explanation is not a measurement, even when the code change looks plausible.

Profiling then put Pixman's `sse2_fill` near the top of the sampled work in both legacy and experimental modes. Those captures were not controlled against each other, so their percentages could not demonstrate that the callback was faster. A more targeted experiment found that, with transparency capability disabled, omitting an opaque CSS background class reduced Tilix's CPU time by 30.5% in one matched pair and 27.0% in a repeat under the same repaint workload. This is a specific CPU-cost result; it does not establish a delivered frame-rate improvement. The study keeps those outcomes separate and leaves the large-display FPS comparison open.

That restraint is part of what makes the work useful. The experiment distinguishes the requested repaint rate from the frames the display actually presents, separates Tilix CPU cost from GDK frame-clock callbacks, and calls out a run on another display as unsuitable for the large-screen comparison. It also records that forcing GTK's OpenGL path did not remove the VTE Cairo/Pixman work and was reported slower by the user, without presenting unlike profiles as a controlled speed comparison.

The repository shows several forms of agentic development. Recent commits include two “Bolt” optimizations, a rendering-path feature, preference corrections, and a growing measurement study. Harnez was initialized with project rules, a study index, and an in-repository issue tracker. Ticket 001 captures the remaining Pixman investigation and its verification plan. The most instructive workflow here is not simply parallel implementation; it is keeping a durable record of what was measured, correcting an attractive but false assumption, and preserving the unanswered question for the next experiment.

This is a focused investigation in a mature application, rather than evidence that agents independently built Tilix. The recent work touches a small rendering area of a codebase with 61 tracked D source files and about 34,000 source lines. CI has Debian stable, Debian testing, Ubuntu, and DUB compiler jobs, while no test-named source files are tracked and the local Makefile test target is currently a placeholder. That gap makes it harder to reproduce a local verification path, and it is now recorded for follow-up.

## Facts

| Item | Verified detail |
|---|---|
| Stack | D, GTK 3, GtkD, VTE, Cairo/Pixman, DUB and Meson |
| Size | 259 tracked files; 61 D source files; approximately 34,000 source lines |
| Recent activity | 21 commits in the six weeks ending 2026-10-04; all dated 2026-10-04 |
| Evidence | Two matched CPU-cost pairs: 30.5% and 27.0% lower Tilix CPU time with opaque CSS background classes omitted |
| Limitation | The CPU experiment does not establish delivered FPS; that comparison remains open |
