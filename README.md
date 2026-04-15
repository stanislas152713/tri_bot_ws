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

- **ROS 2 packages needed for this workspace** (build, Gazebo launch, and control)
  - All of the following are required for `gazebo.launch.py` and controller spawners. Install in one go (ROS 2 Humble):
    ```bash
    sudo apt update
    sudo apt install -y \
      ros-humble-ros-gz-sim \
      ros-humble-gz-ros2-control \
      ros-humble-ros2-control \
      ros-humble-ros2-controllers \
      ros-humble-xacro \
      ros-humble-robot-state-publisher
    ```
  - What each does:
    - **ros_gz_sim**: spawns the robot in Gazebo and can start the sim.
    - **gz_ros2_control**: Gazebo system plugin (avoids "couldn't find shared library [gz_ros2_control-system]").
    - **ros2_control** / **ros2_controllers**: provide `controller_manager`, `joint_state_broadcaster`, and `position_controller`.
    - **xacro**: used by the launch to generate URDF from `tri_bot.xacro`.
    - **robot_state_publisher**: publishes robot state from URDF/joint states.
  - If you still see **"Failed to load system plugin [gz_ros2_control-system] : couldn't find shared library"**:
    1. Start the launch from a shell where you have run `source /opt/ros/humble/setup.bash` (and `source install/setup.bash`).
    2. If needed, add the ROS 2 lib path before launching:
       ```bash
       export GZ_SIM_SYSTEM_PLUGIN_PATH="/opt/ros/humble/lib:$GZ_SIM_SYSTEM_PLUGIN_PATH"
       ```
    3. If you use **Gazebo Harmonic** and the Humble deb does not work, build `gz_ros2_control` from source for Harmonic (see [gz_ros2_control docs](https://control.ros.org/humble/doc/gz_ros2_control/doc/index.html)).

- **Optional – RViz**
  - `sudo apt install ros-humble-rviz2` (for `display.launch.py`)

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
ros2 topic pub --once /position_controller/commands std_msgs/msg/Float64MultiArray "{data: [0.0, 0.0]}"
```