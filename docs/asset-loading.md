# Asset loading — the resource manager, loaders, and pools

## Co-Authored-By: Claude <noreply@anthropic.com>

Every screen clip, unit animation, portrait, and sound bank is an **asset** streamed in from disk at runtime,
not baked into the app. [`ui-system.md`](./ui-system.md) shows the UI *asking* for its art
(`loadFullPageMovieClip`); this doc is the pipeline **underneath** that request — the machinery that fetches a
URL, turns the bytes into a usable object, tracks when a batch is ready, and throws it away when a scene ends.
It is consumed by far more than the UI: the battle board, animations, and sound all pull through the same path.

> **Depth note.** Architecture narrative, not a per-class reference. Paths are under `_decompiled/scripts/`
> (the generated full source); line numbers are spot-checked but drift on re-decompile — treat them as "look
> near here." `[Inference]` marks anything read off the decompile rather than traced end-to-end.

## Two managers, not a singleton

There is no global "asset system." The game holds **two** `ResourceManager` instances, built side by side in
`game/cfg/GameConfig.as`:

- **`resman`** (`GameConfig.as:429`) — general game assets (art, animations, data, sound), rooted at the asset path.
- **`guiresman`** (`GameConfig.as:430`) — the UI resource SWFs (`great_hall.swf`, `battle_initiative.swf`, …),
  rooted at the gui path.

Keeping them separate lets the UI SWFs live under their own root and be managed as a group. Two more facts frame
everything below:

- **Everything is keyed by its URL string.** A manager holds a dictionary of URL → `Resource`
  (`ResourceManager.m_resources`), so asking twice for the same URL returns the **same** object — assets are
  shared and reference-counted, never loaded twice.
- **Completion is plain Flash events + callbacks.** There is no Signals library and no Starling `AssetManager`
  here. Loaders finish through a `Function` callback; resources announce themselves with a native
  `flash.events` event; and the objects they produce are native `flash.display` objects — the client renders
  on the native display list, not Starling (see [`ui-system.md`](./ui-system.md)); loading is plain Flash end to end.

## The manager and the base resource

**`ResourceManager`** (`engine/resource/ResourceManager.as:9`) has essentially one entry point:

```
getResource(url, ResourceClass, group?, loaderFactory?)   // ResourceManager.as:44
```

It (1) returns the cached `Resource` if this URL was already requested; otherwise (2) constructs a
`new ResourceClass(url, this, loaderFactory)`, calls `load()` on it, and caches it; then (3) adds a **reference**
(refcount) and enrolls the resource in the caller's group and any active progress monitors. URL resolution goes
through `getFullUrl` (`:133`), which maps a logical path to the real hashed filename via an `AssetIndex`.

**`Resource`** (`engine/resource/Resource.as:10`, `extends EventDispatcher implements IResource`) is the base
every asset type extends. Its lifecycle is small:

- `loadFromUrl()` (`:155`) hands the full URL to the **loader factory**, which returns the right loader for this
  asset type and starts fetching.
- When the loader finishes it calls back into `onLoadComplete` (`:183`), which either defers to a dependency
  **tree** (below) or sets `loaded = true`.
- The `loaded` setter (`:73`) is the moment of truth: it fires `ResourceLoadedEvent("complete")` (`:89`).
  Consumers subscribe with `addResourceListener(fn)` (`:226`) — which, helpfully, fires *immediately* if the
  resource is already loaded, so there's no race between "ask" and "subscribe."

**Reference counting.** Each `Resource` owns a `Refcount` (`engine/core/util/Refcount.as`). `addReference()`
bumps it; `releaseReference()` (`:24`) drops it and, when it hits zero, fires an `"unload"` event so the manager
can free the asset. This is why the same clip shared by three screens survives until the *last* one lets go.

## Grouping: tree vs group vs monitor

Three small classes coordinate *sets* of resources — they look similar but do different jobs:

| Class | Question it answers | Key method |
|---|---|---|
| **`ResourceTree`** | "This asset **depends on** others — don't call it ready until its children are too." | `checkChildren()` (`ResourceTree.as:44`) marks the root loaded only once every child has loaded. |
| **`ResourceGroup`** | "Load this **ad-hoc set** together and tell me when the whole batch is in." | `addResource()` (`ResourceGroup.as:32`) enrolls; `release()` (`:43`) drops the group's references — the **per-scene unload-everything** call. |
| **`ResourceMonitor`** | "How far along is this batch?" — the loading bar. | Tracks remaining/total and exposes `percent`; a page or scene watches one to drive its progress display. |

A `ResourceTree` is a **dependency fan-out**: the root resource loads, then its declared children load, and the
root only reports complete when the whole subtree is in. A `ResourceGroup` is looser — a bag of resources loaded
together and released together when a scene tears down. A `ResourceMonitor` observes without owning; a
`GamePage`, for instance, holds one to know when its screen is fully loaded.

## The resource type hierarchy

The `ResourceClass` you pass to `getResource` decides what the bytes *become*. Two branches hang off `Resource`
— one for **raw data**, one for **display objects**:

```
Resource                         engine/resource/Resource.as:10   (EventDispatcher, IResource)
├─ URLResource                   URLResource.as:7                 raw URLLoader payload
│  ├─ URLBinaryResource          URLBinaryResource.as:6           binary ByteArray
│  │  └─ CompressedTextResource  CompressedTextResource.as:3      gzipped text/JSON
│  └─ DefResource                def/DefResource.as:8             a "def" data blob; auto-loads its children
│     ├─ AnimClipResource        AnimClipResource.as:12           → an animation clip
│     ├─ SoundLibraryResource    engine/sound/def/…:6             a bank of sounds
│     └─ Iso{Anim,Vfx}LibraryResource   engine/battle/def/…       battle animation / effect libraries
└─ DisplayResource               DisplayResource.as:6             wraps flash.display.Loader (a live display object)
   ├─ SwfResource                SwfResource.as:7                 a whole SWF's symbol library
   ├─ MovieClipResource          MovieClipResource.as:7           one "file.swf/Symbol" → a MovieClip
   └─ BitmapResource             BitmapResource.as:10             a bitmap / PNG
```

The one method to know here is **`SwfResource.getClass(symbol)`** (`SwfResource.as:53`). It asks its loader
`getLibraryClass(symbol)` (`DisplayResourceLoader.as:163`), which looks the symbol up in the loaded SWF's
**application domain** (its private symbol table) and returns the class. **This is the exact mechanism behind the
resource-SWF class-resolution model** — the reason a gui symbol class runs from *inside* its SWF. The full
consequences (symbol linkage vs by-name, why some gui classes can't be patched from the app) are owned by
[`architecture.md`](./architecture.md) → "Resource SWFs and runtime class resolution"; here it is just "how a
symbol name becomes a class."

`DefResource` is special: it reads a data blob and **auto-pulls the children it references into a
`ResourceTree`**, so requesting one def transparently loads its whole dependency graph. The broader
`Def`/`Vars`/`Wrangler` data pattern that builds on this is documented once in `data-model.md` (planned — P3;
see [`doc-gaps.md`](./doc-gaps.md)); here `DefResource` is simply "the resource type that fans out."

## The loaders

A `Resource` doesn't fetch bytes itself — it delegates to a **loader**, and there are two, under
`engine/resource/loader/`:

- **`URLResourceLoader`** (`URLResourceLoader.as:13`) wraps `flash.net.URLLoader` — it pulls **raw bytes**, and
  transparently un-gzips a `.z` file when the download completes (`onLoadComplete`, `:97`). This is the loader
  behind every `URLResource`/`DefResource`.
- **`DisplayResourceLoader`** (`DisplayResourceLoader.as:16`) produces a **live display object**. It first uses a
  URL loader to fetch the bytes, then calls `flash.display.Loader.loadBytes` (`:93`) to turn them into a display
  object *plus* an application domain (the symbol table that `getLibraryClass` reads). This is the loader behind
  every `DisplayResource`/`SwfResource`.

**Naming trap:** the base classes are named `IResourceLoader` / `IURLResourceLoader` / `IDisplayResourceLoader`,
but the `I` prefix is misleading — they are **concrete abstract base classes**, not AS3 `interface`s. Their
"pure virtual" methods literally `throw` if a subclass forgets to override them (`IResourceLoader.as:7`), and the
shared completion plumbing lives in the base: `emitCompleteCallback` (`:52`) is the single `Function` call every
loader makes to hand its result back to the `Resource`.

**The fork's one edit lives here.** Which application domain a SWF loads into is decided at
`DisplayResourceLoader.as:73`: normally each SWF gets a fresh, isolated domain (`null`), but our patch routes
`battle_initiative.swf` into `ApplicationDomain.currentDomain` so its by-name references resolve to the app's
patched classes. The reasoning (and the `[Inference]` comment right above that line) is catalogued in
[`patch-inventory.md`](./patch-inventory.md) → "Resource & scene loading (2)".

## Object pooling

Spawning and discarding hundreds of display objects during a battle would thrash the garbage collector, so hot
paths **reuse** objects through a pool. `ObjectPool` (`engine/core/util/ObjectPool.as:5`) is the generic
primitive: `pop()` hands out a recycled object (or builds one), and `reclaim()` / `push()` return it, discarding
only past a limit.

The three display-object pools — `MovieClipPool`, `BitmapPool`, `AnimClipSpritePool` (all in
`engine/resource/`) — are **managers of** `ObjectPool`s, one pool per SWF symbol, keyed by URL: `MovieClipPool`,
for example, builds a fresh `ObjectPool` per clip on first request (`MovieClipPool.addPool`) and recycles from it
thereafter. Their primary consumer is the isometric battle board — `BattleBoardView` constructs all three in one
place (`engine/battle/board/view/BattleBoardView.as:113–115`) to recycle the unit clips, bitmaps, and animation
sprites that churn every frame of combat.

## Three pipelines, end to end

The same machinery serves three shapes of request. Following each once shows how the parts fit:

- **(A) A display asset (a screen or unit clip).** `getResource(url, MovieClipResource)` → a `DisplayResource`
  whose `DisplayResourceLoader` fetches bytes and `loadBytes` them into a domain → `set loaded` fires `"complete"`
  → the UI's `addResourceListener` callback runs and pulls the clip out via `getClass`/`getMovieClip`. This is
  what `ui-system.md`'s `loadFullPageMovieClip` bottoms out in.
- **(B) A data blob (a def).** `getResource(url, DefResource)` → a `URLResource`-family loader fetches and
  un-gzips the bytes → `DefResource` parses them and **auto-loads referenced children into a `ResourceTree`** →
  the root reports complete only when the whole tree is in.
- **(C) A whole scene, loaded together.** A scene enrolls its assets in a `ResourceGroup` and watches a
  `ResourceMonitor` for progress; the scene-load state (`SceneLoader` / `SceneLoadState`, the load-then-run pair
  from [`game-flow.md`](./game-flow.md)) waits for the group, then hands control to the running scene. When the
  scene ends, `ResourceGroup.release()` drops every reference at once and the assets unload.

## Where our fork touches this

The loader is almost entirely Stoic's original code; our footprint is deliberately tiny. The one edit is the
domain reroute at `DisplayResourceLoader.as:73` (above) — plus the closely related resource/scene handling
catalogued in [`patch-inventory.md`](./patch-inventory.md) → "Resource & scene loading (2)". Everything else in
this pipeline runs unmodified, which is why understanding it here — rather than through the patches — is the
right mental model.

## Related reading

- [`ui-system.md`](./ui-system.md) — the UI layer that consumes this pipeline (`loadFullPageMovieClip`, `guiresman`).
- [`architecture.md`](./architecture.md) — the resource-SWF class-resolution model that `getLibraryClass` implements.
- [`game-flow.md`](./game-flow.md) — the scene load-then-run states that drive grouped loads (pipeline C).
- [`patch-inventory.md`](./patch-inventory.md) — the `battle_initiative.swf` domain reroute and scene-loading edits.
- [`subsystem-index.md`](./subsystem-index.md) — class-level "where do I look for X?" for `engine/resource`.
