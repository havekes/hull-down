# Hull Down

A World of Tanks–style 3D vehicle combat game built with **Godot 4.x** for macOS.

Players drive a tracked tank on a flat testing arena, controlling the hull independently
from an orbiting third-person camera. The turret and gun traverse toward the camera's aim
point at a fixed speed, and firing uses a dynamic dispersion reticle (bloom) that expands
while moving or turning and tightens when stationary.

## Scope

**Epic 1 — Foundation & Playable Flat-Map Milestone**

Incremental, playable-at-every-step tickets:

- `SETUP-01` — Godot 4 macOS project init, input map, flat lit test arena
- `TANK-01` — CSG tank hierarchy (hull/turret/gun) & chase camera
- `TANK-02` — Kinematic tracked-vehicle driving controller
- `TANK-03` — Decoupled turret traverse & gun elevation
- `TANK-04` — Reticle bloom HUD & firing cycle

## Setup

**Requirements**
- macOS
- [Godot 4.x](https://godotengine.org/download) (Forward+ or Compatibility renderer)

**Run**
1. Open Godot.
2. Import the project by selecting this folder (the one containing `project.godot`).
3. Press **F5** (or the Play button) to launch the main scene, `res://scenes/TestArena.tscn`.

**Controls**
- `W` / `S` / `A` / `D` or arrow keys — drive (pivot-in-place when stationary)
- Mouse — orbit third-person camera (click to capture, `Esc` to release)
- Mouse wheel — camera zoom
- Left mouse button — fire

## Project Layout

```
res://scenes/   # maps, vehicles, ui
res://scripts/  # controllers, mechanics
res://assets/   # materials, meshes, audio
```
