# Polygon regression checks

Proposed against Drawing.luau blob 020c1078ff991f8d161cab957ccaf817a16f0ab5.
The patch does not change other drawing types.

## Offline

Run python3 tests/polygon_geometry.py from a checkout with the patch applied.
Requires Python 3 and liblua5.4 (for example Debian package liblua5.4-0).
The runner executes the exact rasterizer extracted from Drawing.luau, then
executes the entire file under a minimal Roblox state model. No pip packages.
This checks Lua-compatible syntax, coverage and disjointness, reversed winding,
concavity, crossing edges, clipping, fractional/flat edges, repeated points,
zero-area cases, style updates, equal-value transparency assignment, listener
cleanup and cache removal. It is not a Luau typecheck or Roblox rendering test.

## Client visual harness

In a supported client environment, load the patched library and then execute
tests/polygon_visual.client.luau. Do not use a session with important drawings
for any additional cleardrawcache checks.

For Studio Play Solo, make a temporary ModuleScript named Drawing alongside
the visual LocalScript in StarterPlayerScripts. Paste the patched library into
it, prepend this local compatibility shim:

    local function getgenv() return _G end

Replace only this initialization line in the temporary copy:

    UI.Parent = gethui()

with:

    UI.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

Append return Drawing. The temporary adapter bypasses the existing library's
CoreGui/getgenv environment assumptions; it is not part of the library patch.
Use a desktop viewport at least 740x620.

Expected checks:

- Pink areas follow the vertices; checkerboard stays visible outside polygons.
- At alpha 0.5, fill has uniform opacity with no darker internal diagonals.
- Concave indentation remains empty; crossing quad fills two even-odd lobes.
- Collinear triangle has no fill. Repeated-vertex quad reduces to a triangle.
- F toggles between only perimeter strokes and only fill, retaining thickness.
- T toggles opacity and repeats assignment without exposing root rectangles.
- V hides and restores all parts; C recolors all parts.
- M moves the first triangle. Watch aliasing and frame time in MicroProfiler.
- Resize the client smaller and larger: clipped fill must rebuild correctly.
- R and D remove the first two objects. Q disconnects harness events and removes
  its remaining drawings and background without clearing unrelated drawings.
- In Explorer, change polygon ZIndex through the proxy while overlapping another
  Drawing shape; confirm order both above and below it. All child parts must
  carry the same ZIndex as their polygon root. Also check equal-ZIndex ordering
  against existing library behavior.
- In an otherwise empty test session, call cleardrawcache, resize, and confirm
  no fill/outline descendants survive and no disconnected update errors occur.
- Run on a physical mobile client / different DPI and graphics settings.

## Technique and limits

Perimeter order is A-B-C[-D]-A. Either winding is supported. Self-crossing quads
use even-odd coverage. No fill is produced for collapsed polygons. This defines
previously unspecified filled-quad behavior without adding public properties.

Each pixel center is tested by scanline intersections with half-open edges.
Horizontal intervals become disjoint integer Frame rectangles. Identical spans
on adjacent rows merge vertically. Consequently fill opacity is applied once
per covered pixel; there is no triangulation seam or double alpha on a diagonal.
Edges are binary pixel coverage, not antialiased vector edges. Subpixel polygons
may cover zero pixels. Live rendering must verify Roblox maps adjacent integer
Frames to contiguous pixels at the target device scale.

The transparent zero-size root stays at screen origin, with ClipsDescendants
false. Child coordinates are absolute screen pixels. Its identity stays in
DrawingCache. Filled mode hides perimeter segments, preserving prior semantics.
Drawing Transparency remains opacity: 1 opaque, 0 transparent.

Rasterization is O(viewport height * vertex count), with at most two spans per
row for a quad. It is clipped to UI.AbsoluteSize, so large offscreen coordinates
do not allocate offscreen rows. No per-frame update loop is added. Geometry is
dirty only after vertex or viewport changes and is deferred while hidden or in
outline mode. Color, alpha, thickness and ZIndex changes do not rasterize.
GUI parts are pooled lazily and retain peak allocation until Remove/Destroy.
Pool size is bounded by twice the largest viewport height seen while filled;
unchanged rectangular quads use one fill Frame after row merging.

Many large moving polygons can still be expensive. Benchmark representative
object counts in a client before rollout; this is a compatibility-first default,
not a claim of constant-cost polygon rendering. A texture-mask renderer could
reduce instances but introduces asset availability and sampling assumptions.
EditableImage introduces platform enablement, memory and display-update limits.
No external asset, editable-image entitlement or rotated clipping is required.

## Validation recorded during proposal preparation

- PASS: 2016 geometry cases compared against an independent per-pixel oracle.
- PASS: full-file execution under mocked API state/lifecycle tests.
- Not run: Luau analyzer, Roblox Studio, live rendering, mobile/DPI, MicroProfiler.
- The tests validate geometry and state, not actual pixels or performance.
