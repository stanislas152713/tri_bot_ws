#!/usr/bin/env bash
set -euo pipefail

# Use directory containing this script to find workspace root (e.g. .../tri_bot_ws/scripts -> .../tri_bot_ws).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_DIR="${WS_DIR:-$(dirname "$SCRIPT_DIR")}"

# ROS setup scripts read optional vars that may be unset under `set -u`.
set +u
source /opt/ros/humble/setup.bash
source "$WS_DIR/install/setup.bash"
set -u

# Improve GUI startup reliability on systems with limited OpenGL support.
export LIBGL_ALWAYS_SOFTWARE=1
mkdir -p "$WS_DIR/log"
export ROS_LOG_DIR="$WS_DIR/log"

echo "[INFO] Starting tri_bot simulation..."
echo "[INFO] Workspace: $WS_DIR"
echo "[INFO] Launch args: use_software_gl:=true"

ros2 launch tri_bot_description gazebo.launch.py use_software_gl:=true
