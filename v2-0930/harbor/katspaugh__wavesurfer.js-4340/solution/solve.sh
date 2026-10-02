#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/docs/RELEASE_NOTES-scope-refactor.md b/docs/RELEASE_NOTES-scope-refactor.md
new file mode 100644
--- /dev/null
+++ b/docs/RELEASE_NOTES-scope-refactor.md
@@ -0,0 +1,76 @@
+# Release notes: `refactor/scope-and-leak-fixes`
+
+Draft release-note bullets for the PR that merges this branch (based on `main` @ `ae8d3cd`,
+current package version `7.12.11`). Copy/trim into the changelog as needed.
+
+## Breaking changes
+
+- **`WaveSurfer` no longer exposes `protected subscriptions` / `protected mediaSubscriptions`.**
+  These per-instance disposer arrays were replaced by the new `Scope` disposal-tree primitive
+  (`this.scope`). Any subclass that pushed its own cleanup callbacks onto
+  `this.subscriptions`/`this.mediaSubscriptions` will fail to compile against this version's
+  TypeScript types (the fields no longer exist) and must migrate to `this.scope.add(disposer)`
+  instead. This is a source-level break for TypeScript subclasses; there is no runtime shim.
+
+- **Several internal modules are no longer emitted to `dist/`,** so deep imports through the
+  package's `./dist/*` wildcard export will now 404 / fail to resolve:
+  - `dist/draggable.js`
+  - `dist/reactive/event-stream-emitter.js`
+  - `dist/reactive/media-event-bridge.js`
+  - `dist/reactive/render-scheduler.js`
+  - `dist/reactive/state-event-emitter.js`
+
+  These were internal, unreferenced-in-source modules (verified via repo-wide grep before
+  deletion) that happened to be reachable only because `./dist/*` mechanically wildcard-matches
+  every file `tsc` compiles from `src/`, not because they were a curated public API. Anyone
+  importing one of these paths directly (outside the documented `.` and `./plugins/*` entry
+  points) needs to drop the import or reimplement the functionality locally.
+
+## Fixes
+
+- **`Spectrogram`'s `maxCanvasWidth` is now tracked per-instance instead of on a shared static.**
+  Previously, setting `maxCanvasWidth` on one Spectrogram instance mutated a class-level static
+  shared by every instance, so multiple spectrograms on a page (or a spectrogram created after
+  another with different options) could silently pick up the wrong value. Each instance now owns
+  its own value.
+
+- **Several events are now emitted exactly once instead of twice.** A previous internal
+  state -> event bridge caused `pause`, `seeking`, `finish`, and `timeupdate` (among others) to
+  double-fire under certain conditions; that bridge has been removed and events are now emitted
+  directly, exactly once per underlying occurrence. If application code was compensating for
+  double emission (e.g. dividing counts by two, deduplicating manually), that workaround is no
+  longer needed and should be removed.
+
+- **The WebAudio backend now emits an `error` event on load failure** instead of silently
+  swallowing it. Code using `backend: 'WebAudio'` that previously had no visibility into decode/
+  load failures can now listen for `wavesurfer.on('error', ...)`.
+
+- Various destroy-time and async-continuation leak fixes across plugins (record, spectrogram,
+  spectrogram-windowed, regions, envelope, timeline/hover, minimap) so that: recordings emit
+  their final blob even if `onstop` fires after `destroy()` returns without leaking a blob URL,
+  in-flight async work no longer touches DOM state after destroy, and duplicate/leftover event
+  listeners are cleaned up correctly. See individual commit messages on this branch for the
+  fix-by-fix detail.
+
+## New / documented internals
+
+- **New `Scope` primitive** (`src/scope.ts`): a disposal-tree ownership primitive used
+  throughout the codebase for listeners, timers, observers, signal subscriptions, and child
+  lifetimes. Disposing a `Scope` is idempotent, disposes children before its own disposers (LIFO
+  for its own), and any disposer added after disposal runs immediately instead of leaking. Every
+  `destroy()` in the codebase is now expressed as disposing a `Scope`. This replaced the old
+  per-class `subscriptions`/`mediaSubscriptions` disposer-array pattern (see breaking change
+  above).
+
+- **`computed()` in the reactive store is now always disposable.** Calling `.dispose()` on a
+  computed unsubscribes it from its dependencies so it stops recomputing; this is documented in
+  `src/reactive/README.md` alongside the `Scope` primitive and general reactive-system usage
+  guidance (subscribe/dispose discipline, `batch()`, auto-tracked vs. explicit dependencies).
+
+## Not breaking, but worth calling out for reviewers
+
+- `WaveSurfer.getState()`'s derived computeds (`isReady`, `progress`, `isPaused`, etc.) are
+  intentionally instance-lifetime-owned and are **not** disposed by `destroy()`/reused-`Scope`
+  cycles, so `getState()` keeps working correctly across a `destroy()` -> `load()` reuse (a
+  previously-supported pattern per issue #3637). See the comment at the
+  `createWaveSurferState()` call site in `src/wavesurfer.ts` for the reasoning.
diff --git a/src/base-plugin.ts b/src/base-plugin.ts
--- a/src/base-plugin.ts
+++ b/src/base-plugin.ts
@@ -14,6 +14,11 @@ export class BasePlugin<EventTypes extends BasePluginEvents, Options> extends Ev
   protected options: Options
   private isDestroyed = false
 
+  /** Whether destroy() has been called. Subclasses use this to guard async work. */
+  protected get destroyed(): boolean {
+    return this.isDestroyed
+  }
+
   /** Create a plugin instance */
   constructor(options: Options) {
     super()
@@ -27,22 +32,21 @@ export class BasePlugin<EventTypes extends BasePluginEvents, Options> extends Ev
 
   /** Do not call directly, only called by WavesSurfer internally */
   public _init(wavesurfer: WaveSurfer) {
-    // Reset state if plugin was previously destroyed
-    if (this.isDestroyed) {
-      this.subscriptions = []
-      this.isDestroyed = false
-    }
-
+    this.isDestroyed = false
     this.wavesurfer = wavesurfer
     this.onInit()
   }
 
   /** Destroy the plugin and unsubscribe from all events */
   public destroy() {
+    if (this.isDestroyed) return
+    this.isDestroyed = true
     this.emit('destroy')
     this.subscriptions.forEach((unsubscribe) => unsubscribe())
     this.subscriptions = []
-    this.isDestroyed = true
+    // Clear listeners registered BY consumers ON this plugin — after the
+    // destroy event so those consumers still receive it
+    this.unAll()
     this.wavesurfer = undefined
   }
 }
diff --git a/src/draggable.ts b/src/draggable.ts
deleted file mode 100644
--- a/src/draggable.ts
+++ /dev/null
@@ -1,136 +0,0 @@
-/**
- * @deprecated Use createDragStream from './reactive/drag-stream.js' instead.
- * This function is maintained for backward compatibility but will be removed in a future version.
- */
-export function makeDraggable(
-  element: HTMLElement | null,
-  onDrag: (dx: number, dy: number, x: number, y: number) => void,
-  onStart?: (x: number, y: number) => void,
-  onEnd?: (x: number, y: number) => void,
-  threshold = 3,
-  mouseButton = 0,
-  touchDelay = 100,
-): () => void {
-  if (!element) return () => void 0
-
-  const activePointers = new Map<number, PointerEvent>()
-  const isTouchDevice = matchMedia('(pointer: coarse)').matches
-
-  let unsubscribeDocument = () => void 0
-
-  const onPointerDown = (event: PointerEvent) => {
-    if (event.button !== mouseButton) return
-    if (activePointers.has(event.pointerId)) return
-
-    activePointers.set(event.pointerId, event)
-    if (activePointers.size > 1) {
-      return
-    }
-
-    const dragPointerId = event.pointerId
-    let startX = event.clientX
-    let startY = event.clientY
-    let isDragging = false
-    const touchStartTime = Date.now()
-
-    const onPointerMove = (event: PointerEvent) => {
-      if (event.pointerId !== dragPointerId) return
-      if (event.defaultPrevented || activePointers.size > 1) {
-        return
-      }
-
-      if (isTouchDevice && Date.now() - touchStartTime < touchDelay) return
-
-      const x = event.clientX
-      const y = event.clientY
-      const dx = x - startX
-      const dy = y - startY
-
-      if (isDragging || Math.abs(dx) > threshold || Math.abs(dy) > threshold) {
-        event.preventDefault()
-        event.stopPropagation()
-
-        const rect = element.getBoundingClientRect()
-        const { left, top } = rect
-
-        if (!isDragging) {
-          onStart?.(startX - left, startY - top)
-          isDragging = true
-        }
-
-        onDrag(dx, dy, x - left, y - top)
-
-        startX = x
-        startY = y
-      }
-    }
-
-    const onPointerUp = (event: PointerEvent) => {
-      // Only react to pointers that started on the element
-      if (!activePointers.delete(event.pointerId)) return
-
-      // Only the pointer that started the drag can end it
-      if (event.pointerId === dragPointerId && isDragging) {
-        const x = event.clientX
-        const y = event.clientY
-        const rect = element.getBoundingClientRect()
-        const { left, top } = rect
-
-        onEnd?.(x - left, y - top)
-      }
-
-      // Keep listening until all pointers are released
-      if (activePointers.size === 0) {
-        unsubscribeDocument()
-      }
-    }
-
-    const onPointerLeave = (e: PointerEvent) => {
-      if (!e.relatedTarget || e.relatedTarget === document.documentElement) {
-        onPointerUp(e)
-      }
-    }
-
-    const onClick = (event: MouseEvent) => {
-      if (isDragging) {
-        event.stopPropagation()
-        event.preventDefault()
-      }
-    }
-
-    const onTouchMove = (event: TouchEvent) => {
-      if (event.defaultPrevented || activePointers.size > 1) {
-        return
-      }
-      if (isDragging) {
-        event.preventDefault()
-      }
-    }
-
-    document.addEventListener('pointermove', onPointerMove)
-    document.addEventListener('pointerup', onPointerUp)
-    document.addEventListener('pointerout', onPointerLeave)
-    document.addEventListener('pointercancel', onPointerLeave)
-    document.addEventListener('touchmove', onTouchMove, { passive: false })
-    document.addEventListener('click', onClick, { capture: true })
-
-    unsubscribeDocument = () => {
-      document.removeEventListener('pointermove', onPointerMove)
-      document.removeEventListener('pointerup', onPointerUp)
-      document.removeEventListener('pointerout', onPointerLeave)
-      document.removeEventListener('pointercancel', onPointerLeave)
-      document.removeEventListener('touchmove', onTouchMove)
-      setTimeout(() => {
-        document.removeEventListener('click', onClick, { capture: true })
-      }, 10)
-    }
-  }
-
-  element.addEventListener('pointerdown', onPointerDown)
-
-  return () => {
-    unsubscribeDocument()
-    element.removeEventListener('pointerdown', onPointerDown)
-    activePointers.clear()
-  }
-}
diff --git a/src/player.ts b/src/player.ts
--- a/src/player.ts
+++ b/src/player.ts
@@ -1,5 +1,6 @@
 import EventEmitter, { type GeneralEventTypes } from './event-emitter.js'
 import { signal, type WritableSignal } from './reactive/store.js'
+import { Scope } from './scope.js'
 
 type PlayerOptions = {
   media?: HTMLMediaElement
@@ -21,7 +22,18 @@ class Player<T extends GeneralEventTypes> extends EventEmitter<T> {
   private _muted: WritableSignal<boolean>
   private _playbackRate: WritableSignal<number>
   private _seeking: WritableSignal<boolean>
-  private reactiveMediaEventCleanups: Array<() => void> = []
+  // Note: Player has no separate "root" scope of its own -- mediaScope IS its
+  // whole ownership tree. (A wrapper root named `scope`, as a plain mechanical
+  // reading of the plan might suggest, would collide with WaveSurfer's own
+  // `scope` field of the same name: TS rejects two classes in an extends
+  // chain declaring a same-named field with different visibility (TS2415),
+  // and even reconciling visibility wouldn't help since it's a single
+  // storage slot per instance -- WaveSurfer's field initializer would run
+  // after Player's and silently stomp the reference Player already captured
+  // for mediaScope's parent. Keeping Player's and WaveSurfer's scopes as two
+  // independent trees also matches their pre-existing independence: neither
+  // class's cleanup array was ever connected to the other's.)
+  private mediaScope = new Scope()
 
   // Expose reactive state as writable signals
   // These are writable to allow WaveSurfer to compose them into centralized state
@@ -97,66 +109,66 @@ class Player<T extends GeneralEventTypes> extends EventEmitter<T> {
    */
   private setupReactiveMediaEvents() {
     // Playing state
-    this.reactiveMediaEventCleanups.push(
+    this.mediaScope.add(
       this.onMediaEvent('play', () => {
         this._isPlaying.set(true)
       }),
     )
 
-    this.reactiveMediaEventCleanups.push(
+    this.mediaScope.add(
       this.onMediaEvent('pause', () => {
         this._isPlaying.set(false)
       }),
     )
 
-    this.reactiveMediaEventCleanups.push(
+    this.mediaScope.add(
       this.onMediaEvent('ended', () => {
         this._isPlaying.set(false)
       }),
     )
 
     // Time tracking
-    this.reactiveMediaEventCleanups.push(
+    this.mediaScope.add(
       this.onMediaEvent('timeupdate', () => {
         this._currentTime.set(this.media.currentTime)
       }),
     )
 
-    this.reactiveMediaEventCleanups.push(
+    this.mediaScope.add(
       this.onMediaEvent('durationchange', () => {
         this._duration.set(this.media.duration || 0)
       }),
     )
 
-    this.reactiveMediaEventCleanups.push(
+    this.mediaScope.add(
       this.onMediaEvent('loadedmetadata', () => {
         this._duration.set(this.media.duration || 0)
       }),
     )
 
     // Seeking state
-    this.reactiveMediaEventCleanups.push(
+    this.mediaScope.add(
       this.onMediaEvent('seeking', () => {
         this._seeking.set(true)
       }),
     )
 
-    this.reactiveMediaEventCleanups.push(
+    this.mediaScope.add(
       this.onMediaEvent('seeked', () => {
         this._seeking.set(false)
       }),
     )
 
     // Volume and muted
-    this.reactiveMediaEventCleanups.push(
+    this.mediaScope.add(
       this.onMediaEvent('volumechange', () => {
         this._volume.set(this.media.volume)
         this._muted.set(this.media.muted)
       }),
     )
 
     // Playback rate
-    this.reactiveMediaEventCleanups.push(
+    this.mediaScope.add(
       this.onMediaEvent('ratechange', () => {
         this._playbackRate.set(this.media.playbackRate)
       }),
@@ -216,8 +228,15 @@ class Player<T extends GeneralEventTypes> extends EventEmitter<T> {
 
   protected destroy() {
     // Cleanup reactive media event listeners
-    this.reactiveMediaEventCleanups.forEach((cleanup) => cleanup())
-    this.reactiveMediaEventCleanups = []
+    this.mediaScope.dispose()
+    // Player instances are reused after destroy (see WaveSurfer's loadAudio
+    // comment about issue #3637). setMediaElement() already disposes and
+    // replaces mediaScope unconditionally at its own start, so this isn't
+    // strictly required for that path -- it's here for consistency /
+    // defensiveness, so a destroyed-but-reused Player is never left holding
+    // a disposed scope that would silently no-op (or immediately re-run)
+    // anything registered on it before setMediaElement() is called again.
+    this.mediaScope = new Scope()
 
     // Revoke blob URLs that we created
     this.revokeSrc()
@@ -236,8 +255,8 @@ class Player<T extends GeneralEventTypes> extends EventEmitter<T> {
 
   protected setMediaElement(element: HTMLMediaElement) {
     // Cleanup reactive event listeners from old media element
-    this.reactiveMediaEventCleanups.forEach((cleanup) => cleanup())
-    this.reactiveMediaEventCleanups = []
+    this.mediaScope.dispose()
+    this.mediaScope = new Scope()
 
     // Set new media element
     this.media = element
diff --git a/src/plugins/envelope.ts b/src/plugins/envelope.ts
--- a/src/plugins/envelope.ts
+++ b/src/plugins/envelope.ts
@@ -57,6 +57,7 @@ class Polyline extends EventEmitter<{
     }
   >
   private subscriptions: (() => void)[] = []
+  private pointCleanups = new Map<EnvelopePoint, () => void>()
   private dblClickListener?: (e: MouseEvent) => void
   private touchStartListener?: (e: TouchEvent) => void
   private touchMoveListener?: () => void
@@ -183,7 +184,7 @@ class Polyline extends EventEmitter<{
     svg.addEventListener('touchend', this.touchEndListener)
   }
 
-  private makeDraggable(draggable: SVGElement, onDrag: (x: number, y: number) => void) {
+  private makeDraggable(draggable: SVGElement, onDrag: (x: number, y: number) => void): () => void {
     const dragStream = createDragStream(draggable as unknown as HTMLElement, { threshold: 1 })
 
     const unsubscribe = effect(() => {
@@ -199,10 +200,10 @@ class Polyline extends EventEmitter<{
       }
     }, [dragStream.signal])
 
-    this.subscriptions.push(() => {
+    return () => {
       unsubscribe()
       dragStream.cleanup()
-    })
+    }
   }
 
   private createCircle(x: number, y: number) {
@@ -238,6 +239,12 @@ class Polyline extends EventEmitter<{
     points.removeItem(index)
     circle.remove()
     this.polyPoints.delete(point)
+
+    const cleanup = this.pointCleanups.get(point)
+    if (cleanup) {
+      cleanup()
+      this.pointCleanups.delete(point)
+    }
   }
 
   addPolyPoint(relX: number, relY: number, refPoint: EnvelopePoint) {
@@ -258,7 +265,7 @@ class Polyline extends EventEmitter<{
 
     this.polyPoints.set(refPoint, { polyPoint: newPoint, circle })
 
-    this.makeDraggable(circle, (dx, dy) => {
+    const cleanup = this.makeDraggable(circle, (dx, dy) => {
       const newX = newPoint.x + dx
       const newY = newPoint.y + dy
 
@@ -284,6 +291,8 @@ class Polyline extends EventEmitter<{
       // Emit the event passing the point and new relative coordinates
       this.emit('point-move', refPoint, newX / width, newY / height)
     })
+
+    this.pointCleanups.set(refPoint, cleanup)
   }
 
   update() {
@@ -333,8 +342,14 @@ class Polyline extends EventEmitter<{
     }
 
     this.subscriptions.forEach((unsubscribe) => unsubscribe())
+    this.subscriptions = []
+
+    this.pointCleanups.forEach((cleanup) => cleanup())
+    this.pointCleanups.clear()
+
     this.polyPoints.clear()
     this.svg.remove()
+    this.unAll()
   }
 }
 
@@ -343,6 +358,7 @@ const randomId = () => Math.random().toString(36).slice(2)
 class EnvelopePlugin extends BasePlugin<EnvelopePluginEvents, EnvelopePluginOptions> {
   protected options: Options
   private polyline: Polyline | null = null
+  private polylineSubscriptions: Array<() => void> = []
   private points: EnvelopePoint[]
   private throttleTimeout: ReturnType<typeof setTimeout> | null = null
   private volume = 1
@@ -422,6 +438,9 @@ class EnvelopePlugin extends BasePlugin<EnvelopePluginEvents, EnvelopePluginOpti
       this.throttleTimeout = null
     }
 
+    this.polylineSubscriptions.forEach((unsubscribe) => unsubscribe())
+    this.polylineSubscriptions = []
+
     this.polyline?.destroy()
     super.destroy()
   }
@@ -481,14 +500,19 @@ class EnvelopePlugin extends BasePlugin<EnvelopePluginEvents, EnvelopePluginOpti
   }
 
   private initPolyline() {
+    // Drop the previous polyline's listeners before replacing it, instead of
+    // accumulating a fresh set of 4 on every decode.
+    this.polylineSubscriptions.forEach((unsubscribe) => unsubscribe())
+    this.polylineSubscriptions = []
+
     if (this.polyline) this.polyline.destroy()
     if (!this.wavesurfer) return
 
     const wrapper = this.wavesurfer.getWrapper()
 
     this.polyline = new Polyline(this.options, wrapper)
 
-    this.subscriptions.push(
+    this.polylineSubscriptions.push(
       this.polyline.on('point-move', (point, relativeX, relativeY) => {
         const duration = this.wavesurfer?.getDuration() || 0
         point.time = relativeX * duration
diff --git a/src/plugins/hover.ts b/src/plugins/hover.ts
--- a/src/plugins/hover.ts
+++ b/src/plugins/hover.ts
@@ -57,6 +57,7 @@ class HoverPlugin extends BasePlugin<HoverPluginEvents, HoverPluginOptions> {
   private lastPointerPosition: { clientX: number; clientY: number } | null = null
   private isPointerOverWaveform = false
   private streamCleanups: Array<() => void> = []
+  private transitionEndCleanup: (() => void) | null = null
 
   constructor(options?: HoverPluginOptions) {
     super(options || {})
@@ -175,18 +176,26 @@ class HoverPlugin extends BasePlugin<HoverPluginEvents, HoverPluginOptions> {
         this.wrapper.style.opacity = '0'
         this.isPointerOverWaveform = false
         this.lastPointerPosition = null
+
+        // Remove any previously attached transitionend listener before attaching a
+        // new one, so listeners don't accumulate if the transition never fires
+        // (e.g. element hidden or opacity already 0).
+        if (this.transitionEndCleanup) {
+          this.transitionEndCleanup()
+          this.transitionEndCleanup = null
+        }
+
         // Reset transform after the opacity fade so the line doesn't jump to position 0
         // while still visible. Also resets the scrollable overflow area of the scroll
         // container to prevent improper scrollLeft clamping on zoom changes.
-        this.wrapper.addEventListener(
-          'transitionend',
-          () => {
-            if (!this.isPointerOverWaveform) {
-              this.wrapper.style.transform = ''
-            }
-          },
-          { once: true },
-        )
+        const onTransitionEnd = () => {
+          this.transitionEndCleanup = null
+          if (!this.isPointerOverWaveform) {
+            this.wrapper.style.transform = ''
+          }
+        }
+        this.wrapper.addEventListener('transitionend', onTransitionEnd, { once: true })
+        this.transitionEndCleanup = () => this.wrapper.removeEventListener('transitionend', onTransitionEnd)
       }, [pointerLeave]),
     )
 
@@ -217,6 +226,10 @@ class HoverPlugin extends BasePlugin<HoverPluginEvents, HoverPluginOptions> {
 
   /** Unmount */
   public destroy() {
+    if (this.transitionEndCleanup) {
+      this.transitionEndCleanup()
+      this.transitionEndCleanup = null
+    }
     this.streamCleanups.forEach((fn) => fn())
     this.streamCleanups = []
     super.destroy()
diff --git a/src/plugins/minimap.ts b/src/plugins/minimap.ts
--- a/src/plugins/minimap.ts
+++ b/src/plugins/minimap.ts
@@ -256,9 +256,9 @@ class MinimapPlugin extends BasePlugin<MinimapPluginEvents, MinimapPluginOptions
   private destroyMinimap() {
     const miniWavesurfer = this.miniWavesurfer
     this.miniWavesurfer = null
-    miniWavesurfer?.destroy()
     this.miniSubscriptions.forEach((unsubscribe) => unsubscribe())
     this.miniSubscriptions = []
+    miniWavesurfer?.destroy()
 
     if (this.dragTimeout) {
       clearTimeout(this.dragTimeout)
diff --git a/src/plugins/record.ts b/src/plugins/record.ts
--- a/src/plugins/record.ts
+++ b/src/plugins/record.ts
@@ -68,6 +68,11 @@ class RecordPlugin extends BasePlugin<RecordPluginEvents, RecordPluginOptions> {
   private unsubscribeDestroy?: () => void
   private unsubscribeRecordEnd?: () => void
   private recordedBlobUrl: string | null = null
+  // Snapshot of 'record-end' listeners taken at destroy() time when a recording is
+  // still active. MediaRecorder.stop() fires 'onstop' via a queued task (async), so
+  // by the time it runs, super.destroy() may have already cleared listeners via
+  // unAll(); this lets the final blob still reach whoever was listening.
+  private pendingFinalRecordEndListeners: Set<(...args: unknown[]) => void> | null = null
 
   /** Create an instance of the Record plugin */
   constructor(options: RecordPluginOptions) {
@@ -82,7 +87,9 @@ class RecordPlugin extends BasePlugin<RecordPluginEvents, RecordPluginOptions> {
     })
 
     this.timer = new Timer()
+  }
 
+  protected onInit() {
     this.subscriptions.push(
       this.timer.on('tick', () => {
         const currentTime = performance.now() - this.lastStartTime
@@ -250,6 +257,8 @@ class RecordPlugin extends BasePlugin<RecordPluginEvents, RecordPluginOptions> {
 
     const micStream = this.renderMicStream(stream)
     this.micStream = micStream
+    // Safety net: cleans up mic resources if 'destroy' fires before stopMic() runs
+    // (stopMic() normally unsubscribes this first, making the common path a no-op).
     this.unsubscribeDestroy = this.once('destroy', micStream.onDestroy)
     this.unsubscribeRecordEnd = this.once('record-end', micStream.onEnd)
     this.stream = stream
@@ -296,7 +305,28 @@ class RecordPlugin extends BasePlugin<RecordPluginEvents, RecordPluginOptions> {
     const emitWithBlob = (ev: 'record-pause' | 'record-end') => {
       const blob = new Blob(recordedChunks, { type: mediaRecorder.mimeType })
       this.emit(ev, blob)
-      if (this.options.renderRecordedAudio) {
+      if (ev === 'record-end' && this.pendingFinalRecordEndListeners) {
+        const snapshot = this.pendingFinalRecordEndListeners
+        this.pendingFinalRecordEndListeners = null
+        // Only redeliver here if the plugin has already fully torn down (unAll ran) —
+        // otherwise this.emit(ev, blob) above already reached these listeners live,
+        // and redelivering would double-fire them.
+        if (this.destroyed) {
+          snapshot.forEach((listener) => {
+            try {
+              listener(blob)
+            } catch (err) {
+              console.error('Error in record-end listener during destroy teardown:', err)
+            }
+          })
+        }
+      }
+      // Guard against onstop firing after destroy() has already run (it's a queued
+      // microtask, so it can land after destroy() returns -- see the test above).
+      // Without this, a post-destroy onstop would create a fresh blob URL via
+      // createObjectURL() that nothing ever revokes, since destroy() has already
+      // done its own revocation pass and this code path runs after that.
+      if (this.options.renderRecordedAudio && !this.destroyed) {
         this.applyOriginalOptionsIfNeeded()
         // Revoke previous blob URL before creating a new one
         if (this.recordedBlobUrl) {
@@ -383,14 +413,31 @@ class RecordPlugin extends BasePlugin<RecordPluginEvents, RecordPluginOptions> {
   /** Destroy the plugin */
   public destroy() {
     this.applyOriginalOptionsIfNeeded()
-    super.destroy()
+
+    // If a recording is still active, MediaRecorder.stop() below will fire 'onstop'
+    // asynchronously (a queued task) — after this synchronous destroy() call (and
+    // its super.destroy()) has already returned and cleared listeners via unAll().
+    // Snapshot the current 'record-end' listeners now, while they're still live, so
+    // emitWithBlob() can still deliver the final blob to them later.
+    if (this.mediaRecorder && (this.mediaRecorder.state === 'recording' || this.mediaRecorder.state === 'paused')) {
+      // Reaching into EventEmitter's private `listeners` map is an intentional escape
+      // hatch: it's the only way to preserve delivery across the async onstop boundary.
+      const listeners = (this as unknown as { listeners?: Record<string, Set<(...args: unknown[]) => void>> })
+        .listeners?.['record-end']
+      this.pendingFinalRecordEndListeners = listeners ? new Set(listeners) : null
+    }
+
+    // Stop recording/mic first so any resulting 'record-end' reaches
+    // listeners before super.destroy() clears them (unAll).
     this.stopRecording()
     this.stopMic()
+    this.timer.destroy()
     // Revoke blob URL to free memory
     if (this.recordedBlobUrl) {
       URL.revokeObjectURL(this.recordedBlobUrl)
       this.recordedBlobUrl = null
     }
+    super.destroy()
   }
 
   private applyOriginalOptionsIfNeeded() {
diff --git a/src/plugins/regions.ts b/src/plugins/regions.ts
--- a/src/plugins/regions.ts
+++ b/src/plugins/regions.ts
@@ -108,6 +108,9 @@ class SingleRegion extends EventEmitter<RegionEvents> implements Region {
   public isRemoved = false
   private contentClickListener?: (e: MouseEvent) => void
   private contentBlurListener?: () => void
+  private resizeHandleCleanup: (() => void) | null = null
+  /** True once initMouseEvents has run; controls whether setContent must (re)attach listeners itself */
+  private mouseEventsInitialized = false
 
   constructor(
     params: RegionParams,
@@ -210,15 +213,24 @@ class SingleRegion extends EventEmitter<RegionEvents> implements Region {
       }
     }, [rightDragStream.signal])
 
-    this.subscriptions.push(() => {
+    const cleanup = () => {
       unsubscribeLeft()
       unsubscribeRight()
       leftDragStream.cleanup()
       rightDragStream.cleanup()
-    })
+    }
+
+    this.resizeHandleCleanup = cleanup
+    this.subscriptions.push(cleanup)
   }
 
   private removeResizeHandles(element: HTMLElement) {
+    if (this.resizeHandleCleanup) {
+      this.resizeHandleCleanup()
+      this.subscriptions = this.subscriptions.filter((sub) => sub !== this.resizeHandleCleanup)
+      this.resizeHandleCleanup = null
+    }
+
     const leftHandle = element.querySelector('[part*="region-handle-left"]')
     const rightHandle = element.querySelector('[part*="region-handle-right"]')
     if (leftHandle) {
@@ -278,6 +290,32 @@ class SingleRegion extends EventEmitter<RegionEvents> implements Region {
     this.element.style.cursor = toggle ? 'grabbing' : 'grab'
   }
 
+  /** Attach the content click/blur listeners, first removing any existing pair */
+  private attachContentListeners() {
+    this.detachContentListeners()
+
+    if (!this.contentEditable || !this.content) return
+
+    this.contentClickListener = (e) => this.onContentClick(e)
+    this.contentBlurListener = () => this.onContentBlur()
+    this.content.addEventListener('click', this.contentClickListener)
+    this.content.addEventListener('blur', this.contentBlurListener)
+  }
+
+  /** Remove the content click/blur listeners, if attached */
+  private detachContentListeners() {
+    if (!this.content) return
+
+    if (this.contentClickListener) {
+      this.content.removeEventListener('click', this.contentClickListener)
+      this.contentClickListener = undefined
+    }
+    if (this.contentBlurListener) {
+      this.content.removeEventListener('blur', this.contentBlurListener)
+      this.contentBlurListener = undefined
+    }
+  }
+
   private initMouseEvents() {
     const { element } = this
     if (!element) return
@@ -336,12 +374,8 @@ class SingleRegion extends EventEmitter<RegionEvents> implements Region {
       dragStream.cleanup()
     })
 
-    if (this.contentEditable && this.content) {
-      this.contentClickListener = (e) => this.onContentClick(e)
-      this.contentBlurListener = () => this.onContentBlur()
-      this.content.addEventListener('click', this.contentClickListener)
-      this.content.addEventListener('blur', this.contentBlurListener)
-    }
+    this.attachContentListeners()
+    this.mouseEventsInitialized = true
   }
 
   public _onUpdate(dx: number, side?: UpdateSide, startTime?: number) {
@@ -431,14 +465,7 @@ class SingleRegion extends EventEmitter<RegionEvents> implements Region {
     if (!this.element) return
 
     // Remove event listeners from old content before removing it
-    if (this.content && this.contentEditable) {
-      if (this.contentClickListener) {
-        this.content.removeEventListener('click', this.contentClickListener)
-      }
-      if (this.contentBlurListener) {
-        this.content.removeEventListener('blur', this.contentBlurListener)
-      }
-    }
+    this.detachContentListeners()
 
     this.content?.remove()
     if (!content) {
@@ -459,11 +486,11 @@ class SingleRegion extends EventEmitter<RegionEvents> implements Region {
     }
     if (this.contentEditable) {
       this.content.contentEditable = 'true'
-      // Re-add event listeners to new content
-      this.contentClickListener = (e) => this.onContentClick(e)
-      this.contentBlurListener = () => this.onContentBlur()
-      this.content.addEventListener('click', this.contentClickListener)
-      this.content.addEventListener('blur', this.contentBlurListener)
+      // Only (re)attach here when replacing content at runtime -- during construction,
+      // initMouseEvents() runs right after setContent() and is the single attachment point.
+      if (this.mouseEventsInitialized) {
+        this.attachContentListeners()
+      }
     }
     this.content.setAttribute('part', 'region-content')
     this.element.appendChild(this.content)
@@ -535,16 +562,7 @@ class SingleRegion extends EventEmitter<RegionEvents> implements Region {
     this.subscriptions = []
 
     // Clean up content event listeners
-    if (this.content && this.contentEditable) {
-      if (this.contentClickListener) {
-        this.content.removeEventListener('click', this.contentClickListener)
-        this.contentClickListener = undefined
-      }
-      if (this.contentBlurListener) {
-        this.content.removeEventListener('blur', this.contentBlurListener)
-        this.contentBlurListener = undefined
-      }
-    }
+    this.detachContentListeners()
 
     // Remove DOM element
     if (this.element) {
@@ -894,10 +912,17 @@ class RegionsPlugin extends BasePlugin<RegionsPluginEvents, RegionsPluginOptions
       }
     }, [dragStream.signal])
 
-    return () => {
+    const cleanup = () => {
       unsubscribe()
       dragStream.cleanup()
     }
+
+    this.subscriptions.push(cleanup)
+
+    return () => {
+      cleanup()
+      this.subscriptions = this.subscriptions.filter((sub) => sub !== cleanup)
+    }
   }
 
   /** Remove all regions */
diff --git a/src/plugins/spectrogram-windowed.ts b/src/plugins/spectrogram-windowed.ts
--- a/src/plugins/spectrogram-windowed.ts
+++ b/src/plugins/spectrogram-windowed.ts
@@ -163,6 +163,10 @@ class WindowedSpectrogramPlugin extends BasePlugin<WindowedSpectrogramPluginEven
   private pixelsPerSecond = 0
   private isRendering = false
   private renderTimeout: number | null = null
+  private initialRenderTimeout: number | null = null
+  // Cap on how many frequency segments are kept in memory/DOM at once; segments farthest
+  // from the current view are evicted once this is exceeded (see evictDistantSegments)
+  private maxRetainedSegments = 48
 
   // FFT and processing
   private fft: FFT | null = null
@@ -397,8 +401,11 @@ class WindowedSpectrogramPlugin extends BasePlugin<WindowedSpectrogramPluginEven
     // This ensures the spectrogram appears even if no redraw event is fired
     if (this.wavesurfer.getDecodedData()) {
       // Use setTimeout to ensure DOM is fully ready
-      setTimeout(() => {
-        this.render(this.wavesurfer.getDecodedData())
+      this.initialRenderTimeout = window.setTimeout(() => {
+        this.initialRenderTimeout = null
+        const decodedData = this.wavesurfer?.getDecodedData()
+        if (!decodedData) return
+        this.render(decodedData)
       }, 0)
     }
   }
@@ -524,6 +531,7 @@ class WindowedSpectrogramPlugin extends BasePlugin<WindowedSpectrogramPluginEven
     for (const segment of visibleSegments) {
       if (segment.canvas) {
         await this.renderSegment(segment)
+        if (this.destroyed) return
       }
     }
   }
@@ -640,13 +648,35 @@ class WindowedSpectrogramPlugin extends BasePlugin<WindowedSpectrogramPluginEven
 
       // Generate segments for this window
       await this.generateSegments(windowStartTime, windowEndTime)
+      if (this.destroyed) return
 
-      // Don't clean up old segments - keep them all in memory for performance
+      // Evict segments far from the current view so memory stays bounded regardless
+      // of audio length, instead of keeping every segment ever rendered
+      this.evictDistantSegments(this.getCurrentViewMidpoint() ?? (windowStartTime + windowEndTime) / 2)
     } finally {
       this.isRendering = false
     }
   }
 
+  /**
+   * Midpoint (in seconds) of the currently visible viewport, using the same scroll/viewport/
+   * zoom sources as renderVisibleWindow. Returns null when there's no wavesurfer wrapper or
+   * buffered audio yet, so callers have nothing sensible to anchor eviction on.
+   */
+  private getCurrentViewMidpoint(): number | null {
+    const wrapper = this.wavesurfer?.getWrapper()
+    if (!wrapper || !this.buffer) return null
+
+    const scrollLeft = this.getScrollLeft(wrapper)
+    const viewportWidth = this.getViewportWidth(wrapper)
+    const pixelsPerSec = this.getPixelsPerSecond()
+    if (!pixelsPerSec) return null
+
+    const visibleStartTime = scrollLeft / pixelsPerSec
+    const visibleEndTime = (scrollLeft + viewportWidth) / pixelsPerSec
+    return (visibleStartTime + visibleEndTime) / 2
+  }
+
   private async generateSegments(startTime: number, endTime: number) {
     if (!this.buffer) return
 
@@ -712,6 +742,7 @@ class WindowedSpectrogramPlugin extends BasePlugin<WindowedSpectrogramPluginEven
         // Calculate frequency data for this segment
         const freqStartTime = performance.now()
         const frequencies = await this.calculateFrequencies(segmentStart, segmentEnd)
+        if (this.destroyed) return
         const freqEndTime = performance.now()
 
         if (frequencies && frequencies.length > 0) {
@@ -728,6 +759,7 @@ class WindowedSpectrogramPlugin extends BasePlugin<WindowedSpectrogramPluginEven
           // Render this segment
           const renderStartTime = performance.now()
           await this.renderSegment(segment)
+          if (this.destroyed) return
           const renderEndTime = performance.now()
 
           // Emit progress update
@@ -826,6 +858,17 @@ class WindowedSpectrogramPlugin extends BasePlugin<WindowedSpectrogramPluginEven
       }
     }
 
+    // Re-check after the await: destroy() or stopProgressiveLoading() may have run
+    // while we were awaiting, and must not be undone by re-arming the timer below
+    if (this.destroyed || !this.isProgressiveLoading) return
+
+    // Background loading has no renderVisibleWindow to enforce the cap, so evict here too -
+    // anchored on the current view (not the segment we just loaded) so background fill
+    // doesn't push out segments near what the user is actually looking at; fall back to the
+    // freshly loaded segment's own midpoint only when there's no view to anchor on (e.g. no
+    // wavesurfer wrapper yet)
+    this.evictDistantSegments(this.getCurrentViewMidpoint() ?? (segmentStart + segmentEnd) / 2)
+
     // Move to next segment
     this.nextProgressiveSegmentTime = segmentEnd
 
@@ -1081,8 +1124,11 @@ class WindowedSpectrogramPlugin extends BasePlugin<WindowedSpectrogramPluginEven
         freqMin,
         freqMax,
       )
+      if (this.destroyed) return
     }
 
+    if (!this.canvasContainer) return
+
     // Remove old canvas if this segment was previously rendered
     if (segment.canvas) {
       segment.canvas.remove()
@@ -1155,6 +1201,29 @@ class WindowedSpectrogramPlugin extends BasePlugin<WindowedSpectrogramPluginEven
     this.segments.clear()
   }
 
+  /**
+   * Evict segments whose midpoint is farthest from currentTime once the retained count
+   * exceeds maxRetainedSegments, so memory usage stays bounded regardless of audio length.
+   */
+  private evictDistantSegments(currentTime: number) {
+    if (this.segments.size <= this.maxRetainedSegments) return
+
+    const entries = Array.from(this.segments.entries())
+    // Farthest-from-currentTime first
+    entries.sort((a, b) => {
+      const distA = Math.abs((a[1].startTime + a[1].endTime) / 2 - currentTime)
+      const distB = Math.abs((b[1].startTime + b[1].endTime) / 2 - currentTime)
+      return distB - distA
+    })
+
+    const numToEvict = this.segments.size - this.maxRetainedSegments
+    for (let i = 0; i < numToEvict; i++) {
+      const [key, segment] = entries[i]
+      segment.canvas?.remove()
+      this.segments.delete(key)
+    }
+  }
+
   private getFilterBank(sampleRate: number) {
     const fftLength = this.fftSize ?? this.fftSamples
     const numFilters = fftLength / 2
@@ -1286,8 +1355,6 @@ class WindowedSpectrogramPlugin extends BasePlugin<WindowedSpectrogramPluginEven
   }
 
   destroy() {
-    this.unAll()
-
     if (this.renderTimeout) {
       clearTimeout(this.renderTimeout)
       this.renderTimeout = null
@@ -1298,6 +1365,11 @@ class WindowedSpectrogramPlugin extends BasePlugin<WindowedSpectrogramPluginEven
       this.qualityUpdateTimeout = null
     }
 
+    if (this.initialRenderTimeout) {
+      clearTimeout(this.initialRenderTimeout)
+      this.initialRenderTimeout = null
+    }
+
     // Stop progressive loading
     this.stopProgressiveLoading()
     this.nextProgressiveSegmentTime = 0
diff --git a/src/plugins/spectrogram.ts b/src/plugins/spectrogram.ts
--- a/src/plugins/spectrogram.ts
+++ b/src/plugins/spectrogram.ts
@@ -179,9 +179,10 @@ export type SpectrogramPluginEvents = BasePluginEvents & {
 const isPowerOfTwo = (value: number) => Number.isInteger(value) && value >= 2 && Number.isInteger(Math.log2(value))
 
 class SpectrogramPlugin extends BasePlugin<SpectrogramPluginEvents, SpectrogramPluginOptions> {
-  private static MAX_CANVAS_WIDTH = 30000
   private static MAX_NODES = 10
 
+  private maxCanvasWidth = 30000
+  private buffer: AudioBuffer | null = null
   private frequenciesDataUrl?: string
   private container: HTMLElement
   private wrapper: HTMLElement
@@ -323,7 +324,7 @@ class SpectrogramPlugin extends BasePlugin<SpectrogramPluginEvents, SpectrogramP
 
     // Override the default max canvas width if provided
     if (options.maxCanvasWidth) {
-      SpectrogramPlugin.MAX_CANVAS_WIDTH = options.maxCanvasWidth
+      this.maxCanvasWidth = options.maxCanvasWidth
     }
 
     // Set default performance settings
@@ -444,20 +445,6 @@ class SpectrogramPlugin extends BasePlugin<SpectrogramPluginEvents, SpectrogramP
   }
 
   public destroy() {
-    this.unAll()
-
-    // Clean up any direct event listeners (if they exist)
-    if (this.wavesurfer) {
-      // Note: _onReady and _onRender methods may not exist, but the original code had these
-      // We should be cautious and only call un if the methods exist
-      if (typeof this._onReady === 'function') {
-        this.wavesurfer.un('ready', this._onReady)
-      }
-      if (typeof this._onRender === 'function') {
-        this.wavesurfer.un('redraw', this._onRender)
-      }
-    }
-
     // Clean up performance optimization resources
     if (this.renderTimeout) {
       clearTimeout(this.renderTimeout)
@@ -479,6 +466,7 @@ class SpectrogramPlugin extends BasePlugin<SpectrogramPluginEvents, SpectrogramP
     this.cachedFrequencies = null
     this.cachedResampledData = null
     this.cachedBuffer = null
+    this.buffer = null
 
     // Clean up DOM elements properly
     this.clearCanvases()
@@ -500,9 +488,6 @@ class SpectrogramPlugin extends BasePlugin<SpectrogramPluginEvents, SpectrogramP
     this.container = null
     this.isRendering = false
     this.lastZoomLevel = 0
-    this.wavesurfer = null
-    this.util = null
-    this.options = null
 
     super.destroy()
   }
@@ -513,7 +498,7 @@ class SpectrogramPlugin extends BasePlugin<SpectrogramPluginEvents, SpectrogramP
       throw new Error('Unable to fetch frequencies data')
     }
     const data = await resp.json()
-    if (!this.options) return
+    if (this.destroyed) return
     this.drawSpectrogram(data)
   }
 
@@ -670,7 +655,7 @@ class SpectrogramPlugin extends BasePlugin<SpectrogramPluginEvents, SpectrogramP
         const decodedData = this.wavesurfer?.getDecodedData()
         if (decodedData) {
           const frequencies = await this.getFrequenciesData()
-          if (!this.options || !frequencies) return
+          if (this.destroyed || !frequencies) return
           // Draw what this render computed (cache hit, fresh data, or empty on failure)
           // rather than whatever the cache field holds
           this.drawSpectrogram(frequencies)
@@ -720,7 +705,7 @@ class SpectrogramPlugin extends BasePlugin<SpectrogramPluginEvents, SpectrogramP
     this.wrapper.style.height = totalHeight + 'px'
 
     const totalWidth = this.getWidth()
-    const maxCanvasWidth = Math.min(SpectrogramPlugin.MAX_CANVAS_WIDTH, totalWidth)
+    const maxCanvasWidth = Math.min(this.maxCanvasWidth, totalWidth)
 
     // Nothing to render
     if (totalWidth === 0 || totalHeight === 0) return
@@ -1053,8 +1038,8 @@ class SpectrogramPlugin extends BasePlugin<SpectrogramPluginEvents, SpectrogramP
       try {
         return await this.calculateFrequenciesWithWorker(buffer)
       } catch (error) {
-        if (!this.options) return []
-        
+        if (this.destroyed) return []
+
         if (!this.fallbackToMainThread) {
           // Surface the failure instead of silently recomputing on the main thread, which
           // can freeze the page for long files
diff --git a/src/plugins/timeline.ts b/src/plugins/timeline.ts
--- a/src/plugins/timeline.ts
+++ b/src/plugins/timeline.ts
@@ -59,7 +59,7 @@ class TimelinePlugin extends BasePlugin<TimelinePluginEvents, TimelinePluginOpti
   private timelineWrapper: HTMLElement
   protected options: TimelinePluginOptions & typeof defaultOptions
   private notchElements: Map<HTMLElement, { start: number; width: number; wasVisible: boolean }> = new Map()
-  private currentTimeline: HTMLElement | null = null
+  private currentTimeline: HTMLElement | undefined = undefined
 
   constructor(options?: TimelinePluginOptions) {
     super(options || {})
@@ -127,6 +127,8 @@ class TimelinePlugin extends BasePlugin<TimelinePluginEvents, TimelinePluginOpti
 
   /** Unmount */
   public destroy() {
+    this.notchElements.clear()
+    this.currentTimeline = undefined
     this.timelineWrapper.remove()
     super.destroy()
   }
diff --git a/src/reactive/README.md b/src/reactive/README.md
--- a/src/reactive/README.md
+++ b/src/reactive/README.md
@@ -1,10 +1,10 @@
 # Reactive System
 
-Signal-based reactivity for WaveSurfer.js, providing automatic state management and efficient updates.
+Signal-based reactivity for WaveSurfer.js: state management and event streams built on plain synchronous signals.
 
 ## Overview
 
-The reactive system provides a lightweight, signal-based reactivity implementation similar to SolidJS signals. Signals are reactive values that automatically notify subscribers when they change, enabling efficient state management and UI updates.
+The reactive system provides a lightweight, signal-based reactivity implementation similar to SolidJS signals. Signals are reactive values that notify subscribers when they change. Notification is **synchronous** by default; `batch()` is the only way to coalesce multiple writes into a single notification (see below).
 
 ## Core Concepts
 
@@ -26,68 +26,113 @@ const unsubscribe = count.subscribe((value) => {
   console.log('Count changed:', value)
 })
 
-count.set(10) // Logs: "Count changed: 10"
+count.set(10) // Synchronously logs: "Count changed: 10"
 unsubscribe() // Stop listening
 ```
 
 ### Computed Values
 
-Automatically derived values that update when dependencies change.
+Derived values that recompute when their dependencies change. `computed()` is always disposable: calling `dispose()` unsubscribes it from its dependencies so it stops recomputing. Without a `dependencies` array, dependencies are auto-tracked from whichever signals are read during the function body, and are re-collected on every run so conditional reads stay correct.
 
 ```typescript
 import { signal, computed } from './store.js'
 
 const count = signal(0)
+
+// Explicit dependencies
 const doubled = computed(() => count.value * 2, [count])
 
+// Auto-tracked dependencies (omit the array)
+const tripled = computed(() => count.value * 3)
+
 console.log(doubled.value) // 0
 count.set(5)
 console.log(doubled.value) // 10
+
+// Stop recomputing and unsubscribe from dependencies
+doubled.dispose()
+tripled.dispose()
 ```
 
 ### Effects
 
-Side effects that run automatically when dependencies change.
+Side effects that (re-)run when dependencies change. Like `computed`, `effect` supports both an explicit `dependencies` array and auto-tracking. The function may return a cleanup callback, which runs before the next invocation and on final teardown.
 
 ```typescript
 import { signal, effect } from './store.js'
 
 const count = signal(0)
 
-const cleanup = effect(() => {
+const stop = effect(() => {
   console.log('Count is:', count.value)
   // Optional: return cleanup function
   return () => console.log('Cleanup')
 }, [count])
 
 count.set(5) // Logs: "Cleanup", "Count is: 5"
-cleanup() // Stop effect and run cleanup
+stop() // Stop effect and run final cleanup
 ```
 
-## Module Architecture
+### batch()
 
-### Core Reactive Primitives
+Signal writes notify subscribers synchronously, one `set()` call at a time — there is no automatic batching. To coalesce multiple writes into a single notification per signal, wrap them in `batch()`:
 
-- **`store.ts`** - Core signal, computed, and effect implementations
-  - `signal<T>(value)` - Create a writable reactive value
-  - `computed<T>(fn, deps)` - Create a derived reactive value
-  - `effect(fn, deps)` - Run side effects on changes
+```typescript
+import { signal, batch } from './store.js'
+
+const count = signal(0)
+count.subscribe((v) => console.log('count:', v))
+
+count.set(1) // Logs "count: 1" immediately
+count.set(2) // Logs "count: 2" immediately
+
+batch(() => {
+  count.set(3) // Queued, not yet delivered
+  count.set(4) // Queued, replaces the previous queued notification
+})
+// Logs "count: 4" once, after the batch() call returns
+```
+
+Nested `batch()` calls are supported: notifications are only flushed once the outermost `batch()` returns. Writes triggered by a notification while flushing (e.g. one subscriber setting another signal) are queued rather than fired re-entrantly.
+
+### Scope
+
+`Scope` (in `../scope.ts`, one level up from `reactive/`) is the disposal-tree ownership primitive used throughout wavesurfer for listeners, timers, observers, signal subscriptions, and child lifetimes. Every `destroy()` in the codebase is expressed as disposing a `Scope`.
+
+```typescript
+import { Scope } from '../scope.js'
+
+const scope = new Scope()
 
-### Event Streams
+scope.add(() => console.log('cleanup'))
+scope.listen(element, 'click', onClick)
+scope.timeout(() => console.log('fired'), 100)
+scope.interval(tick, 16)
+scope.raf(onFrame)
 
-- **`event-stream-emitter.ts`** - Convert EventEmitter to reactive streams
-- **`event-streams.ts`** - DOM event streams (click, drag, scroll, zoom)
-- **`drag-stream.ts`** - Drag gesture detection and handling
-- **`scroll-stream.ts`** - Scroll position tracking with percentages
+// Child scopes dispose together with (and before) their parent's own disposers
+const child = scope.child()
 
-### Bridges
+scope.dispose() // disposes children first, then own disposers, LIFO
+```
 
-- **`state-event-emitter.ts`** - Bridge reactive state to EventEmitter API (backwards compatibility)
-- **`media-event-bridge.ts`** - Bridge HTML media events to reactive state
+Disposing a `Scope` is idempotent, disposes children before its own disposers (own disposers run LIFO), and any disposer added after disposal runs immediately instead of leaking.
+
+## Module Architecture
+
+### Core Reactive Primitives
+
+- **`store.ts`** - Core signal, computed, effect and `batch()` implementations
+  - `signal<T>(value)` - Create a writable reactive value
+  - `computed<T>(fn, deps?)` - Create a disposable derived reactive value
+  - `effect(fn, deps?)` - Run side effects on changes; returns a stop/dispose function
+  - `batch(fn)` - Coalesce signal writes made inside `fn` into one notification per signal
 
-### Utilities
+### Event & Gesture Streams
 
-- **`render-scheduler.ts`** - Efficient render scheduling with RAF batching
+- **`event-streams.ts`** - `fromEvent()` converts a DOM event into a signal; `cleanup()` tears down a stream's listener/subscription. Used by the hover, zoom, and regions plugins.
+- **`drag-stream.ts`** - Drag gesture detection (`createDragStream`), the reactive replacement for the old `makeDraggable` helper.
+- **`scroll-stream.ts`** - Scroll position tracking with percentages.
 
 ## Usage in WaveSurfer
 
@@ -137,79 +182,54 @@ class MyPlugin extends BasePlugin {
 
 Run tests:
 ```bash
-npm test src/reactive/__tests__
+npx jest src/reactive/__tests__ src/__tests__/scope.test.ts
 ```
 
-Test coverage: **97.66%**
-
 Test files:
-- `store.test.ts` - Core reactive primitives (362 tests)
-- `event-stream-emitter.test.ts` - EventEmitter streams (335 tests)
-- `event-streams.test.ts` - DOM event streams (375 tests)
-- `drag-stream.test.ts` - Drag gestures (253 tests)
-- `scroll-stream.test.ts` - Scroll tracking (250 tests)
-- `state-event-emitter.test.ts` - State bridging (368 tests)
-- `media-event-bridge.test.ts` - Media events (277 tests)
-- `render-scheduler.test.ts` - Render scheduling (278 tests)
+- `store.test.ts` - Core reactive primitives: signal, computed, effect, batch
+- `event-streams.test.ts` - DOM event streams (`fromEvent`, `cleanup`)
+- `drag-stream.test.ts` - Drag gestures
+- `scroll-stream.test.ts` - Scroll tracking
+- `../../__tests__/scope.test.ts` - The `Scope` disposal-tree primitive
 
 ## Best Practices
 
-1. **Always unsubscribe**: Store unsubscribe functions and call them in cleanup
+1. **Always unsubscribe / dispose**: Store unsubscribe functions (or the `computed`/`effect`/`Scope` handle) and call them in cleanup.
    ```typescript
    const unsubscribe = signal.subscribe(...)
    // Later:
    unsubscribe()
    ```
 
-2. **Use computed for derived values**: Don't manually recalculate
+2. **Use computed for derived values**: Don't manually recalculate, and dispose computeds you no longer need.
    ```typescript
    // Good
    const total = computed(() => price.value * quantity.value, [price, quantity])
-   
+   // Later:
+   total.dispose()
+
    // Avoid
    let total = 0
    price.subscribe(p => total = p * quantity.value)
    quantity.subscribe(q => total = price.value * q)
    ```
 
-3. **Batch updates**: Multiple signal updates in the same tick are batched
+3. **Use `batch()` when writing multiple signals together**: without it, each `set()` notifies synchronously on its own.
    ```typescript
-   count.set(1)
-   count.set(2)
-   count.set(3)
+   batch(() => {
+     count.set(1)
+     count.set(2)
+     count.set(3)
+   })
    // Subscribers notified once with value 3
    ```
 
-4. **Memory safety**: Cleanup subscriptions in destroy/cleanup methods
-   ```typescript
-   class Component {
-     private cleanups: Array<() => void> = []
-     
-     init() {
-       this.cleanups.push(
-         state.subscribe(...)
-       )
-     }
-     
-     destroy() {
-       this.cleanups.forEach(fn => fn())
-     }
-   }
-   ```
+4. **Prefer `Scope` for lifecycle-bound resources**: listeners, timers, observers, and child components should be registered on a `Scope` and released via a single `scope.dispose()` rather than tracked by hand.
 
 ## Performance Characteristics
 
 - **O(1)** signal reads via property getter
 - **O(n)** signal writes, where n = number of subscribers
-- **Automatic batching** - Multiple updates in same tick are batched
+- **Synchronous notification** - `set()` notifies subscribers immediately unless inside `batch()`
 - **Change detection** - Uses `Object.is()` to detect changes
 - **Memory efficient** - Subscriptions use `Set` for O(1) add/remove
-
-## Future Enhancements
-
-Potential improvements for future versions:
-
-- Optional debug mode for tracking signal updates
-- WeakMap-based subscriptions for large objects
-- Automatic dependency tracking (like SolidJS)
-- Transaction support for atomic multi-signal updates
diff --git a/src/reactive/drag-stream.ts b/src/reactive/drag-stream.ts
--- a/src/reactive/drag-stream.ts
+++ b/src/reactive/drag-stream.ts
@@ -6,7 +6,6 @@
  */
 
 import { signal, type Signal } from './store.js'
-import { cleanup } from './event-streams.js'
 
 export interface DragEvent {
   type: 'start' | 'move' | 'end'
@@ -188,7 +187,6 @@ export function createDragStream(
     unsubscribeDocument()
     element.removeEventListener('pointerdown', onPointerDown)
     activePointers.clear()
-    cleanup(dragSignal)
   }
 
   return {
diff --git a/src/reactive/event-stream-emitter.ts b/src/reactive/event-stream-emitter.ts
deleted file mode 100644
--- a/src/reactive/event-stream-emitter.ts
+++ /dev/null
@@ -1,195 +0,0 @@
-/**
- * Event stream emitter - bridges EventEmitter to reactive streams
- *
- * Provides reactive stream API on top of traditional EventEmitter.
- * This allows users to choose between callback-based and stream-based APIs.
- */
-
-import { signal, type Signal, type WritableSignal } from './store.js'
-import type EventEmitter from '../event-emitter.js'
-
-/**
- * Convert an EventEmitter event to a reactive signal/stream
- *
- * Creates a signal that updates whenever the event is emitted.
- * Returns both the signal (for reading values) and cleanup function.
- *
- * @example
- * ```typescript
- * const { stream, cleanup } = toStream(wavesurfer, 'play')
- *
- * // Subscribe to play events
- * stream.subscribe(() => console.log('Playing!'))
- *
- * // Cleanup when done
- * cleanup()
- * ```
- *
- * @param emitter - EventEmitter instance
- * @param eventName - Name of the event to stream
- * @returns Object with stream signal and cleanup function
- */
-export function toStream<T extends Record<string, any[]>, K extends keyof T>(
-  emitter: EventEmitter<T>,
-  eventName: K,
-): {
-  stream: Signal<T[K] | null>
-  cleanup: () => void
-} {
-  const stream = signal<T[K] | null>(null) as WritableSignal<T[K] | null>
-
-  // Listen to event and update signal
-  const handler = (...args: T[K]) => {
-    stream.set(args)
-  }
-
-  // @ts-expect-error - EventEmitter on() signature
-  const unsubscribe = emitter.on(eventName as string, handler)
-
-  return {
-    stream,
-    cleanup: unsubscribe,
-  }
-}
-
-/**
- * Create multiple event streams from an emitter
- *
- * Helper to create streams for multiple events at once.
- *
- * @example
- * ```typescript
- * const streams = toStreams(wavesurfer, ['play', 'pause', 'timeupdate'])
- *
- * streams.play.subscribe(() => console.log('Play'))
- * streams.pause.subscribe(() => console.log('Pause'))
- * streams.timeupdate.subscribe(([time]) => console.log('Time:', time))
- *
- * // Cleanup all
- * streams.cleanup()
- * ```
- *
- * @param emitter - EventEmitter instance
- * @param eventNames - Array of event names to stream
- * @returns Object with streams for each event and cleanup function
- */
-export function toStreams<T extends Record<string, any[]>, K extends keyof T>(
-  emitter: EventEmitter<T>,
-  eventNames: K[],
-): {
-  [P in K]: Signal<T[P] | null>
-} & {
-  cleanup: () => void
-} {
-  const cleanups: Array<() => void> = []
-  const result: any = {}
-
-  for (const eventName of eventNames) {
-    const { stream, cleanup } = toStream(emitter, eventName)
-    result[eventName] = stream
-    cleanups.push(cleanup)
-  }
-
-  // Add cleanup that removes all event listeners
-  result.cleanup = () => {
-    cleanups.forEach((cleanup) => cleanup())
-  }
-
-  return result
-}
-
-/**
- * Create a stream that combines multiple events into one
- *
- * Useful when you want to react to any of several events.
- *
- * @example
- * ```typescript
- * const { stream, cleanup } = mergeStreams(wavesurfer, ['play', 'pause'])
- *
- * stream.subscribe(({ event, args }) => {
- *   console.log(`Event ${event} fired with`, args)
- * })
- * ```
- *
- * @param emitter - EventEmitter instance
- * @param eventNames - Array of event names to merge
- * @returns Object with merged stream and cleanup function
- */
-export function mergeStreams<T extends Record<string, any[]>, K extends keyof T>(
-  emitter: EventEmitter<T>,
-  eventNames: K[],
-): {
-  stream: Signal<{ event: K; args: T[K] } | null>
-  cleanup: () => void
-} {
-  const stream = signal<{ event: K; args: T[K] } | null>(null) as WritableSignal<{
-    event: K
-    args: T[K]
-  } | null>
-  const cleanups: Array<() => void> = []
-
-  for (const eventName of eventNames) {
-    // @ts-expect-error - EventEmitter on() signature
-    const unsubscribe = emitter.on(eventName as string, (...args: T[K]) => {
-      stream.set({ event: eventName, args })
-    })
-    cleanups.push(unsubscribe)
-  }
-
-  return {
-    stream,
-    cleanup: () => {
-      cleanups.forEach((cleanup) => cleanup())
-    },
-  }
-}
-
-/**
- * Helper to map event stream values
- *
- * @example
- * ```typescript
- * const { stream: timeStream } = toStream(wavesurfer, 'timeupdate')
- * const seconds = mapStream(timeStream, ([time]) => Math.floor(time))
- * ```
- */
-export function mapStream<T, U>(source: Signal<T>, mapper: (value: T) => U): Signal<U> {
-  const result = signal<U>(mapper(source.value)) as WritableSignal<U>
-
-  const unsubscribe = source.subscribe((value) => {
-    result.set(mapper(value))
-  })
-
-  // Store cleanup
-  ;(result as any)._cleanup = unsubscribe
-
-  return result
-}
-
-/**
- * Helper to filter event stream values
- *
- * @example
- * ```typescript
- * const { stream: timeStream } = toStream(wavesurfer, 'timeupdate')
- * const afterTenSeconds = filterStream(timeStream, ([time]) => time > 10)
- * ```
- */
-export function filterStream<T>(source: Signal<T>, predicate: (value: T) => boolean): Signal<T | null> {
-  const initialValue = predicate(source.value) ? source.value : null
-  const result = signal<T | null>(initialValue) as WritableSignal<T | null>
-
-  const unsubscribe = source.subscribe((value) => {
-    if (predicate(value)) {
-      result.set(value)
-    } else {
-      result.set(null)
-    }
-  })
-
-  // Store cleanup
-  ;(result as any)._cleanup = unsubscribe
-
-  return result
-}
diff --git a/src/reactive/event-streams.ts b/src/reactive/event-streams.ts
--- a/src/reactive/event-streams.ts
+++ b/src/reactive/event-streams.ts
@@ -35,128 +35,6 @@ export function fromEvent<K extends keyof HTMLElementEventMap>(
   return stream
 }
 
-/**
- * Transform stream values using a mapping function
- *
- * @example
- * ```typescript
- * const clicks = fromEvent(button, 'click')
- * const positions = map(clicks, e => e ? e.clientX : 0)
- * ```
- */
-export function map<T, U>(source: Signal<T>, mapper: (value: T) => U): Signal<U> {
-  const result = signal<U>(mapper(source.value))
-
-  const unsubscribe = source.subscribe((value) => {
-    ;(result as WritableSignal<U>).set(mapper(value))
-  })
-
-  // Store cleanup
-  ;(result as any)._cleanup = unsubscribe
-
-  return result
-}
-
-/**
- * Filter stream values based on a predicate
- *
- * @example
- * ```typescript
- * const numbers = signal(5)
- * const evenOnly = filter(numbers, n => n % 2 === 0)
- * ```
- */
-export function filter<T>(source: Signal<T>, predicate: (value: T) => boolean): Signal<T | null> {
-  const initialValue = predicate(source.value) ? source.value : null
-  const result = signal<T | null>(initialValue)
-
-  const unsubscribe = source.subscribe((value) => {
-    if (predicate(value)) {
-      ;(result as WritableSignal<T | null>).set(value)
-    } else {
-      ;(result as WritableSignal<T | null>).set(null)
-    }
-  })
-
-  // Store cleanup
-  ;(result as any)._cleanup = unsubscribe
-
-  return result
-}
-
-/**
- * Debounce stream updates - wait for quiet period before emitting
- *
- * @example
- * ```typescript
- * const input = fromEvent(textField, 'input')
- * const debounced = debounce(input, 300) // Wait 300ms after last input
- * ```
- */
-export function debounce<T>(source: Signal<T>, delay: number): Signal<T> {
-  const result = signal<T>(source.value)
-  let timeout: ReturnType<typeof setTimeout> | undefined
-
-  const unsubscribe = source.subscribe((value) => {
-    clearTimeout(timeout)
-    timeout = setTimeout(() => {
-      ;(result as WritableSignal<T>).set(value)
-    }, delay)
-  })
-
-  // Store cleanup that clears timeout and unsubscribes
-  ;(result as any)._cleanup = () => {
-    clearTimeout(timeout)
-    unsubscribe()
-  }
-
-  return result
-}
-
-/**
- * Throttle stream updates - limit update frequency
- *
- * Emits immediately, then waits before allowing next emission.
- * Different from debounce which waits for quiet period.
- *
- * @example
- * ```typescript
- * const scroll = fromEvent(window, 'scroll')
- * const throttled = throttle(scroll, 100) // Max once per 100ms
- * ```
- */
-export function throttle<T>(source: Signal<T>, delay: number): Signal<T> {
-  const result = signal<T>(source.value)
-  let lastEmit = 0
-  let timeout: ReturnType<typeof setTimeout> | undefined
-
-  const unsubscribe = source.subscribe((value) => {
-    const now = Date.now()
-    const timeSinceLastEmit = now - lastEmit
-
-    if (timeSinceLastEmit >= delay) {
-      // Enough time has passed, emit immediately
-      ;(result as WritableSignal<T>).set(value)
-      lastEmit = now
-    } else {
-      // Too soon, schedule for later
-      clearTimeout(timeout)
-      timeout = setTimeout(() => {
-        ;(result as WritableSignal<T>).set(value)
-        lastEmit = Date.now()
-      }, delay - timeSinceLastEmit)
-    }
-  })
-
-  // Store cleanup
-  ;(result as any)._cleanup = () => {
-    clearTimeout(timeout)
-    unsubscribe()
-  }
-
-  return result
-}
-
 /**
  * Cleanup a stream created with event stream utilities
  *
diff --git a/src/reactive/media-event-bridge.ts b/src/reactive/media-event-bridge.ts
deleted file mode 100644
--- a/src/reactive/media-event-bridge.ts
+++ /dev/null
@@ -1,184 +0,0 @@
-/**
- * Media event bridge utilities
- *
- * Bridges HTMLMediaElement events to reactive state updates.
- * Provides a clean separation between imperative media API and reactive state.
- */
-
-import type { WaveSurferActions } from '../state/wavesurfer-state.js'
-
-/**
- * Bridge HTMLMediaElement events to WaveSurfer state actions
- *
- * This function sets up event listeners on a media element that automatically
- * update the reactive state through actions. It handles all standard media events
- * (play, pause, timeupdate, etc.) and keeps state in sync with media.
- *
- * @example
- * ```typescript
- * const { state, actions } = createWaveSurferState()
- * const media = document.createElement('audio')
- *
- * const cleanup = bridgeMediaEvents(media, actions)
- *
- * // Now media events automatically update state
- * media.play() // → actions.setPlaying(true)
- * ```
- *
- * @param media - HTMLMediaElement to listen to
- * @param actions - State actions to call on events
- * @returns Cleanup function that removes all listeners
- */
-export function bridgeMediaEvents(media: HTMLMediaElement, actions: WaveSurferActions): () => void {
-  const listeners: Array<() => void> = []
-
-  // Helper to add event listener and track cleanup
-  const addListener = <K extends keyof HTMLMediaElementEventMap>(
-    event: K,
-    handler: (e: HTMLMediaElementEventMap[K]) => void,
-    options?: AddEventListenerOptions,
-  ) => {
-    media.addEventListener(event, handler, options)
-    listeners.push(() => media.removeEventListener(event, handler))
-  }
-
-  // ============================================================================
-  // Playback State Events
-  // ============================================================================
-
-  addListener('play', () => {
-    actions.setPlaying(true)
-  })
-
-  addListener('pause', () => {
-    actions.setPlaying(false)
-  })
-
-  addListener('ended', () => {
-    actions.setPlaying(false)
-    // Set current time to duration on end
-    if (media.duration) {
-      actions.setCurrentTime(media.duration)
-    }
-  })
-
-  // ============================================================================
-  // Time and Duration Events
-  // ============================================================================
-
-  addListener('timeupdate', () => {
-    actions.setCurrentTime(media.currentTime)
-  })
-
-  addListener('durationchange', () => {
-    if (isFinite(media.duration)) {
-      actions.setDuration(media.duration)
-    }
-  })
-
-  addListener('loadedmetadata', () => {
-    if (isFinite(media.duration)) {
-      actions.setDuration(media.duration)
-    }
-  })
-
-  // ============================================================================
-  // Seeking Events
-  // ============================================================================
-
-  addListener('seeking', () => {
-    actions.setSeeking(true)
-  })
-
-  addListener('seeked', () => {
-    actions.setSeeking(false)
-  })
-
-  // ============================================================================
-  // Volume Events
-  // ============================================================================
-
-  addListener('volumechange', () => {
-    actions.setVolume(media.volume)
-  })
-
-  // ============================================================================
-  // Playback Rate Events
-  // ============================================================================
-
-  addListener('ratechange', () => {
-    actions.setPlaybackRate(media.playbackRate)
-  })
-
-  // Return cleanup function that removes all listeners
-  return () => {
-    listeners.forEach((cleanup) => cleanup())
-  }
-}
-
-/**
- * Bridge HTMLMediaElement events with custom handler
- *
- * Similar to bridgeMediaEvents but allows custom state update logic.
- * Useful when you need more control over how events map to state.
- *
- * @example
- * ```typescript
- * const cleanup = bridgeMediaEventsWithHandler(media, (event, data) => {
- *   if (event === 'play') {
- *     actions.setPlaying(true)
- *     console.log('Started playing')
- *   }
- * })
- * ```
- *
- * @param media - HTMLMediaElement to listen to
- * @param handler - Custom handler function
- * @returns Cleanup function that removes all listeners
- */
-export function bridgeMediaEventsWithHandler(
-  media: HTMLMediaElement,
-  handler: (event: string, data?: any) => void,
-): () => void {
-  const listeners: Array<() => void> = []
-
-  const addListener = <K extends keyof HTMLMediaElementEventMap>(event: K) => {
-    const listener = (e: HTMLMediaElementEventMap[K]) => {
-      handler(event, e)
-    }
-    media.addEventListener(event, listener)
-    listeners.push(() => media.removeEventListener(event, listener))
-  }
-
-  // Add all standard media events
-  const events: Array<keyof HTMLMediaElementEventMap> = [
-    'play',
-    'pause',
-    'ended',
-    'timeupdate',
-    'durationchange',
-    'loadedmetadata',
-    'seeking',
-    'seeked',
-    'volumechange',
-    'ratechange',
-    'waiting',
-    'canplay',
-    'canplaythrough',
-    'loadstart',
-    'progress',
-    'suspend',
-    'abort',
-    'error',
-    'emptied',
-    'stalled',
-    'loadeddata',
-    'playing',
-  ]
-
-  events.forEach((event) => addListener(event))
-
-  return () => {
-    listeners.forEach((cleanup) => cleanup())
-  }
-}
diff --git a/src/reactive/render-scheduler.ts b/src/reactive/render-scheduler.ts
deleted file mode 100644
--- a/src/reactive/render-scheduler.ts
+++ /dev/null
@@ -1,80 +0,0 @@
-/**
- * RenderScheduler batches multiple render requests into a single frame using requestAnimationFrame.
- * This prevents multiple state changes from triggering redundant renders.
- */
-
-export type RenderPriority = 'high' | 'normal' | 'low'
-
-export class RenderScheduler {
-  private pendingRender = false
-  private rafId: number | null = null
-
-  /**
-   * Schedule a render to occur on the next animation frame.
-   * If a render is already scheduled, this is a no-op.
-   *
-   * @param renderFn - The function to call to perform the render
-   * @param priority - Render priority (high = immediate, normal/low = batched)
-   *
-   * @example
-   * ```typescript
-   * const scheduler = new RenderScheduler()
-   *
-   * // Multiple calls in same frame = single render
-   * scheduler.scheduleRender(() => draw())
-   * scheduler.scheduleRender(() => draw()) // no-op
-   * scheduler.scheduleRender(() => draw()) // no-op
-   * ```
-   */
-  scheduleRender(renderFn: () => void, priority: RenderPriority = 'normal'): void {
-    // High priority renders happen immediately
-    if (priority === 'high') {
-      this.flushRender(renderFn)
-      return
-    }
-
-    // If already scheduled, don't schedule again
-    if (this.pendingRender) return
-
-    this.pendingRender = true
-    this.rafId = requestAnimationFrame(() => {
-      try {
-        renderFn()
-      } finally {
-        // Always clean up, even if render throws
-        this.pendingRender = false
-        this.rafId = null
-      }
-    })
-  }
-
-  /**
-   * Cancel any pending render request.
-   * Useful when unmounting or destroying components.
-   */
-  cancelRender(): void {
-    if (this.rafId !== null) {
-      cancelAnimationFrame(this.rafId)
-      this.rafId = null
-      this.pendingRender = false
-    }
-  }
-
-  /**
-   * Force an immediate synchronous render, canceling any pending batched render.
-   * Use for high-priority updates like cursor during playback, or for testing.
-   *
-   * @param renderFn - The function to call to perform the render
-   */
-  flushRender(renderFn: () => void): void {
-    this.cancelRender()
-    renderFn()
-  }
-
-  /**
-   * Check if a render is currently scheduled.
-   */
-  isPending(): boolean {
-    return this.pendingRender
-  }
-}
diff --git a/src/reactive/scroll-stream.ts b/src/reactive/scroll-stream.ts
--- a/src/reactive/scroll-stream.ts
+++ b/src/reactive/scroll-stream.ts
@@ -6,7 +6,6 @@
  */
 
 import { signal, computed, effect, type Signal } from './store.js'
-import { cleanup } from './event-streams.js'
 
 export interface ScrollData {
   /** Current scroll position in pixels */
@@ -133,7 +132,8 @@ export function createScrollStream(element: HTMLElement): ScrollStream {
   // Cleanup function
   const cleanupFn = () => {
     element.removeEventListener('scroll', onScroll)
-    cleanup(scrollData)
+    percentages.dispose()
+    bounds.dispose()
   }
 
   return {
diff --git a/src/reactive/state-event-emitter.ts b/src/reactive/state-event-emitter.ts
deleted file mode 100644
--- a/src/reactive/state-event-emitter.ts
+++ /dev/null
@@ -1,280 +0,0 @@
-/**
- * State-driven event emission utilities
- *
- * Automatically emit events when reactive state changes.
- * Ensures events are always in sync with state and removes manual emit() calls.
- */
-
-import { effect, type Signal } from './store.js'
-import type { WaveSurferState } from '../state/wavesurfer-state.js'
-
-export type EventEmitter = {
-  emit(event: string, ...args: any[]): void
-}
-
-/**
- * Setup automatic event emission from state changes
- *
- * This function subscribes to all relevant state signals and automatically
- * emits corresponding events when state changes. This ensures:
- * - Events are always in sync with state
- * - No manual emit() calls needed
- * - Can't forget to emit an event
- * - Clear event sources (state changes)
- *
- * @example
- * ```typescript
- * const { state } = createWaveSurferState()
- * const wavesurfer = new WaveSurfer()
- *
- * const cleanup = setupStateEventEmission(state, wavesurfer)
- *
- * // Now state changes automatically emit events
- * state.isPlaying.set(true) // → wavesurfer.emit('play')
- * ```
- *
- * @param state - Reactive state to observe
- * @param emitter - Event emitter to emit events on
- * @returns Cleanup function that removes all subscriptions
- */
-export function setupStateEventEmission(state: WaveSurferState, emitter: EventEmitter): () => void {
-  const cleanups: Array<() => void> = []
-
-  // ============================================================================
-  // Play/Pause Events
-  // ============================================================================
-
-  // Emit play/pause events when playing state changes
-  cleanups.push(
-    effect(() => {
-      const isPlaying = state.isPlaying.value
-      emitter.emit(isPlaying ? 'play' : 'pause')
-    }, [state.isPlaying]),
-  )
-
-  // ============================================================================
-  // Time Update Events
-  // ============================================================================
-
-  // Emit timeupdate when current time changes
-  cleanups.push(
-    effect(() => {
-      const currentTime = state.currentTime.value
-      emitter.emit('timeupdate', currentTime)
-
-      // Also emit audioprocess when playing
-      if (state.isPlaying.value) {
-        emitter.emit('audioprocess', currentTime)
-      }
-    }, [state.currentTime, state.isPlaying]),
-  )
-
-  // ============================================================================
-  // Seeking Events
-  // ============================================================================
-
-  // Emit seeking event when seeking state changes to true
-  cleanups.push(
-    effect(() => {
-      const isSeeking = state.isSeeking.value
-      if (isSeeking) {
-        emitter.emit('seeking', state.currentTime.value)
-      }
-    }, [state.isSeeking, state.currentTime]),
-  )
-
-  // ============================================================================
-  // Ready Event
-  // ============================================================================
-
-  // Emit ready when state becomes ready
-  let wasReady = false
-  cleanups.push(
-    effect(() => {
-      const isReady = state.isReady.value
-      if (isReady && !wasReady) {
-        wasReady = true
-        emitter.emit('ready', state.duration.value)
-      }
-    }, [state.isReady, state.duration]),
-  )
-
-  // Reset wasReady when audio buffer is cleared (new load starting)
-  // This allows the 'ready' event to fire again on subsequent loads
-  cleanups.push(
-    effect(() => {
-      if (state.audioBuffer.value === null) {
-        wasReady = false
-      }
-    }, [state.audioBuffer]),
-  )
-
-  // ============================================================================
-  // Finish Event
-  // ============================================================================
-
-  // Emit finish when playback ends (reached duration and stopped)
-  let wasPlayingAtEnd = false
-  cleanups.push(
-    effect(() => {
-      const isPlaying = state.isPlaying.value
-      const currentTime = state.currentTime.value
-      const duration = state.duration.value
-
-      // Check if we're at the end
-      const isAtEnd = duration > 0 && currentTime >= duration
-
-      // Emit finish when we were playing at end and now stopped
-      if (wasPlayingAtEnd && !isPlaying && isAtEnd) {
-        emitter.emit('finish')
-      }
-
-      // Track if we're playing at the end
-      wasPlayingAtEnd = isPlaying && isAtEnd
-    }, [state.isPlaying, state.currentTime, state.duration]),
-  )
-
-  // ============================================================================
-  // Zoom Events
-  // ============================================================================
-
-  // Emit zoom when zoom level changes
-  cleanups.push(
-    effect(() => {
-      const zoom = state.zoom.value
-      if (zoom > 0) {
-        emitter.emit('zoom', zoom)
-      }
-    }, [state.zoom]),
-  )
-
-  // Return cleanup function
-  return () => {
-    cleanups.forEach((cleanup) => cleanup())
-  }
-}
-
-/**
- * Setup custom event emission from signal changes
- *
- * This is a lower-level utility for setting up custom event emission
- * from any signal. Useful when you need more control over event emission logic.
- *
- * @example
- * ```typescript
- * const volumeSignal = signal(1)
- *
- * const cleanup = setupSignalEventEmission(
- *   volumeSignal,
- *   emitter,
- *   (volume) => ['volume', volume]
- * )
- * ```
- *
- * @param signal - Signal to observe
- * @param emitter - Event emitter
- * @param getEventData - Function that returns [eventName, ...args]
- * @returns Cleanup function
- */
-export function setupSignalEventEmission<T>(
-  signal: Signal<T>,
-  emitter: EventEmitter,
-  getEventData: (value: T) => [string, ...any[]],
-): () => void {
-  return effect(() => {
-    const value = signal.value
-    const [eventName, ...args] = getEventData(value)
-    emitter.emit(eventName, ...args)
-  }, [signal])
-}
-
-/**
- * Setup event emission with debouncing
- *
- * Useful for high-frequency events like scroll or timeupdate.
- *
- * @example
- * ```typescript
- * const cleanup = setupDebouncedEventEmission(
- *   state.scrollPosition,
- *   emitter,
- *   (pos) => ['scroll', pos],
- *   100 // debounce 100ms
- * )
- * ```
- *
- * @param signal - Signal to observe
- * @param emitter - Event emitter
- * @param getEventData - Function that returns [eventName, ...args]
- * @param debounceMs - Debounce delay in milliseconds
- * @returns Cleanup function
- */
-export function setupDebouncedEventEmission<T>(
-  signal: Signal<T>,
-  emitter: EventEmitter,
-  getEventData: (value: T) => [string, ...any[]],
-  debounceMs: number,
-): () => void {
-  let timeoutId: ReturnType<typeof setTimeout> | null = null
-
-  const cleanup = effect(() => {
-    const value = signal.value
-
-    // Clear previous timeout
-    if (timeoutId !== null) {
-      clearTimeout(timeoutId)
-    }
-
-    // Set new timeout
-    timeoutId = setTimeout(() => {
-      const [eventName, ...args] = getEventData(value)
-      emitter.emit(eventName, ...args)
-      timeoutId = null
-    }, debounceMs)
-  }, [signal])
-
-  // Return cleanup that also clears pending timeout
-  return () => {
-    if (timeoutId !== null) {
-      clearTimeout(timeoutId)
-    }
-    cleanup()
-  }
-}
-
-/**
- * Setup conditional event emission
- *
- * Only emit events when a condition is met.
- *
- * @example
- * ```typescript
- * // Only emit finish event when playing stops at end
- * const cleanup = setupConditionalEventEmission(
- *   state.isPlaying,
- *   emitter,
- *   (isPlaying) => !isPlaying && state.currentTime.value >= state.duration.value,
- *   () => ['finish']
- * )
- * ```
- *
- * @param signal - Signal to observe
- * @param emitter - Event emitter
- * @param condition - Function that returns true when event should emit
- * @param getEventData - Function that returns [eventName, ...args]
- * @returns Cleanup function
- */
-export function setupConditionalEventEmission<T>(
-  signal: Signal<T>,
-  emitter: EventEmitter,
-  condition: (value: T) => boolean,
-  getEventData: (value: T) => [string, ...any[]],
-): () => void {
-  return effect(() => {
-    const value = signal.value
-    if (condition(value)) {
-      const [eventName, ...args] = getEventData(value)
-      emitter.emit(eventName, ...args)
-    }
-  }, [signal])
-}
diff --git a/src/reactive/store.ts b/src/reactive/store.ts
--- a/src/reactive/store.ts
+++ b/src/reactive/store.ts
@@ -1,54 +1,133 @@
 /**
- * Reactive primitives for managing state in WaveSurfer
- *
- * This module provides signal-based reactivity similar to SolidJS signals.
- * Signals are reactive values that notify subscribers when they change.
+ * Reactive primitives for managing state in WaveSurfer.
+ * Signals notify synchronously; use batch() to coalesce. computed/effect
+ * auto-track dependencies when no dependency array is given, and are
+ * always disposable.
  */
 
-/**
- * A reactive value that can be read and subscribed to
- */
 export interface Signal<T> {
-  /** Get the current value */
   get value(): T
-  /** Subscribe to changes. Returns an unsubscribe function. */
   subscribe(callback: (value: T) => void): () => void
 }
 
-/**
- * A writable reactive value that can be updated
- */
 export interface WritableSignal<T> extends Signal<T> {
-  /** Set a new value. Only notifies if value changed. */
   set(value: T): void
-  /** Update value using a function. */
   update(fn: (current: T) => T): void
 }
 
+export interface ComputedSignal<T> extends Signal<T> {
+  dispose(): void
+}
+
+type AnySignal = Signal<unknown>
+
+let activeTracker: Set<AnySignal> | null = null
+let batchDepth = 0
+// Queue of not-yet-fired notifyAll closures, one per dirtied signal.
+// pendingSet gives O(1) membership checks so re-dirtying an already-queued
+// signal merges into its existing entry instead of pushing a duplicate.
+const pendingQueue: Array<() => void> = []
+const pendingSet = new Set<() => void>()
+
+function scheduleNotification(notify: () => void): void {
+  if (pendingSet.has(notify)) return
+  pendingSet.add(notify)
+  pendingQueue.push(notify)
+}
+
+export function batch(fn: () => void): void {
+  batchDepth++
+  try {
+    fn()
+  } finally {
+    batchDepth--
+    if (batchDepth === 0) {
+      flushPending()
+    }
+  }
+}
+
 /**
- * Create a reactive signal that notifies subscribers when its value changes
+ * Drain pendingQueue until empty. Runs under an elevated batchDepth so that
+ * any set() triggered by a notification - e.g. one signal's subscriber
+ * setting another signal, or a signal's own subscriber re-setting itself -
+ * is queued rather than fired immediately.
+ *
+ * Draining LIFO (most-recently-queued first) means a cascading set()
+ * triggered while flushing a later-queued entry reaches an earlier-queued,
+ * not-yet-fired entry for the same signal in time to merge into it, instead
+ * of that entry having already fired with a stale value and needing a
+ * second, separate flush.
  *
- * @example
- * ```typescript
- * const count = signal(0)
- * count.subscribe(val => console.log('Count:', val))
- * count.set(5) // Logs: Count: 5
- * ```
+ * A signal stays in pendingSet for the full duration of its own notify()
+ * call, not just while it's queued. That way a same-signal reentrant set()
+ * triggered from within its own subscribers - which notify()'s internal
+ * notifying/settleAgain loop already settles to the final value - finds
+ * itself still "pending" and is deduped by scheduleNotification, instead of
+ * being re-queued for a redundant second delivery of the same final value.
  */
+function flushPending(): void {
+  batchDepth++
+  try {
+    while (pendingQueue.length > 0) {
+      const notify = pendingQueue.pop() as () => void
+      notify()
+      pendingSet.delete(notify)
+    }
+  } finally {
+    batchDepth--
+  }
+}
+
 export function signal<T>(initialValue: T): WritableSignal<T> {
   let _value = initialValue
   const subscribers = new Set<(value: T) => void>()
+  let notifying = false
+  let settleAgain = false
 
-  return {
+  const notifyAll = () => {
+    if (notifying) {
+      settleAgain = true
+      return
+    }
+    notifying = true
+    try {
+      do {
+        settleAgain = false
+        const snapshot = [...subscribers]
+        const valueAtStart = _value
+        for (const fn of snapshot) {
+          try {
+            fn(valueAtStart)
+          } catch (err) {
+            console.error('Signal subscriber error:', err)
+          }
+          // A subscriber changed the value again; abort this pass, the
+          // settle loop delivers the newer value to everyone
+          if (!Object.is(_value, valueAtStart)) {
+            settleAgain = true
+            break
+          }
+        }
+      } while (settleAgain)
+    } finally {
+      notifying = false
+    }
+  }
+
+  const self: WritableSignal<T> = {
     get value() {
+      activeTracker?.add(self)
       return _value
     },
 
     set(newValue: T) {
-      // Only update and notify if value actually changed
-      if (!Object.is(_value, newValue)) {
-        _value = newValue
-        subscribers.forEach((fn) => fn(_value))
+      if (Object.is(_value, newValue)) return
+      _value = newValue
+      if (batchDepth > 0) {
+        scheduleNotification(notifyAll)
+      } else {
+        notifyAll()
       }
     },
 
@@ -61,90 +140,111 @@ export function signal<T>(initialValue: T): WritableSignal<T> {
       return () => subscribers.delete(callback)
     },
   }
+
+  return self
 }
 
-/**
- * Create a computed value that automatically updates when its dependencies change
- *
- * @example
- * ```typescript
- * const count = signal(0)
- * const doubled = computed(() => count.value * 2, [count])
- * console.log(doubled.value) // 0
- * count.set(5)
- * console.log(doubled.value) // 10
- * ```
- */
-export function computed<T>(fn: () => T, dependencies: Signal<any>[]): Signal<T> {
-  const result = signal<T>(fn())
-
-  // Subscribe to all dependencies immediately
-  // This ensures the computed value stays in sync even if no one is subscribed to it
-  dependencies.forEach((dep) =>
-    dep.subscribe(() => {
-      const newValue = fn()
-      // Update the result signal, which will notify our subscribers if value changed
-      if (!Object.is(result.value, newValue)) {
-        ;(result as WritableSignal<T>).set(newValue)
-      }
-    }),
-  )
+/** Run fn, recording which signals it reads. Returns [result, dependencies]. */
+function track<T>(fn: () => T): [T, Set<AnySignal>] {
+  const previousTracker = activeTracker
+  const deps = new Set<AnySignal>()
+  activeTracker = deps
+  try {
+    return [fn(), deps]
+  } finally {
+    activeTracker = previousTracker
+  }
+}
+
+export function computed<T>(fn: () => T, dependencies?: Signal<any>[]): ComputedSignal<T> {
+  const result = signal<T>(undefined as T)
+  let unsubscribes: Array<() => void> = []
+  let disposed = false
+
+  const recompute = () => {
+    if (disposed) return
+    if (dependencies) {
+      result.set(fn())
+    } else {
+      // Auto-tracked: re-collect dependencies on every run so
+      // conditional reads stay correct
+      unsubscribes.forEach((unsub) => unsub())
+      const [value, deps] = track(fn)
+      unsubscribes = [...deps].map((dep) => dep.subscribe(recompute))
+      result.set(value)
+    }
+  }
 
-  // Return a read-only signal that proxies the result
-  return {
+  if (dependencies) {
+    unsubscribes = dependencies.map((dep) => dep.subscribe(recompute))
+    result.set(fn())
+  } else {
+    recompute()
+  }
+
+  const dispose = () => {
+    disposed = true
+    unsubscribes.forEach((unsub) => unsub())
+    unsubscribes = []
+  }
+
+  const readonly: ComputedSignal<T> = {
     get value() {
+      // Propagate tracking so computeds can nest
+      activeTracker?.add(readonly)
       return result.value
     },
-
-    subscribe(callback: (value: T) => void): () => void {
-      // Just subscribe to result changes
-      return result.subscribe(callback)
-    },
+    subscribe: (callback) => result.subscribe(callback),
+    dispose,
   }
+
+  // Duck-typed disposal used by event-streams' cleanup()
+  Object.defineProperty(readonly, '_cleanup', { value: dispose, enumerable: false })
+
+  return readonly
 }
 
-/**
- * Run a side effect automatically when dependencies change
- *
- * @param fn - Effect function. Can return a cleanup function.
- * @param dependencies - Signals that trigger the effect when they change
- * @returns Unsubscribe function that stops the effect and runs cleanup
- *
- * @example
- * ```typescript
- * const count = signal(0)
- * effect(() => {
- *   console.log('Count is:', count.value)
- *   return () => console.log('Cleanup')
- * }, [count])
- * count.set(5) // Logs: Cleanup, Count is: 5
- * ```
- */
-export function effect(fn: () => void | (() => void), dependencies: Signal<any>[]): () => void {
+export function effect(fn: () => void | (() => void), dependencies?: Signal<any>[]): () => void {
   let cleanup: (() => void) | void
+  let unsubscribes: Array<() => void> = []
+  let disposed = false
 
   const run = () => {
-    // Run cleanup from previous execution
+    if (disposed) return
     if (cleanup) {
-      cleanup()
+      try {
+        cleanup()
+      } catch (err) {
+        console.error('Effect cleanup error:', err)
+      }
       cleanup = undefined
     }
-    // Run effect and capture new cleanup
-    cleanup = fn()
+    if (dependencies) {
+      cleanup = fn()
+    } else {
+      unsubscribes.forEach((unsub) => unsub())
+      const [result, deps] = track(fn)
+      unsubscribes = [...deps].map((dep) => dep.subscribe(run))
+      cleanup = result
+    }
   }
 
-  // Subscribe to all dependencies
-  const unsubscribes = dependencies.map((dep) => dep.subscribe(run))
-
-  // Run effect immediately
+  if (dependencies) {
+    unsubscribes = dependencies.map((dep) => dep.subscribe(run))
+  }
   run()
 
-  // Return function that unsubscribes and runs cleanup
   return () => {
+    disposed = true
     if (cleanup) {
-      cleanup()
+      try {
+        cleanup()
+      } catch (err) {
+        console.error('Effect cleanup error:', err)
+      }
       cleanup = undefined
     }
     unsubscribes.forEach((unsub) => unsub())
+    unsubscribes = []
   }
 }
diff --git a/src/renderer.ts b/src/renderer.ts
--- a/src/renderer.ts
+++ b/src/renderer.ts
@@ -5,6 +5,7 @@ import type { WaveSurferOptions } from './wavesurfer.js'
 import { createDragStream } from './reactive/drag-stream.js'
 import { createScrollStream } from './reactive/scroll-stream.js'
 import { effect } from './reactive/store.js'
+import { Scope } from './scope.js'
 
 type ChannelData = utils.ChannelData
 
@@ -33,22 +34,28 @@ class Renderer extends EventEmitter<RendererEvents> {
   private canvasWrapper: HTMLElement
   private progressWrapper: HTMLElement
   private cursor: HTMLElement
-  private timeouts: Array<() => void> = []
   private isScrollable = false
   private audioData: AudioBuffer | null = null
   private resizeObserver: ResizeObserver | null = null
   private lastContainerWidth = 0
   private isDragging = false
-  private subscriptions: (() => void)[] = []
-  private unsubscribeOnScroll: (() => void)[] = []
+  private scope = new Scope()
+  // Recreated (disposed + replaced) at the top of render()/reRender(), exactly
+  // where `unsubscribeOnScroll.forEach(...); unsubscribeOnScroll = []` used to run.
+  private scrollRenderScope = this.scope.child()
+  // Recreated at the top of render() only, matching the original
+  // `timeouts.forEach(clear); timeouts = []` there. Each pending delay()
+  // registers its cancellation on the delayScope current at call time, so
+  // both the next render() pass and destroy() can cancel it.
+  private delayScope = this.scope.child()
+  private disposeDragStream: (() => void) | null = null
   private dragStream: { signal: any; cleanup: () => void } | null = null
   private scrollStream: { scrollData: any; percentages: any; bounds: any; cleanup: () => void } | null = null
   private containerInlinePadding = 0
 
   constructor(options: WaveSurferOptions, audioElement?: HTMLElement) {
     super()
 
-    this.subscriptions = []
     this.options = options
 
     const parent = this.parentFromOptionsContainer(options.container)
@@ -117,7 +124,11 @@ class Renderer extends EventEmitter<RendererEvents> {
       const { left, right } = this.scrollStream!.bounds.value
       this.emit('scroll', startX, endX, left, right)
     }, [this.scrollStream.percentages, this.scrollStream.bounds])
-    this.subscriptions.push(unsubscribeScroll)
+    this.scope.add(unsubscribeScroll)
+    this.scope.add(() => {
+      this.scrollStream?.cleanup()
+      this.scrollStream = null
+    })
 
     // Re-render the waveform on container resize
     if (typeof ResizeObserver === 'function') {
@@ -145,6 +156,10 @@ class Renderer extends EventEmitter<RendererEvents> {
     if (this.dragStream) return
 
     this.dragStream = createDragStream(this.wrapper)
+    this.disposeDragStream = this.scope.add(() => {
+      this.dragStream?.cleanup()
+      this.dragStream = null
+    })
 
     const unsubscribeDrag = effect(() => {
       const drag = this.dragStream!.signal.value
@@ -164,7 +179,7 @@ class Renderer extends EventEmitter<RendererEvents> {
       }
     }, [this.dragStream.signal])
 
-    this.subscriptions.push(unsubscribeDrag)
+    this.scope.add(unsubscribeDrag)
   }
 
   private calculateInlinePadding(): void {
@@ -270,8 +285,8 @@ class Renderer extends EventEmitter<RendererEvents> {
     if (options.dragToSeek === true || typeof this.options.dragToSeek === 'object') {
       this.initDrag()
     } else {
-      this.dragStream?.cleanup()
-      this.dragStream = null
+      this.disposeDragStream?.()
+      this.disposeDragStream = null
     }
 
     this.options = options
@@ -307,31 +322,30 @@ class Renderer extends EventEmitter<RendererEvents> {
     this.wrapper.removeEventListener('click', this.onClickWrapper)
     this.wrapper.removeEventListener('dblclick', this.onDblClickWrapper)
 
-    // Clean up all timeouts
-    this.timeouts.forEach((clear) => clear())
-    this.timeouts = []
+    this.scope.dispose()
+    // A Renderer instance IS reused after WaveSurfer.destroy(): a subsequent
+    // load() reaches render(), and setOptions() reaches reRender(). A
+    // disposed Scope hands back pre-disposed children from child(), so
+    // without recreating here, render()/reRender()'s own scope resets would
+    // install permanently-disposed scrollRenderScope/delayScope and any
+    // lazy-render scroll subscription registered afterward would be torn
+    // down the instant it's added (see renderMultiCanvas()). Recreate fresh
+    // scopes exactly as Player/WaveSurfer do.
+    this.scope = new Scope()
+    this.scrollRenderScope = this.scope.child()
+    this.delayScope = this.scope.child()
 
-    this.subscriptions.forEach((unsubscribe) => unsubscribe())
     this.container.remove()
     if (this.resizeObserver) {
       this.resizeObserver.disconnect()
       this.resizeObserver = null
     }
-    this.unsubscribeOnScroll?.forEach((unsubscribe) => unsubscribe())
-    this.unsubscribeOnScroll = []
-    if (this.dragStream) {
-      this.dragStream.cleanup()
-      this.dragStream = null
-    }
-    if (this.scrollStream) {
-      this.scrollStream.cleanup()
-      this.scrollStream = null
-    }
   }
 
   private createDelay(delayMs = 10): () => Promise<void> {
     let timeout: ReturnType<typeof setTimeout> | undefined
     let rejectFn: (() => void) | undefined
+    let deregister: (() => void) | undefined
 
     const onClear = () => {
       if (timeout) {
@@ -344,11 +358,11 @@ class Renderer extends EventEmitter<RendererEvents> {
       }
     }
 
-    this.timeouts.push(onClear)
-
     return () => {
       return new Promise<void>((resolve, reject) => {
-        // Clear any pending delay
+        // Drop the previous registration (a no-op if its delayScope was
+        // already replaced by render()) and clear any pending delay
+        deregister?.()
         onClear()
         // Store reject function for cleanup
         rejectFn = reject
@@ -358,6 +372,9 @@ class Renderer extends EventEmitter<RendererEvents> {
           rejectFn = undefined
           resolve()
         }, delayMs)
+        // Register on the CURRENT delayScope so the next render() pass and
+        // destroy() can both cancel this pending delay
+        deregister = this.delayScope.add(onClear)
       })
     }
   }
@@ -601,7 +618,7 @@ class Renderer extends EventEmitter<RendererEvents> {
         utils.getLazyRenderRange({ scrollLeft, totalWidth, numCanvases }).forEach((index) => draw(index))
       })
 
-      this.unsubscribeOnScroll.push(unsubscribe)
+      this.scrollRenderScope.add(unsubscribe)
     }
   }
 
@@ -631,12 +648,12 @@ class Renderer extends EventEmitter<RendererEvents> {
 
   async render(audioData: AudioBuffer) {
     // Clear previous timeouts
-    this.timeouts.forEach((clear) => clear())
-    this.timeouts = []
+    this.delayScope.dispose()
+    this.delayScope = this.scope.child()
 
     // Clear scroll subscriptions from previous render
-    this.unsubscribeOnScroll.forEach((unsubscribe) => unsubscribe())
-    this.unsubscribeOnScroll = []
+    this.scrollRenderScope.dispose()
+    this.scrollRenderScope = this.scope.child()
 
     // Clear the canvases
     this.canvasWrapper.innerHTML = ''
@@ -694,8 +711,8 @@ class Renderer extends EventEmitter<RendererEvents> {
   }
 
   reRender() {
-    this.unsubscribeOnScroll.forEach((unsubscribe) => unsubscribe())
-    this.unsubscribeOnScroll = []
+    this.scrollRenderScope.dispose()
+    this.scrollRenderScope = this.scope.child()
 
     // Return if the waveform has not been rendered yet
     if (!this.audioData) return
diff --git a/src/scope.ts b/src/scope.ts
new file mode 100644
--- /dev/null
+++ b/src/scope.ts
@@ -0,0 +1,124 @@
+/**
+ * A disposal tree: the single ownership primitive for listeners, timers,
+ * observers, signals subscriptions and child lifetimes. destroy() anywhere
+ * in wavesurfer is expressed as disposing a scope.
+ */
+export class Scope {
+  private disposers: Array<() => void> = []
+  private children = new Set<Scope>()
+  private parent: Scope | null = null
+  private _disposed = false
+  private abortController: AbortController | null = null
+
+  get disposed(): boolean {
+    return this._disposed
+  }
+
+  /** Register a disposer. Returns a function that runs it early and deregisters it. */
+  add(dispose: () => void): () => void {
+    if (this._disposed) {
+      // Late registration: dispose immediately so nothing can leak past dispose()
+      this.safeRun(dispose)
+      return () => undefined
+    }
+    this.disposers.push(dispose)
+    return () => {
+      const index = this.disposers.indexOf(dispose)
+      if (index !== -1) {
+        this.disposers.splice(index, 1)
+        this.safeRun(dispose)
+      }
+    }
+  }
+
+  child(): Scope {
+    const child = new Scope()
+    if (this._disposed) {
+      child.dispose()
+      return child
+    }
+    child.parent = this
+    this.children.add(child)
+    return child
+  }
+
+  listen(
+    target: EventTarget,
+    type: string,
+    fn: EventListenerOrEventListenerObject,
+    options?: boolean | AddEventListenerOptions,
+  ): () => void {
+    target.addEventListener(type, fn, options)
+    return this.add(() => target.removeEventListener(type, fn, options))
+  }
+
+  timeout(fn: () => void, ms: number): () => void {
+    const id = setTimeout(() => {
+      remove()
+      fn()
+    }, ms)
+    const remove = this.add(() => clearTimeout(id))
+    return remove
+  }
+
+  interval(fn: () => void, ms: number): () => void {
+    const id = setInterval(fn, ms)
+    return this.add(() => clearInterval(id))
+  }
+
+  raf(fn: FrameRequestCallback): () => void {
+    const id = requestAnimationFrame((time) => {
+      remove()
+      fn(time)
+    })
+    const remove = this.add(() => cancelAnimationFrame(id))
+    return remove
+  }
+
+  /** Observe element for resize. On dispose, unobserves only this element (safe if observer is shared). */
+  observeResize(observer: ResizeObserver, el: Element): void {
+    observer.observe(el)
+    this.add(() => observer.unobserve(el))
+  }
+
+  abortSignal(): AbortSignal {
+    if (!this.abortController) {
+      this.abortController = new AbortController()
+      if (this._disposed) this.abortController.abort()
+    }
+    return this.abortController.signal
+  }
+
+  dispose(): void {
+    if (this._disposed) return
+    this._disposed = true
+
+    if (this.parent) {
+      this.parent.children.delete(this)
+      this.parent = null
+    }
+
+    // Children first
+    for (const child of [...this.children]) {
+      child.dispose()
+    }
+    this.children.clear()
+
+    // Own disposers, LIFO
+    const disposers = this.disposers
+    this.disposers = []
+    for (let i = disposers.length - 1; i >= 0; i--) {
+      this.safeRun(disposers[i])
+    }
+
+    this.abortController?.abort()
+  }
+
+  private safeRun(fn: () => void): void {
+    try {
+      fn()
+    } catch (err) {
+      console.error('Scope disposer error:', err)
+    }
+  }
+}
diff --git a/src/state/wavesurfer-state.ts b/src/state/wavesurfer-state.ts
--- a/src/state/wavesurfer-state.ts
+++ b/src/state/wavesurfer-state.ts
@@ -101,6 +101,7 @@ export interface PlayerSignals {
 export function createWaveSurferState(playerSignals?: PlayerSignals): {
   state: WaveSurferState
   actions: WaveSurferActions
+  dispose: () => void
 } {
   // Use Player signals if provided, otherwise create new ones
   const currentTime = playerSignals?.currentTime ?? signal(0)
@@ -132,6 +133,8 @@ export function createWaveSurferState(playerSignals?: PlayerSignals): {
     return duration.value > 0 ? currentTime.value / duration.value : 0
   }, [currentTime, duration])
 
+  const computeds = [isPaused, canPlay, isReady, progress, progressPercent]
+
   // Public read-only state
   const state: WaveSurferState = {
     currentTime,
@@ -184,7 +187,14 @@ export function createWaveSurferState(playerSignals?: PlayerSignals): {
     setAudioBuffer: (buffer: AudioBuffer | null) => {
       audioBuffer.set(buffer)
       if (buffer) {
-        duration.set(buffer.duration)
+        // Don't clobber an already-valid duration (e.g. reported by media
+        // metadata) with the AudioBuffer's duration, which can differ
+        // fractionally due to sample-rate resampling or encoder padding.
+        // Mirrors the media-first precedence in WaveSurfer.getDuration().
+        const current = duration.value
+        if (current === 0 || Number.isNaN(current) || current === Infinity) {
+          duration.set(buffer.duration)
+        }
       }
     },
 
@@ -205,5 +215,9 @@ export function createWaveSurferState(playerSignals?: PlayerSignals): {
     },
   }
 
-  return { state, actions }
+  const dispose = () => {
+    computeds.forEach((c) => c.dispose())
+  }
+
+  return { state, actions, dispose }
 }
diff --git a/src/wavesurfer.ts b/src/wavesurfer.ts
--- a/src/wavesurfer.ts
+++ b/src/wavesurfer.ts
@@ -4,10 +4,10 @@ import * as dom from './dom.js'
 import Fetcher from './fetcher.js'
 import Player from './player.js'
 import Renderer from './renderer.js'
+import { Scope } from './scope.js'
 import Timer from './timer.js'
 import WebAudioPlayer from './webaudio.js'
 import { createWaveSurferState, type WaveSurferState, type WaveSurferActions } from './state/wavesurfer-state.js'
-import { setupStateEventEmission } from './reactive/state-event-emitter.js'
 
 export type WaveSurferOptions = {
   /** Required: an HTML element or selector where the waveform will be rendered */
@@ -162,16 +162,15 @@ class WaveSurfer extends Player<WaveSurferEvents> {
   private plugins: GenericPlugin[] = []
   private decodedData: AudioBuffer | null = null
   private stopAtPosition: number | null = null
-  protected subscriptions: Array<() => void> = []
-  protected mediaSubscriptions: Array<() => void> = []
+  protected scope: Scope = new Scope()
+  private mediaEventScope = this.scope.child()
   protected abortController: AbortController | null = null
   private _isDestroyed = false
   private _loadVersion = 0
 
   // Reactive state
   private wavesurferState: WaveSurferState
   private wavesurferActions: WaveSurferActions
-  private reactiveCleanups: Array<() => void> = []
 
   public static readonly BasePlugin = BasePlugin
   public static readonly dom = dom
@@ -218,6 +217,17 @@ class WaveSurfer extends Player<WaveSurferEvents> {
     })
     this.wavesurferState = state
     this.wavesurferActions = actions
+    // Intentionally NOT registering the returned `dispose` with `this.scope`:
+    // the state's signal graph (base signals + computeds) is owned by this
+    // WaveSurfer instance for its entire lifetime, not by the per-load Scope.
+    // `destroy()` disposes and recreates `this.scope` to support a supported
+    // destroy -> load() reuse pattern; if the state's computeds were disposed
+    // there too, they'd be permanently frozen after the first destroy since
+    // nothing ever recreates them. The computeds hold no external resources
+    // (DOM listeners, timers, etc.) -- disposing them buys nothing beyond
+    // what letting the instance (and its closures) get garbage-collected
+    // already provides. `dispose` remains part of createWaveSurferState's
+    // public return value for direct/standalone users of the state module.
 
     this.timer = new Timer()
 
@@ -227,7 +237,6 @@ class WaveSurfer extends Player<WaveSurferEvents> {
     this.initPlayerEvents()
     this.initRendererEvents()
     this.initTimerEvents()
-    this.initReactiveState()
     this.initPlugins()
 
     // Read the initial URL before load has been called
@@ -257,7 +266,7 @@ class WaveSurfer extends Player<WaveSurferEvents> {
 
   private initTimerEvents() {
     // The timer fires every 16ms for a smooth progress animation
-    this.subscriptions.push(
+    this.scope.add(
       this.timer.on('tick', () => {
         if (!this.isSeeking()) {
           const currentTime = this.updateProgress()
@@ -276,53 +285,56 @@ class WaveSurfer extends Player<WaveSurferEvents> {
     )
   }
 
-  private initReactiveState() {
-    // Bridge reactive state to EventEmitter for backwards compatibility
-    this.reactiveCleanups.push(
-      setupStateEventEmission(this.wavesurferState, {
-        emit: this.emit.bind(this),
-      }),
-    )
-  }
-
   private initPlayerEvents() {
     if (this.isPlaying()) {
       this.emit('play')
       this.timer.start()
     }
 
-    this.mediaSubscriptions.push(
+    this.mediaEventScope.add(
       this.onMediaEvent('timeupdate', () => {
         const currentTime = this.updateProgress()
         this.emit('timeupdate', currentTime)
       }),
+    )
 
+    this.mediaEventScope.add(
       this.onMediaEvent('play', () => {
         this.emit('play')
         this.timer.start()
       }),
+    )
 
+    this.mediaEventScope.add(
       this.onMediaEvent('pause', () => {
         this.emit('pause')
         this.timer.stop()
         this.stopAtPosition = null
       }),
+    )
 
+    this.mediaEventScope.add(
       this.onMediaEvent('emptied', () => {
         this.timer.stop()
         this.stopAtPosition = null
       }),
+    )
 
+    this.mediaEventScope.add(
       this.onMediaEvent('ended', () => {
         this.emit('timeupdate', this.getDuration())
         this.emit('finish')
         this.stopAtPosition = null
       }),
+    )
 
+    this.mediaEventScope.add(
       this.onMediaEvent('seeking', () => {
         this.emit('seeking', this.getCurrentTime())
       }),
+    )
 
+    this.mediaEventScope.add(
       this.onMediaEvent('error', () => {
         this.emit('error', (this.getMediaElement().error ?? new Error('Media error')) as Error)
         this.stopAtPosition = null
@@ -331,48 +343,62 @@ class WaveSurfer extends Player<WaveSurferEvents> {
   }
 
   private initRendererEvents() {
-    this.subscriptions.push(
-      // Seek on click
+    // Seek on click
+    this.scope.add(
       this.renderer.on('click', (relativeX, relativeY) => {
         if (this.options.interact) {
           this.seekTo(relativeX)
           this.emit('interaction', relativeX * this.getDuration())
           this.emit('click', relativeX, relativeY)
         }
       }),
+    )
 
-      // Double click
+    // Double click
+    this.scope.add(
       this.renderer.on('dblclick', (relativeX, relativeY) => {
         this.emit('dblclick', relativeX, relativeY)
       }),
+    )
 
-      // Scroll
+    // Scroll
+    this.scope.add(
       this.renderer.on('scroll', (startX, endX, scrollLeft, scrollRight) => {
         const duration = this.getDuration()
         this.emit('scroll', startX * duration, endX * duration, scrollLeft, scrollRight)
       }),
+    )
 
-      // Redraw
+    // Redraw
+    this.scope.add(
       this.renderer.on('render', () => {
         this.emit('redraw')
       }),
+    )
 
-      // RedrawComplete
+    // RedrawComplete
+    this.scope.add(
       this.renderer.on('rendered', () => {
         this.emit('redrawcomplete')
       }),
+    )
 
-      // DragStart
+    // DragStart
+    this.scope.add(
       this.renderer.on('dragstart', (relativeX) => {
         this.emit('dragstart', relativeX)
       }),
+    )
 
-      // DragEnd
+    // DragEnd
+    this.scope.add(
       this.renderer.on('dragend', (relativeX) => {
         this.emit('dragend', relativeX)
       }),
+    )
 
-      // Resize
+    // Resize
+    this.scope.add(
       this.renderer.on('resize', () => {
         this.emit('resize')
       }),
@@ -409,7 +435,7 @@ class WaveSurfer extends Player<WaveSurferEvents> {
       })
 
       // Clear debounce timeout on destroy
-      this.subscriptions.push(() => {
+      this.scope.add(() => {
         clearTimeout(debounce)
         unsubscribeDrag()
       })
@@ -425,19 +451,21 @@ class WaveSurfer extends Player<WaveSurferEvents> {
   }
 
   private unsubscribePlayerEvents() {
-    this.mediaSubscriptions.forEach((unsubscribe) => unsubscribe())
-    this.mediaSubscriptions = []
+    this.mediaEventScope.dispose()
+    this.mediaEventScope = this.scope.child()
   }
 
   /** Set new wavesurfer options and re-render it */
   public setOptions(options: Partial<WaveSurferOptions>) {
     this.options = Object.assign({}, this.options, options)
     if (options.duration && !options.peaks) {
       this.decodedData = Decoder.createBuffer(this.exportPeaks(), options.duration)
+      this.wavesurferActions.setAudioBuffer(this.decodedData)
     }
     if (options.peaks && options.duration) {
       // Create new decoded data buffer from peaks and duration
       this.decodedData = Decoder.createBuffer(options.peaks, options.duration)
+      this.wavesurferActions.setAudioBuffer(this.decodedData)
     }
     this.renderer.setOptions(this.options)
 
@@ -460,11 +488,12 @@ class WaveSurfer extends Player<WaveSurferEvents> {
     this.plugins.push(plugin)
 
     // Unregister plugin on destroy
-    const unsubscribe = plugin.once('destroy', () => {
-      this.plugins = this.plugins.filter((p) => p !== plugin)
-      this.subscriptions = this.subscriptions.filter((fn) => fn !== unsubscribe)
-    })
-    this.subscriptions.push(unsubscribe)
+    const remove = this.scope.add(
+      plugin.once('destroy', () => {
+        this.plugins = this.plugins.filter((p) => p !== plugin)
+        remove()
+      }),
+    )
 
     return plugin
   }
@@ -520,9 +549,17 @@ class WaveSurfer extends Player<WaveSurferEvents> {
 
     this.emit('load', url)
 
+    this.wavesurferActions.setUrl(url || '')
+    if (channelData) {
+      this.wavesurferActions.setPeaks(channelData)
+    } else {
+      this.wavesurferActions.setPeaks(null)
+    }
+
     if (!this.options.media && this.isPlaying()) this.pause()
 
     this.decodedData = null
+    this.wavesurferActions.setAudioBuffer(null)
     this.stopAtPosition = null
 
     // Abort any ongoing fetch before starting a new one
@@ -558,9 +595,7 @@ class WaveSurfer extends Player<WaveSurferEvents> {
       if (staticDuration) {
         resolve(staticDuration)
       } else {
-        this.mediaSubscriptions.push(
-          this.onMediaEvent('loadedmetadata', () => resolve(this.getDuration()), { once: true }),
-        )
+        this.mediaEventScope.add(this.onMediaEvent('loadedmetadata', () => resolve(this.getDuration()), { once: true }))
       }
     })
 
@@ -589,6 +624,7 @@ class WaveSurfer extends Player<WaveSurferEvents> {
     if (this._isDestroyed || loadVersion !== this._loadVersion) return
 
     if (this.decodedData) {
+      this.wavesurferActions.setAudioBuffer(this.decodedData)
       this.emit('decode', this.getDuration())
       this.renderer.render(this.decodedData)
     }
@@ -622,6 +658,7 @@ class WaveSurfer extends Player<WaveSurferEvents> {
       throw new Error('No audio loaded')
     }
     this.renderer.zoom(minPxPerSec)
+    this.wavesurferActions.setZoom(minPxPerSec)
     this.emit('zoom', minPxPerSec)
   }
 
@@ -754,10 +791,13 @@ class WaveSurfer extends Player<WaveSurferEvents> {
     this.emit('destroy')
     this.abortController?.abort()
     this.plugins.forEach((plugin) => plugin.destroy())
-    this.subscriptions.forEach((unsubscribe) => unsubscribe())
-    this.unsubscribePlayerEvents()
-    this.reactiveCleanups.forEach((cleanup) => cleanup())
-    this.reactiveCleanups = []
+    this.scope.dispose()
+    // Reusing an instance after destroy() is a supported behavior (see the
+    // loadAudio comment about issue #3637), so fresh scopes must replace the
+    // disposed ones -- a disposed Scope runs late registrations immediately,
+    // which would otherwise break a subsequent load()/setMediaElement() call.
+    this.scope = new Scope()
+    this.mediaEventScope = this.scope.child()
     this.timer.destroy()
     this.renderer.destroy()
     super.destroy()
diff --git a/src/webaudio.ts b/src/webaudio.ts
--- a/src/webaudio.ts
+++ b/src/webaudio.ts
@@ -10,6 +10,7 @@ type WebAudioPlayerEvents = {
   volumechange: []
   emptied: []
   ended: []
+  error: [error: Error]
 }
 
 function setWebAudioSessionPlayback() {
@@ -45,6 +46,7 @@ class WebAudioPlayer extends EventEmitter<WebAudioPlayerEvents> {
   public crossOrigin: string | null = null
   public seeking = false
   public autoplay = false
+  public error: Error | null = null
 
   constructor(audioContext?: AudioContext) {
     super()
@@ -115,6 +117,8 @@ class WebAudioPlayer extends EventEmitter<WebAudioPlayerEvents> {
   set src(value: string) {
     this.currentSrc = value
     this._duration = undefined
+    // A new load starts with a clean slate, like HTMLMediaElement.error
+    this.error = null
 
     if (!value) {
       this.buffer = null
@@ -146,6 +150,8 @@ class WebAudioPlayer extends EventEmitter<WebAudioPlayerEvents> {
       .catch((err) => {
         // Emit error for proper error handling
         console.error('WebAudioPlayer load error:', err)
+        this.error = err instanceof Error ? err : new Error(String(err))
+        this.emit('error', this.error)
       })
   }
 
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
