# VR Pruning — Meta Quest 3 Mixed Reality Tree Pruning

Built & Developed by **CAIML, SKUAST Kashmir**.

A standalone **Meta Quest 3 Mixed Reality (Color Passthrough)** and **PCVR / Desktop Preview** tree pruning simulator built with **Godot 4.7.2**, **GodotOpenXRVendors v5.2.0**, and **Jolt Physics**.

## Features
- **Meta Quest 3 Color Passthrough (MR)**: Places a potted botanical tree anchored to your real room floor (`OpenXRFbPassthroughExtension`, boundaryless mode), with a grounded contact shadow and invisible floor collision so severed branches fall and bounce naturally onto your real floor.
- **Real-Time 3D Branch Splitting**: Cuts branches at the exact tool blade intersection point `t`, sealing both the remaining tree stub and the severed falling `RigidBody3D` branch with realistic annual growth-ring / green cambium wood cross-sections, wood-chip bursts, and spatialized audio.
- **3 Articulated Realistic Tools**:
  - **Bypass Secateurs** (`<= 2.4 cm` twigs, analog trigger jaw squeeze)
  - **Long-Reach Bypass Loppers** (`<= 5.0 cm` medium branches)
  - **Curved Japanese Pull Pruning Saw** (any limb thickness via realistic back-and-forth sawing motion)
- **3 Botanical Tree Species**: Honeycrisp Apple (Open-Center Orchard), Japanese Maple (`Acer palmatum`), and Garden Olive (Rejuvenation), with procedural bark/normal/roughness PBR shaders and wind-swaying alpha-tested foliage cards.
- **Arboriculture Training & Collar-Cut Grading**: Evaluates branch collar cut distance, identifies deadwood, diseased limbs, crossing branches, upright watersprouts, and basal suckers, and enforces realistic tool capacity limits.
- **Touch Controllers + Hand Tracking + Desktop Mode**: Supports Quest 3 Touch Controllers (with haptics), controller-free Meta Hand Tracking + pinch aim, and automatic Desktop 3D preview when launched without a VR headset.

## Quest 3 Controls
- **Right Trigger / Hand Pinch**: Squeeze Secateurs/Loppers to cut, or click buttons on the 3D Arborist Control Board. Move Pruning Saw back-and-forth across thick limbs to saw through.
- **Right A Button**: Cycle pruning tool (`Secateurs -> Loppers -> Saw`).
- **Right B Button**: Undo last cut.
- **Left Grip (Hold)**: Move & rotate the tree anywhere in your room.
- **Left X Button**: Toggle Mixed Reality Passthrough vs. Sunlit Garden Terrace.
- **Left Y Button**: Re-center tree `1.1 m` in front of you.

## Laptop / Desktop Preview Controls
Run directly on your laptop with:
```powershell
powershell -ExecutionPolicy Bypass -File .\run_laptop_preview.ps1
```
- **WASD / Q / E**: Move camera (`Arrow Keys` or `Right-Drag` to look around, `Scroll Wheel` to zoom)
- **Left-Click**: Cut branch / click 3D HUD panel buttons (hold while moving for Pull Saw)
- **1 / 2 / 3 / Tab**: Switch tool (`Secateurs`, `Loppers`, `Pull Saw`)
- **M**: Toggle Passthrough preview / Garden sky
- **H**: Toggle Arborist Hints
- **Z**: Undo last cut
- **R**: Generate new tree

## Deploy to Meta Quest 3
1. If building from a fresh clone in **Godot 4.7.2**, run **Project -> Install Android Build Template...** once so Godot populates `android/build/libs/` (excluded from Git due to GitHub's 100 MB file limit), and keep `org.gradle.daemon=false` in `android/build/gradle.properties`.
2. Enable **Developer Mode** on your Meta Quest 3 via the Meta Horizon mobile app.
3. Connect Quest 3 via USB-C and accept **Allow USB Debugging** inside the headset.
4. Run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\deploy_quest3.ps1
   ```
   (Add `-Rebuild` to re-export `builds/VRPruning-Quest3.apk` before installing.)

## Run Headless Verification Tests
```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --path . --xr-mode off --script res://tests/test_pruning.gd
```

