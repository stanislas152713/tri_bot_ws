#!/usr/bin/env bash
set -euo pipefail

# Fixed decision-control workflow launcher:
# 1) Verify simulation/controllers are healthy
# 2) Start tvc_allocator
# 3) Start state_machine
# 4) Keep both alive until interrupted

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_DIR="${WS_DIR:-$(dirname "$SCRIPT_DIR")}"
mkdir -p "$WS_DIR/log"
export ROS_LOG_DIR="$WS_DIR/log"

# Runtime parameters (override with env vars if needed)
ALLOCATOR_TIMEOUT_S="${ALLOCATOR_TIMEOUT_S:-2.0}"
ALLOCATOR_RATE_HZ="${ALLOCATOR_RATE_HZ:-50.0}"
TRANSITION_SECONDS="${TRANSITION_SECONDS:-2.0}"
STATE_MACHINE_RATE_HZ="${STATE_MACHINE_RATE_HZ:-10.0}"

# ROS setup scripts read optional vars that may be unset under `set -u`.
set +u
source /opt/ros/humble/setup.bash
source "$WS_DIR/install/setup.bash"
set -u

echo "[INFO] Step 1/3: checking simulation health..."
"$SCRIPT_DIR/check_sim_health.sh"

ALLOC_PID=""
STATE_PID=""

cleanup() {
  local code=$?
  trap - EXIT INT TERM

  if [[ -n "${STATE_PID}" ]] && kill -0 "${STATE_PID}" 2>/dev/null; then
    kill "${STATE_PID}" 2>/dev/null || true
  fi

  if [[ -n "${ALLOC_PID}" ]] && kill -0 "${ALLOC_PID}" 2>/dev/null; then
    kill "${ALLOC_PID}" 2>/dev/null || true
  fi

  wait "${STATE_PID}" 2>/dev/null || true
  wait "${ALLOC_PID}" 2>/dev/null || true
  exit "${code}"
}

trap cleanup EXIT INT TERM

echo "[INFO] Step 2/3: starting tvc_allocator..."
ros2 run tri_bot_control tvc_allocator --ros-args \
  -p command_timeout_s:="${ALLOCATOR_TIMEOUT_S}" \
  -p publish_rate_hz:="${ALLOCATOR_RATE_HZ}" &
ALLOC_PID=$!

sleep 1

echo "[INFO] Step 3/3: starting state_machine..."
ros2 run tri_bot_decision state_machine --ros-args \
  -p transition_seconds:="${TRANSITION_SECONDS}" \
  -p publish_rate_hz:="${STATE_MACHINE_RATE_HZ}" &
STATE_PID=$!

echo "[OK] Decision-control chain is running."
echo "[INFO] PIDs: tvc_allocator=${ALLOC_PID}, state_machine=${STATE_PID}"
echo "[INFO] Press Ctrl+C to stop both nodes."

wait "${ALLOC_PID}" "${STATE_PID}"
