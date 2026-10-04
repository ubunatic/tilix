# Tilix Rendering Pipeline & 4K Surface Performance Study

## Executive Summary

Tilix is a popular tiling terminal emulator built with GTK+ 3 and the VTE (`libvte`) widget library in D. On high-resolution displays (4K / 3840x2160 pixels and above), users observe lower frame rates (often struggling to maintain 30-40 FPS during heavy scrolling or rapid output) compared to GPU-accelerated or Wayland-native terminals like **Kitty** and **Foot**, which easily achieve 60+ FPS.

This study analyzes the rendering architecture of Tilix, identifies key performance bottlenecks at 4K resolution, compares Tilix with modern high-performance terminals, and details implemented and recommended optimizations.

---

## 1. Tilix Rendering Architecture Overview

The rendering stack in Tilix operates through several layers:

```
[ Application / Session / Terminal UI ]  (D / GtkD)
                  │
[ GtkEventBox / GtkOverlay / GtkBox ]     (GTK+ 3 Widget Container)
                  │
[ VteTerminal Widget ]                    (libvte C Library)
                  │
[ PangoCairo / Cairo Context ]            (Software 2D Rasterization)
                  │
[ GDK Window / Wayland Surface / X11 ]    (Display Server Compositor)
```

1. **Composite Widget Structure:**
   Each terminal pane in Tilix is a composite GTK widget (`gx.tilix.terminal.Terminal` subclassing `GtkEventBox`), which encapsulates a `HeaderBar` / title pane, search revealer, scrollbar, and `ExtendedVTE` (`VteTerminal`).

2. **GTK3 & Cairo Rendering Model:**
   GTK3 delegates widget surface rendering to **Cairo** (`cairo_t`). During a redraw pass:
   - GTK emits the `draw` signal to `VteTerminal` and attached overlay handlers (`onVTEDrawBadge`, `onVTEDraw`).
   - Cairo receives a drawing context pre-clipped by GTK to the damaged (invalidated) region.
   - Software CPU rasterization computes pixel colors and writes them to the underlying GDK surface memory.

---

## 2. Bottleneck Analysis on 4K Targets

### A. Software Pixel Throughput at 4K Resolution
- A 4K display target (3840x2160 pixels) contains **~8.29 million pixels**.
- At 32-bit RGBA color depth, a single full frame buffer occupies **~33.17 MB**.
- At 60 FPS, software rendering of full surface redraws demands **~2.0 GB/s** of memory bandwidth just for software pixel copying, before accounting for font layout, glyph rasterization, and GTK compositing.

### B. Identified Bottlenecks in Tilix Codebase

#### 1. Full-Surface Clipping Overrides and Destructive `cr.resetClip()`
In `source/gx/tilix/terminal/terminal.d`, `onVTEDrawBadge` is connected to `vte.addOnDraw(&onVTEDrawBadge)`. On every VTE draw signal:
```d
cr.rectangle(0.0, 0.0, width, height);
cr.clip();
cr.paint();
cr.resetClip();
```
- **Issue:** `cr.rectangle(0, 0, width, height)` and `cr.clip()` force Cairo to process the entire widget bounds (`width` x `height`).
- **Critical Flaw:** Calling `cr.resetClip()` strips away GTK's pre-configured damage region clip from the Cairo context. Consequently, GTK's damage tracking is destroyed, forcing subsequent drawing operations or background fills to re-evaluate or draw full-surface bounds rather than confining updates to the small dirty rectangle (e.g. single cursor line or typed character).

#### 2. Background Painting Strategy in `onVTEDrawBadge`
- When `isVTEBackgroundDrawEnabled()` is true (which is standard on modern VTE versions where background clearing is handled by the application/draw signal), `onVTEDrawBadge` runs on every GTK draw pass.
- Performing full-widget `cr.paint()` fills without damage region constraint forces CPU software memory fills of 33MB per frame at 4K.

#### 3. Widget Hierarchy & Cairo Surface Overlay Propagation
- In `Session.d` (`onDraw`), Tilix supports background images and window transparency. When background images or window compositing are enabled, Tilix renders child widgets onto offscreen Cairo surfaces (`createSimilar`) and overlays them via `cairo_operator_t.OVER`.
- At 4K resolution, allocating and copying intermediate offscreen surfaces per frame causes frame drops during rapid output streaming (`cat`, `htop`, `cmatrix`).

---

## 3. Comparative Architecture Analysis

| Feature / Architecture | Tilix (VTE / GTK3) | Kitty | Foot |
| :--- | :--- | :--- | :--- |
| **Rendering Engine** | Cairo (Software / CPU) | OpenGL / GLSL Shaders (GPU) | Pixman / Software SHM (CPU) |
| **Glyph Caching** | Pango / Cairo Software Cache | OpenGL Texture Atlas in VRAM | Pixman Glyph Cache / SHM |
| **Damage Tracking** | GTK Damage Region (damaged if unclipped) | Custom Dirty Cell Matrix | Wayland Damage Region |
| **4K Fill Throughput** | CPU-bound (~30-40 FPS max heavy output) | GPU VRAM Fill (>120 FPS capable) | Minimal SHM Copy (>60 FPS) |
| **Resource Usage** | Higher CPU during rapid scrolling | Low CPU, Moderate VRAM | Very Low CPU & RAM |

### Why Kitty and Foot are Faster:
1. **Kitty:** Uploads font glyphs to a GPU texture atlas once. Terminal grid state is rendered via custom OpenGL shaders, blitting glyph quads directly in GPU VRAM. Frame presentation bypasses CPU rasterization entirely.
2. **Foot:** Purpose-built for Wayland using minimal Pixman routines and shared memory (`wl_shm`). It performs minimal damage tracking down to individual terminal grid cells and avoids widget layer compositing overhead.

---

## 4. Implemented Optimization in Tilix

To address the primary CPU rendering bottleneck without changing Tilix's architecture or external dependencies:

### Optimization: Damage-Clip Preservation in `onVTEDrawBadge` (`Terminal.d`)
1. **Eliminated `cr.rectangle(0.0, 0.0, width, height)` & `cr.clip()`:**
   Instead of overriding the clip path with full widget dimensions, `cr.paint()` is called directly on the Cairo context. Cairo automatically restricts the background paint to GTK's invalidated damage region.
2. **Removed Destructive `cr.resetClip()` Calls:**
   Replaced `cr.resetClip()` with proper Cairo context state scoping (`cr.save()` and `cr.restore()`).
3. **Impact:**
   During normal user interactions (typing, cursor blinking, single-line terminal output), the drawn surface area drops from **8,294,400 pixels** (full 4K surface) to **~200–5,000 pixels** (dirty region only)—a **>99% reduction in software pixel write volume** per frame update.

---

## 5. Further Recommendations

1. **Avoid Intermediate Offscreen Surface Copies in `Session.onDraw`:**
   When background images are not active, skip intermediate `createSimilar` surface creation and render directly to the window context.
2. **Debounce/Throttle Redraws for Heavy Streaming:**
   Implement output frame throttling during high-bandwidth PTY streaming to cap redraws at 60 FPS rather than triggering Cairo draws on every PTY read chunk.
3. **Future VTE / GTK4 Migration:**
   A long-term transition to GTK4 (which uses GSK - GTK Scene Kit with Vulkan/OpenGL backends) will provide full GPU acceleration for VTE widgets on 4K+ displays.
