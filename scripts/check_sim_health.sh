#!/usr/bin/env bash
set -euo pipefail

# This script is a quick health gate for simulation/control readiness.
# It checks:
# 1) controller_manager service discovery
# 2) required controllers are active
# If any check fails, it exits non-zero so CI/PR gates can catch regressions.

WS_DIR="${WS_DIR:-$HOME/tri_bot_ws}"
mkdir -p "$WS_DIR/log"
export ROS_LOG_DIR="$WS_DIR/log"

# ROS setup scripts read optional vars that may be unset under `set -u`.
set +u
source /opt/ros/humble/setup.bash
source "$WS_DIR/install/setup.bash"
set -u

echo "[INFO] Checking controller_manager service..."
# Test purpose:
# - Confirms the control backend is alive and discoverable.
# - If this fails, Gazebo/gz_ros2_control/controller_manager did not initialize correctly.
if ! ros2 service list | grep -q '^/controller_manager/list_controllers$'; then
  echo "[FAIL] /controller_manager/list_controllers is not available."
  echo "[HINT] Make sure simulation is running in another terminal."
  exit 1
fi

echo "[INFO] Checking controller states..."
controllers_output="$(ros2 control list_controllers)"
echo "$controllers_output"

# Test purpose:
# - Ensures state broadcaster is active so joint states are available for monitoring/debug.
if ! grep -q '^joint_state_broadcaster .* active$' <<< "$controllers_output"; then
  echo "[FAIL] joint_state_broadcaster is not active."
  exit 1
fi

# Test purpose:
# - Ensures position command path is active before command tests are run.
if ! grep -q '^position_controller .* active$' <<< "$controllers_output"; then
  echo "[FAIL] position_controller is not active."
  exit 1
fi

echo "[OK] Simulation health check passed."
