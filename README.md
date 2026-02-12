This is the ROS2 workspace for EUN.

---

To use this repo, clone it and install the following:
**Operating System**

- **Ubuntu Jammy Jellyfish**: https://cdimage.ubuntu.mirror.onlime.sl/ubuntu/daily-live/20220417/ 
If you are running it on a virtual machine, make sure you download the desktop image with the right chip (e.g., ARM64 for M1/M2/M3 Mac). 

- **ROS2 humble (Ardupilot requires this specific version)**
  - **Install**: https://docs.ros.org/en/humble/Installation/Ubuntu-Install-Debs.html 
 
- **Ardupilot**
  - **Install**: https://ardupilot.org/dev/docs/building-setup-linux.html#building-setup-linux 

- **Gazebo Harmonic** 
  - **Install**: https://gazebosim.org/docs/harmonic/install_ubuntu/ 

- **Ardupilot Gazebo Plugin** 
  - **Install**: https://github.com/ArduPilot/ardupilot_gazebo 

**SITL** 
  - SITL is installed with Ardupilot. 
  - To test SITL: https://ardupilot.org/dev/docs/setting-up-sitl-on-linux.html 
  - Using SITL with Gazebo: https://ardupilot.org/dev/docs/sitl-with-gazebo.html

---

To build the workspace, run the following:
```
cd ~/tri_bot_ws //replace the path with the path to your local tri_bot_ws
rosdep install --from-paths src --ignore-src -r -y
colcon build --symlink-install
source install/setup.bash
```
