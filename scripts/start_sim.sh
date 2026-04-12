#!/usr/bin/env bash
# Launch the full ArduPilot SITL + Gazebo simulation for tri_bot.
#
# Usage:
#   ./scripts/start_sim.sh                # normal launch
#   ./scripts/start_sim.sh --software-gl  # force Mesa software rendering
#
# SITL runs in the foreground so MAVProxy gets interactive input.
# Ctrl+C stops SITL, which then kills Gazebo automatically.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_DIR="${WS_DIR:-$(dirname "$SCRIPT_DIR")}"
ARDUPILOT_DIR="${ARDUPILOT_DIR:-$HOME/ardupilot}"

SOFTWARE_GL=false
for arg in "$@"; do
    case "$arg" in
        --software-gl) SOFTWARE_GL=true ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

if [ ! -f "$WS_DIR/install/setup.bash" ]; then
    echo "[ERROR] Workspace not built. Run: cd $WS_DIR && colcon build"
    exit 1
fi

if [ ! -f "$ARDUPILOT_DIR/Tools/autotest/sim_vehicle.py" ]; then
    echo "[ERROR] ArduPilot not found at $ARDUPILOT_DIR"
    echo "[HINT] Set ARDUPILOT_DIR to the correct path."
    exit 1
fi

set +u
source /opt/ros/humble/setup.bash
source "$WS_DIR/install/setup.bash"
set -u

if $SOFTWARE_GL; then
    export LIBGL_ALWAYS_SOFTWARE=1
    export MESA_GL_VERSION_OVERRIDE=3.3
    export MESA_GLSL_VERSION_OVERRIDE=330
fi

mkdir -p "$WS_DIR/log"
export ROS_LOG_DIR="$WS_DIR/log"

cleanup() {
    echo ""
    echo "[INFO] Shutting down Gazebo..."
    [ -n "${GZ_PID:-}" ] && kill "$GZ_PID" 2>/dev/null && wait "$GZ_PID" 2>/dev/null
    echo "[INFO] Done."
}
trap cleanup EXIT INT TERM

echo "[INFO] Starting tri_bot simulation (ArduPilot SITL)"
echo "[INFO] Workspace:  $WS_DIR"
echo "[INFO] ArduPilot:  $ARDUPILOT_DIR"
echo "[INFO] Software GL: $SOFTWARE_GL"
echo ""

echo "[INFO] === Launching Gazebo + tri_bot ==="
ros2 launch tri_bot_description ardupilot.launch.py \
    use_software_gl:=$SOFTWARE_GL &
GZ_PID=$!

echo "[INFO] Waiting 8s for Gazebo to load..."
sleep 8

echo "[INFO] === Launching ArduPilot SITL (foreground) ==="
echo "============================================="
echo "  MAVProxy commands: arm throttle, rc 1 1700"
echo "  Press Ctrl+C to stop everything"
echo "============================================="
echo ""

cd "$ARDUPILOT_DIR"
Tools/autotest/sim_vehicle.py \
    -v ArduPlane \
    -f gazebo-zephyr \
    --model JSON \
    --console \
    --map
