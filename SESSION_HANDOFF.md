# Session Handoff: tri_bot ArduPilot Control Wiring

## Project Overview

`tri_bot_ws` is a ROS 2 Humble + Gazebo Harmonic workspace for a UAV (EUN/tri_bot) that transitions between air and water. The model has folding wings, ailerons, rudders, twin wing-mounted propellers, and a retractable landing gear. Control is via ArduPilot SITL communicating with Gazebo through `ArduPilotPlugin`.

## Key Architecture Decision (this session)

**ArduPilot is the sole control backend.** The `gz_ros2_control` path has been dropped because:

1. The Humble apt binary for `gz_ros2_control` targets Gazebo Fortress, not Harmonic -- it fails with `[GzPluginHook] missing`
2. On real hardware, ArduPilot runs on a Pixhawk and `gz_ros2_control` doesn't exist
3. Maintaining two control paths adds complexity with no benefit

ROS 2's role is now **companion computer**: perception (cameras), decision-making (`state_machine` for air/water transitions), and future high-level commands via MAVROS. ArduPilot handles all low-level joint control.

## Current State of the Codebase

### Kinematic tree (`tri_bot.xacro`)

```
base_footprint (fixed) --> base_link
  base_link (fixed)    --> camera_night_link, camera_zoom_link, tvc_link, wheel_frame
  base_link (revolute)  --> left_wing, right_wing, left_rudder, right_rudder, imu_link
  left_wing (revolute)  --> left_aileron
  left_wing (continuous) --> left_propeller
  right_wing (revolute)  --> right_aileron
  right_wing (continuous) --> right_propeller
  wheel_frame (continuous) --> wheel_fl, wheel_fr, wheel_bl, wheel_br
```

14 movable joints total, but only 2 (wing folds) are wired to ArduPilot. The other 6 actuated joints (ailerons, rudders, propellers) have no control channel mapping yet.

### Placeholder joint origins (user will fix from CAD)

These joints have empty or rough `xyz` values -- user will fill in from SolidWorks measurements:

- `left_propeller_joint` -- `xyz=""`
- `right_propeller_joint` -- `xyz=""`
- `wheel_frame_joint` -- `xyz="0 0 0"` (needs negative Z offset)
- `wheel_fl/fr/bl/br_joint` -- rough placeholders

### Files and their status

| File | Status | Notes |
|------|--------|-------|
| `src/tri_bot_description/urdf/tri_bot.xacro` | Needs changes | Add 6 ArduPilot channels; remove `gz_ros2_control` block |
| `src/tri_bot_description/config/tri_bot.parm` | Does not exist | Must create with SERVOx_FUNCTION mapping |
| `src/tri_bot_description/config/controllers.yaml` | Dead config | No longer loaded (gz_ros2_control removed) |
| `src/tri_bot_description/launch/ardupilot.launch.py` | Needs changes | Remove `use_ardupilot:=true` xacro arg |
| `src/tri_bot_description/launch/display.launch.py` | OK | RViz-only, no control path |
| `scripts/start_sim.sh` | Needs changes | Add `--add-param-file` for tri_bot.parm |
| `scripts/test_position_controller.sh` | Needs rewrite | Should test via `rc` commands, not `/position_controller/commands` |
| `scripts/test_decision_control_acceptance.sh` | Needs update | Comments need ArduPilot-path context |
| `src/tri_bot_control/src/tvc_allocator.cpp` | Keep as-is | Wings-only; future MAVROS bridge will replace downstream |
| `CONTROL_INTERFACE.md` | Needs rewrite | Document ArduPilot servo channel contract |
| `README.md` | Needs update | Remove `gz_ros2_control` install instructions |

## Agreed Servo Channel Mapping

| Plugin `channel=` | ArduPilot SERVO# | MAVProxy `rc` | Joint | Control Type |
|--------------------|------------------|---------------|-------|-------------|
| 0 | SERVO1 | `rc 1` | `left_wing_fold_joint` | POSITION |
| 1 | SERVO2 | `rc 2` | `right_wing_fold_joint` | POSITION |
| 2 | SERVO3 | `rc 3` | `left_propeller_joint` | VELOCITY |
| 3 | SERVO4 | `rc 4` | `right_propeller_joint` | VELOCITY |
| 4 | SERVO5 | `rc 5` | `left_aileron_joint` | POSITION |
| 5 | SERVO6 | `rc 6` | `right_aileron_joint` | POSITION |
| 6 | SERVO7 | `rc 7` | `left_rudder_joint` | POSITION |
| 7 | SERVO8 | `rc 8` | `right_rudder_joint` | POSITION |

Wheels are passive (free-spinning, not mapped to any servo channel).

Differential thrust: left and right propellers on separate channels for yaw-via-thrust capability.

## Design Decisions Made

1. **Drop `gz_ros2_control`** -- ArduPilot is the only control backend; `use_ardupilot` xacro arg removed
2. **Differential thrust** -- CH3 left propeller, CH4 right propeller (not single throttle)
3. **Skip joint origins** -- User fills in xyz values from CAD/RViz; not blocking control wiring
4. **Keep `tvc_allocator` wings-only** -- It stays as a 2-element wing fold commander; future MAVROS bridge handles communication to ArduPilot
5. **`gazebo-zephyr` + override** -- Keep `-f gazebo-zephyr` for JSON transport, overlay `tri_bot.parm` via `--add-param-file`
6. **`ARMING_CHECK 0`** -- Disable arming checks in sim `.parm` to unblock testing (fixes "Gyros inconsistent")

## Implementation Plan (5 tasks)

### Task 1: Add 6 ArduPilot control channels to xacro

In `tri_bot.xacro`, inside the ArduPilotPlugin block, add `<control channel="N">` blocks for:
- CH2/CH3: propellers (VELOCITY type, `multiplier` sets max rad/s)
- CH4/CH5: ailerons (POSITION type, cmd range +/-0.436 rad)
- CH6/CH7: rudders (POSITION type, cmd range +/-0.436 rad)

Also add 6 `ApplyJointForce` plugin entries, one per joint.

### Task 2: Remove gz_ros2_control path from xacro

Delete the `<xacro:unless value="$(arg use_ardupilot)">` block (ros2_control + GazeboSimROS2ControlPlugin). Remove `use_ardupilot` and `controllers_file` xacro args. The ArduPilot block becomes unconditional.

### Task 3: Create `tri_bot.parm`

New file at `src/tri_bot_description/config/tri_bot.parm` with:
- SERVO1_FUNCTION through SERVO8_FUNCTION
- ARMING_CHECK 0
- Basic ArduPlane parameters for this airframe

### Task 4: Update `start_sim.sh`

- Add `--add-param-file` pointing to `tri_bot.parm`
- Remove `use_ardupilot:=true` from launch command (no longer an arg)

### Task 5: Update downstream files

- `CONTROL_INTERFACE.md` -- Rewrite for ArduPilot servo contract
- `README.md` -- Remove gz_ros2_control install, simplify to ArduPilot-only
- `ardupilot.launch.py` -- Remove `use_ardupilot:=true` xacro processing
- `test_position_controller.sh` -- Rewrite to test via `rc` commands
- `test_decision_control_acceptance.sh` -- Update comments
- `controllers.yaml` -- Mark as unused / delete

## Known Issues

1. **Joint origins are placeholders** -- propeller and wheel joint xyz values need CAD measurements. Use `ros2 launch tri_bot_description display.launch.py` in RViz to visually verify.
2. **No MAVROS bridge yet** -- The `state_machine` -> `tvc_allocator` -> `position_controller` chain targets a dead endpoint. Future work: add MAVROS node to bridge ROS 2 commands to ArduPilot servo overrides.
3. **PID tuning** -- ArduPilotPlugin PID gains for new joints are initial estimates; will need tuning in simulation.
4. **`.parm` SERVOx_FUNCTION values** -- Need to confirm correct ArduPlane function codes (e.g., 73 for ThrottleLeft, 74 for ThrottleRight, 4 for Aileron, 21 for Rudder, etc.)

## How to Test After Implementation

```bash
# Terminal A: Launch Gazebo + robot
cd ~/tri_bot_ws && source install/setup.bash
ros2 launch tri_bot_description ardupilot.launch.py

# Terminal B: Launch ArduPilot SITL (loads tri_bot.parm automatically)
./scripts/start_sim.sh

# Terminal C: Test servo channels in MAVProxy
# After "ARMED" appears:
rc 1 1700    # left wing fold
rc 3 1700    # left propeller spin
rc 5 1700    # left aileron deflect
rc 7 1700    # left rudder deflect
```
