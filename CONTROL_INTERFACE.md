# Control Interface Contract (V1 MVP)

This document defines the control-side interface contract for `tri_bot_ws`.
All control and decision changes must follow this contract unless explicitly updated in a reviewed PR.

## 1) Scope and Assumptions (V1)

- V1 focus: stable simulation and control path.
- URDF actuation is **wing fold only** (`left_wing_fold_joint`, `right_wing_fold_joint`). The TVC assembly is a **fixed** mesh on the fuselage (`tvc_base_joint`).
- Active control in V1 is wing folding only.
- No complex linkage dynamics or advanced behavior strategy in this phase.

## 2) Frame and Units

- Body frame convention:
  - `+X` forward
  - `+Y` left
  - `+Z` up
- Joint angles in radians (`rad`).
- Command timeout in seconds (`s`).
- Command rates in hertz (`Hz`).

## 3) Runtime Control Path (Current)

Primary actuator command topic:

- Topic: `/position_controller/commands`
- Type: `std_msgs/msg/Float64MultiArray`
- Required order:
  1. `left_wing_fold_joint`
  2. `right_wing_fold_joint`

Command shape:

- `[left_wing, right_wing]`

## 4) Input Interface for Minimal Control Node

Minimal control node (`tvc_allocator`) input:

- Topic: `wing_fold_cmd`
- Type: `std_msgs/msg/Float32MultiArray`
- Required data format:
  - `data[0] = left_wing_cmd`
  - `data[1] = right_wing_cmd`

If fewer than 2 values are provided, command is rejected and warning is logged.

## 5) Safety and Limits (V1)

Wing command clamping:

- Left wing (`left_wing_fold_joint`): `[-1.57, 0.0]`
- Right wing (`right_wing_fold_joint`): `[0.0, 1.57]`

Timeout behavior:

- Parameter: `command_timeout_s` (default `0.5`)
- If no valid input is received for longer than timeout:
  - publish neutral command `[0.0, 0.0]`

Publish loop:

- Parameter: `publish_rate_hz` (default `50.0`)
- Node republishes current command continuously at configured rate.

## 6) Controller Requirements

The following controllers must be active:

- `joint_state_broadcaster`
- `position_controller`

Health check command:

```bash
./scripts/check_sim_health.sh
```

## 7) Regression Gate (Required Before Merge)

Every PR affecting control/simulation must pass:

```bash
./scripts/start_sim.sh
./scripts/check_sim_health.sh
./scripts/test_position_controller.sh
```

Attach command output summary to PR description.

## 8) Reserved Interfaces for Later Phases

These interfaces exist but are not required for V1 runtime closure:

- `tri_bot_interfaces/msg/TvcSetpoint`
- `tri_bot_interfaces/msg/VehicleState`

They are reserved for V2 integration (`decision -> control -> state feedback`).

## 9) Change Control Rules

- No silent changes to:
  - topic names
  - message types
  - channel order
  - units
  - limits
- Any interface change must update this file in the same PR.
- At least one teammate review is required for interface changes.
