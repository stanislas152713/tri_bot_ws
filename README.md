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
  1. Install Gazebo Harmonic:
     ```bash
     sudo apt-get update
     sudo apt-get install curl lsb-release gnupg
     sudo curl https://packages.osrfoundation.org/gazebo.gpg --output /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg
     echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] https://packages.osrfoundation.org/gazebo/ubuntu-stable $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/gazebo-stable.list > /dev/null
     sudo apt-get update
     sudo apt-get install gz-harmonic
     ```
  2. Install ROS 2 bridge and ros2_control for Harmonic (after sourcing ROS 2):
     ```bash
     source /opt/ros/humble/setup.bash
     sudo apt-get install ros-humble-ros-gz-sim ros-humble-gz-ros2-control
     ```

- **ArduPilot Gazebo plugin**
  - **Install**: https://github.com/ArduPilot/ardupilot_gazebo  
  - Build for **Gazebo Harmonic**: set `GZ_VERSION=harmonic` and build as per the repo README.

- **Optional – RViz** (for `display.launch.py`)
  - `sudo apt install ros-humble-rviz2`

- **SITL** (comes with ArduPilot)
  - Test SITL: https://ardupilot.org/dev/docs/setting-up-sitl-on-linux.html
  - SITL with Gazebo: https://ardupilot.org/dev/docs/sitl-with-gazebo.html

**Note (VM / no OpenGL 3.3):** If the Gazebo window fails to open (e.g. “OpenGL 3.3 is not supported”), run `source LIBGL_ALWAYS_SOFTWARE=1` before initializing Gazebo.

---

After everything is installed, run the following to build the workspace:
```
cd ~/tri_bot_ws //replace the path with the path to your local tri_bot_ws
rosdep install --from-paths src --ignore-src -r -y
colcon build --symlink-install
source install/setup.bash
```
