This is the ROS2 workspace for EUN (tri_bot).

---

## Software

To use this repo, use **Ubuntu 22.04 (Jammy Jellyfish)**. Clone the repo and install the following in order.

- **Ubuntu Jammy Jellyfish (22.04)**
  - **Install**: [Official 22.04 LTS](https://releases.ubuntu.com/22.04/) or [daily image](https://cdimage.ubuntu.mirror.onlime.sl/ubuntu/daily-live/20220417/).
  - On a VM (e.g. M1/M2/M3 Mac), use the **ARM64** desktop image.

- **ROS 2 Humble** (required by ArduPilot)
  - **Install**: https://docs.ros.org/en/humble/Installation/Ubuntu-Install-Debs.html

- **ArduPilot**
  - **Install**: https://ardupilot.org/dev/docs/building-setup-linux.html#building-setup-linux

- **Gazebo Harmonic** (required for this project and ArduPilot SITL; **do not install Fortress**)
  - **Install**: https://gazebosim.org/docs/harmonic/getstarted/ Find the harmonic release.

- **ArduPilot Gazebo plugin**
  - **Install**: https://github.com/ArduPilot/ardupilot_gazebo  
  - Build for **Gazebo Harmonic**: set `GZ_VERSION=harmonic` and build as per the repo README.

- **Optional – RViz** (for `display.launch.py`)
  - `sudo apt install ros-humble-rviz2`

- **SITL** (comes with ArduPilot)
  - Test SITL: https://ardupilot.org/dev/docs/setting-up-sitl-on-linux.html
  - SITL with Gazebo: https://ardupilot.org/dev/docs/sitl-with-gazebo.html

**Note (VM / no OpenGL 3.3):** If the Gazebo window fails to open (e.g. "OpenGL 3.3 is not supported"), run `export LIBGL_ALWAYS_SOFTWARE=1` before launching Gazebo.

---

After everything is installed, run the following to build the workspace:
```
cd ~/tri_bot_ws //replace the path with the path to your local tri_bot_ws
rosdep install --from-paths src --ignore-src -r -y
colcon build
source install/setup.bash
```

## Startup sequence (validated)

Use this sequence for a reliable simulation and controller startup.

### Terminal A - Launch Gazebo + robot
```
cd ~/tri_bot_ws
source /opt/ros/humble/setup.bash
source ~/tri_bot_ws/install/setup.bash
export LIBGL_ALWAYS_SOFTWARE=1
ros2 launch tri_bot_description gazebo.launch.py use_software_gl:=true
```

### Terminal B - Check controller status
```
source /opt/ros/humble/setup.bash
source ~/tri_bot_ws/install/setup.bash
ros2 control list_controllers
```

Expected result:
- `joint_state_broadcaster ... active`
- `position_controller ... active`

### Terminal B - Send one command test (optional)
```
ros2 topic pub --once /position_controller/commands std_msgs/msg/Float64MultiArray "{data: [0.0, 0.0, 0.1, -0.1]}"
```

Plan: Scroll down to the bottom for the english version!
Phase 1 - 稳定化（短期，1-2 周）
固化一个默认“稳定启动配置”（GUI 与 headless 两套命令都可用）。
在 launch 中加入更清晰日志/错误提示（例如 controller_manager 未就绪时提示下一步）。
增加 quick_test 脚本：一键检查 controllers 状态并发送小幅测试命令。
Phase 2 - 控制能力建设（中期）
在 tri_bot_control 实现最小控制节点（订阅目标，发布到 /position_controller/commands）。
定义并固定关节命令约束（限幅、速率限制、回中策略）。
用 tri_bot_interfaces 补充必要状态/命令消息（若现有不够）。
Phase 3 - 决策与模式切换（中期）
在 tri_bot_decision 实现基础状态机（DISARMED/AIR/TRANSITION/UNDERWATER）。
把状态机输出映射到控制目标（翼面、TVC、节流等）。
增加最小安全机制（超时回中、无命令保持、模式切换保护）。
Phase 4 - 观测与验证（中后期）
做一套标准测试场景：
启动自检
控制器激活
单步动作回归
模式切换回归
加入自动化验证（至少脚本级 CI smoke test）。
记录“已知限制与排障手册”（尤其 OpenGL/GPU/VM 差异）。
Phase 5 - 面向任务应用（长期）
对接更高层任务（导航/目标跟踪/任务规划）。
引入传感器仿真与闭环感知。
与 ArduPilot/SITL 形成更完整的联合测试流程。
Current State (English)
Your project has moved from a scaffold to a working simulation-control prototype.
Major milestones achieved:
Simulation path works: tri_bot_description launches in Gazebo Harmonic and spawns the robot.
Control pipeline works: gz_ros2_control -> controller_manager -> controllers is functional.
Controllers activate reliably: both joint_state_broadcaster and position_controller reach active.
Command path validated: publishing to /position_controller/commands works.
Repeatable startup documented: stable startup and checks are now in README.md.
Current project profile:
Strength: robot model + Gazebo integration + ros2_control execution loop.
Gap: real decision logic (tri_bot_decision), real control algorithm (tri_bot_control), and automated system tests.
Future Plan (English)
Phase 1 - Stabilization (near-term, 1-2 weeks)
Keep a default stable startup profile (GUI and headless workflows).
Improve launch-time diagnostics (clear messages when controller_manager is unavailable).
Add a quick_test script for one-command health check + tiny command test.
Phase 2 - Control Capability (mid-term)
Implement a minimal control node in tri_bot_control (subscribe target, publish command array).
Add command constraints (saturation, rate limiting, return-to-neutral policy).
Extend tri_bot_interfaces only where needed.
Phase 3 - Decision & Mode Logic (mid-term)
Implement a basic state machine in tri_bot_decision (DISARMED/AIR/TRANSITION/UNDERWATER).
Map state outputs to actuator targets (wings, TVC, throttle).
Add basic safety guards (timeout neutralization, mode-transition protection).
Phase 4 - Verification & Observability (mid/late-term)
Define standard test scenarios:
startup sanity
controller activation
single-step motion regression
mode transition regression
Add automated smoke tests (script-level CI minimum).
Build a known-issues troubleshooting guide (especially OpenGL/GPU/VM variance).
Phase 5 - Mission-Level Extension (long-term)
Integrate higher-level tasks (navigation/target tracking/planning).
Add sensor simulation for perception-in-the-loop behavior.
Strengthen ArduPilot/SITL integrated workflow.