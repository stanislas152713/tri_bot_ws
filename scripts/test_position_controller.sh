#!/usr/bin/env bash
set -euo pipefail

# This script performs a safe smoke test for command execution.
# It sends a small command sequence to /position_controller/commands:
# neutral -> small deflection -> neutral.
# Goal: verify command transport + controller response without aggressive motion.

WS_DIR="${WS_DIR:-$HOME/tri_bot_ws}"
mkdir -p "$WS_DIR/log"
export ROS_LOG_DIR="$WS_DIR/log"

# ROS setup scripts read optional vars that may be unset under `set -u`.
set +u
source /opt/ros/humble/setup.bash
source "$WS_DIR/install/setup.bash"
set -u

publish_once() {
  local values="$1"
  echo "[INFO] Publishing command: $values"
  # Test action:
  # - Publish one command sample to the controller input topic.
  # - --once keeps test deterministic and avoids continuous command streaming.
  ros2 topic pub --once /position_controller/commands \
    std_msgs/msg/Float64MultiArray \
    "{data: $values}"
}

echo "[INFO] Running safe position controller test sequence..."
echo "[INFO] Order: [left_wing, right_wing, tvc_pitch, tvc_yaw]"

# 1) Neutral
# Test purpose:
# - Establish a known safe baseline before deflection.
publish_once "[0.0, 0.0, 0.0, 0.0]"
sleep 1

# 2) Small TVC deflection
# Test purpose:
# - Validate that non-zero command is accepted and produces observable motion.
publish_once "[0.0, 0.0, 0.1, -0.1]"
sleep 2

# 3) Back to neutral
# Test purpose:
# - Verify return-to-neutral command path after motion.
publish_once "[0.0, 0.0, 0.0, 0.0]"

echo "[OK] Test sequence sent."
