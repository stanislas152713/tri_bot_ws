#!/usr/bin/env bash
set -euo pipefail

# Simple, direct acceptance test for decision-control chain.
# Assumes simulation is already running.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_DIR="${WS_DIR:-$(dirname "$SCRIPT_DIR")}"
mkdir -p "$WS_DIR/log"
export ROS_LOG_DIR="$WS_DIR/log"

set +u
source /opt/ros/humble/setup.bash
source "$WS_DIR/install/setup.bash"
set -u

"$SCRIPT_DIR/check_sim_health.sh"

ALLOC_PID=""
STATE_PID=""

cleanup() {
  trap - EXIT INT TERM
  if [[ -n "${STATE_PID}" ]]; then
    kill "${STATE_PID}" 2>/dev/null || true
  fi
  if [[ -n "${ALLOC_PID}" ]]; then
    kill "${ALLOC_PID}" 2>/dev/null || true
  fi
  wait "${STATE_PID}" 2>/dev/null || true
  wait "${ALLOC_PID}" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

echo "[INFO] Start tvc_allocator..."
ros2 run tri_bot_control tvc_allocator --ros-args \
  -p command_timeout_s:=0.8 \
  -p publish_rate_hz:=50.0 &
ALLOC_PID=$!

sleep 1

echo "[INFO] Start state_machine..."
ros2 run tri_bot_decision state_machine --ros-args \
  -p transition_seconds:=2.0 \
  -p publish_rate_hz:=10.0 &
STATE_PID=$!

sleep 1

read_data() {
  local topic="$1"
  timeout 5s ros2 topic echo --once "$topic" --field data 2>/dev/null
}

assert_close() {
  local label="$1"
  local actual_text="$2"
  local expected_csv="$3"
  python3 - "$label" "$actual_text" "$expected_csv" <<'PY'
import math
import re
import sys

label, actual_text, expected_csv = sys.argv[1], sys.argv[2], sys.argv[3]
tol = 0.05
expected = [float(x) for x in expected_csv.split(",")]

text = actual_text.strip()
if "array(" in text:
    m = re.search(r"\[([^\]]+)\]", text)
    if not m:
        print(f"[FAIL] {label}: cannot parse '{text}'")
        sys.exit(1)
    actual = [float(x.strip()) for x in m.group(1).split(",")]
else:
    lines = [ln.strip() for ln in text.splitlines() if ln.strip() and ln.strip() not in ("---", "...")]
    if any(ln.startswith("-") for ln in lines):
        actual = [float(ln[1:].strip()) for ln in lines if ln.startswith("-")]
    else:
        m = re.search(r"\[([^\]]+)\]", "\n".join(lines))
        if not m:
            print(f"[FAIL] {label}: cannot parse '{text}'")
            sys.exit(1)
        actual = [float(x.strip()) for x in m.group(1).split(",")]

if len(actual) != len(expected):
    print(f"[FAIL] {label}: len mismatch actual={actual} expected={expected}")
    sys.exit(1)

for i, (a, e) in enumerate(zip(actual, expected)):
    if math.fabs(a - e) > tol:
        print(f"[FAIL] {label}: idx={i} actual={actual} expected={expected}")
        sys.exit(1)

print(f"[PASS] {label}: actual={actual} expected={expected}")
PY
}

echo "[INFO] Case 1: DISARMED + dry"
ros2 topic pub --once /is_wet std_msgs/msg/Bool "{data: false}" >/dev/null
ros2 topic pub --once /set_mode std_msgs/msg/UInt8 "{data: 0}" >/dev/null
sleep 0.5
assert_close "wing(disarmed)" "$(read_data /wing_fold_cmd)" "0.0,0.0"
assert_close "pos(disarmed)" "$(read_data /position_controller/commands)" "0.0,0.0"

echo "[INFO] Case 2: AIR + dry"
ros2 topic pub --once /is_wet std_msgs/msg/Bool "{data: false}" >/dev/null
ros2 topic pub --once /set_mode std_msgs/msg/UInt8 "{data: 1}" >/dev/null
sleep 0.5
assert_close "wing(air)" "$(read_data /wing_fold_cmd)" "0.0,0.0"
assert_close "pos(air)" "$(read_data /position_controller/commands)" "0.0,0.0"

echo "[INFO] Case 3: AIR + wet -> TRANSITION"
ros2 topic pub --once /set_mode std_msgs/msg/UInt8 "{data: 1}" >/dev/null
ros2 topic pub --once /is_wet std_msgs/msg/Bool "{data: true}" >/dev/null
sleep 0.5
assert_close "wing(transition)" "$(read_data /wing_fold_cmd)" "-0.8,0.8"
assert_close "pos(transition)" "$(read_data /position_controller/commands)" "-0.8,0.8"

echo "[INFO] Case 4: transition done -> UNDERWATER"
sleep 2.2
assert_close "wing(underwater)" "$(read_data /wing_fold_cmd)" "-1.2,1.2"
assert_close "pos(underwater)" "$(read_data /position_controller/commands)" "-1.2,1.2"

echo "[INFO] Case 5: allocator timeout -> neutral"
kill "${STATE_PID}" 2>/dev/null || true
wait "${STATE_PID}" 2>/dev/null || true
STATE_PID=""
sleep 1.0
assert_close "pos(timeout-neutral)" "$(read_data /position_controller/commands)" "0.0,0.0"

echo "[OK] Acceptance test passed."
#!/usr/bin/env bash
set -euo pipefail

# End-to-end acceptance test for the V1 decision-control chain.
# It validates:
# 1) Mode-based wing command outputs from state_machine
# 2) End-to-end mapped outputs via tvc_allocator command publication
# 3) Allocator safety fallback to neutral on input timeout

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_DIR="${WS_DIR:-$(dirname "$SCRIPT_DIR")}"
mkdir -p "$WS_DIR/log"
export ROS_LOG_DIR="$WS_DIR/log"

TRANSITION_SECONDS="${TRANSITION_SECONDS:-2.5}"
STATE_MACHINE_RATE_HZ="${STATE_MACHINE_RATE_HZ:-10.0}"
ALLOCATOR_TIMEOUT_S="${ALLOCATOR_TIMEOUT_S:-0.8}"
ALLOCATOR_RATE_HZ="${ALLOCATOR_RATE_HZ:-50.0}"
TEST_TOPIC_TIMEOUT_S="${TEST_TOPIC_TIMEOUT_S:-1}"
TEST_TOL="${TEST_TOL:-0.05}"
ASSERT_WAIT_S="${ASSERT_WAIT_S:-4}"
RUN_ID="${RUN_ID:-$$_$RANDOM}"
TEST_NS="${TEST_NS:-/acceptance_test_${RUN_ID}}"
SET_MODE_TOPIC="${TEST_NS}/set_mode"
IS_WET_TOPIC="${TEST_NS}/is_wet"
WING_CMD_TOPIC="${TEST_NS}/wing_fold_cmd"
VEHICLE_STATE_TOPIC="${TEST_NS}/vehicle_state"
TEST_POS_CMD_TOPIC="${TEST_NS}/position_controller/commands"
ALLOC_NODE_NAME="tvc_allocator_acceptance_${RUN_ID}"
STATE_NODE_NAME="state_machine_acceptance_${RUN_ID}"

set +u
source /opt/ros/humble/setup.bash
source "$WS_DIR/install/setup.bash"
set -u

"$SCRIPT_DIR/check_sim_health.sh"

base_pub_count="$(
  ros2 topic info /position_controller/commands 2>/dev/null \
  | sed -n 's/Publisher count: //p' \
  | tr -d '[:space:]'
)"
base_pub_count="${base_pub_count:-0}"
if [[ "$base_pub_count" != "0" ]]; then
  echo "[INFO] /position_controller/commands currently has ${base_pub_count} publisher(s)."
  echo "[INFO] Acceptance test uses isolated topic and namespace:"
  echo "[INFO]   TEST_NS=${TEST_NS}"
  echo "[INFO]   TEST_POS_CMD_TOPIC=${TEST_POS_CMD_TOPIC}"
fi

ALLOC_PID=""
STATE_PID=""

cleanup() {
  local code=$?
  trap - EXIT INT TERM

  # First pass: stop known PIDs from this run.
  if [[ -n "${STATE_PID}" ]] && kill -0 "${STATE_PID}" 2>/dev/null; then
    kill "${STATE_PID}" 2>/dev/null || true
  fi

  if [[ -n "${ALLOC_PID}" ]] && kill -0 "${ALLOC_PID}" 2>/dev/null; then
    kill "${ALLOC_PID}" 2>/dev/null || true
  fi

  # Second pass: name-based cleanup to avoid stale publishers after failures.
  pkill -f "${STATE_NODE_NAME}" 2>/dev/null || true
  pkill -f "${ALLOC_NODE_NAME}" 2>/dev/null || true

  wait "${STATE_PID}" 2>/dev/null || true
  wait "${ALLOC_PID}" 2>/dev/null || true
  exit "${code}"
}

trap cleanup EXIT INT TERM

# Pre-cleanup: remove stale acceptance nodes from previous failed runs.
pkill -f "state_machine_acceptance_" 2>/dev/null || true
pkill -f "tvc_allocator_acceptance_" 2>/dev/null || true
sleep 0.2

echo "[INFO] Starting tvc_allocator for acceptance test..."
ros2 run tri_bot_control tvc_allocator --ros-args \
  -r wing_fold_cmd:="${WING_CMD_TOPIC}" \
  -r __node:="${ALLOC_NODE_NAME}" \
  -p command_timeout_s:="${ALLOCATOR_TIMEOUT_S}" \
  -p publish_rate_hz:="${ALLOCATOR_RATE_HZ}" \
  -p output_topic:="${TEST_POS_CMD_TOPIC}" &
ALLOC_PID=$!

sleep 0.7

echo "[INFO] Starting state_machine for acceptance test..."
ros2 run tri_bot_decision state_machine --ros-args \
  -r set_mode:="${SET_MODE_TOPIC}" \
  -r is_wet:="${IS_WET_TOPIC}" \
  -r wing_fold_cmd:="${WING_CMD_TOPIC}" \
  -r vehicle_state:="${VEHICLE_STATE_TOPIC}" \
  -r __node:="${STATE_NODE_NAME}" \
  -p transition_seconds:="${TRANSITION_SECONDS}" \
  -p publish_rate_hz:="${STATE_MACHINE_RATE_HZ}" &
STATE_PID=$!

sleep 1.0

wait_for_publishers() {
  local topic="$1"
  local min_count="${2:-1}"
  local timeout_s="${3:-6}"
  local deadline=$((SECONDS + timeout_s))
  local count="0"
  while (( SECONDS < deadline )); do
    count="$(
      ros2 topic info "$topic" 2>/dev/null \
      | sed -n 's/Publisher count: //p' \
      | tr -d '[:space:]'
    )"
    count="${count:-0}"
    if (( count >= min_count )); then
      return 0
    fi
    sleep 0.2
  done
  echo "[FAIL] Topic publisher not ready: ${topic} (count=${count}, need>=${min_count})"
  return 1
}

wait_for_publishers "${WING_CMD_TOPIC}" 1 8
wait_for_publishers "${TEST_POS_CMD_TOPIC}" 1 8

pub_mode() {
  local mode="$1"
  ros2 topic pub --once "${SET_MODE_TOPIC}" std_msgs/msg/UInt8 "{data: ${mode}}" >/dev/null
}

pub_wet() {
  local wet="$1"
  ros2 topic pub --once "${IS_WET_TOPIC}" std_msgs/msg/Bool "{data: ${wet}}" >/dev/null
}

pub_mode_burst() {
  local mode="$1"
  local n="${2:-3}"
  for _ in $(seq 1 "$n"); do
    pub_mode "$mode"
    sleep 0.12
  done
}

pub_wet_burst() {
  local wet="$1"
  local n="${2:-3}"
  for _ in $(seq 1 "$n"); do
    pub_wet "$wet"
    sleep 0.12
  done
}

get_data_field() {
  local topic="$1"
  timeout "${TEST_TOPIC_TIMEOUT_S}s" ros2 topic echo --once "$topic" --field data 2>/dev/null
}

sleep_transition_elapsed() {
  python3 - "$TRANSITION_SECONDS" <<'PY'
import sys
print(f"{float(sys.argv[1]) + 0.4:.2f}")
PY
}

assert_list_close() {
  local label="$1"
  local actual_text="$2"
  local expected_csv="$3"
  python3 - "$label" "$actual_text" "$expected_csv" "$TEST_TOL" <<'PY'
import ast
import math
import re
import sys

label, actual_text, expected_csv, tol = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])
raw = actual_text.strip()
lines = [
    ln.strip()
    for ln in raw.splitlines()
    if ln.strip() and ln.strip() not in ("---", "...")
]

actual = None

# Case A: YAML list style from ros2 topic echo:
# - 0.0
# - 0.0
if any(ln.startswith("-") for ln in lines):
    vals = []
    for ln in lines:
        if ln.startswith("-"):
            vals.append(float(ln[1:].strip()))
    actual = vals

# Case B: Python-style list string:
# [0.0, 0.0]
if actual is None:
    joined = "\n".join(lines)
    match = re.search(r"\[[^\]]*\]", joined, flags=re.S)
    if match:
        actual = ast.literal_eval(match.group(0))

# Case C: Fallback parse after removing separators.
if actual is None:
    actual = ast.literal_eval("\n".join(lines))

expected = [float(x) for x in expected_csv.split(",")]

if len(actual) != len(expected):
    print(f"[FAIL] {label}: length mismatch, actual={actual}, expected={expected}")
    sys.exit(1)

for i, (a, e) in enumerate(zip(actual, expected)):
    if math.fabs(float(a) - float(e)) > tol:
        print(f"[FAIL] {label}: idx={i}, actual={actual}, expected={expected}, tol={tol}")
        sys.exit(1)

print(f"[PASS] {label}: actual={actual}, expected={expected}")
PY
}

wait_list_close() {
  local label="$1"
  local topic="$2"
  local expected_csv="$3"
  local deadline=$((SECONDS + ASSERT_WAIT_S))
  local last=""
  while (( SECONDS < deadline )); do
    if last="$(get_data_field "$topic")"; then
      if assert_list_close "$label" "$last" "$expected_csv" >/dev/null 2>&1; then
        assert_list_close "$label" "$last" "$expected_csv"
        return 0
      fi
    fi
    sleep 0.15
  done
  echo "[FAIL] ${label}: did not converge within ${ASSERT_WAIT_S}s"
  if [[ -n "$last" ]]; then
    echo "[INFO] Last observed value:"
    echo "$last"
  fi
  return 1
}

echo "[INFO] Case 1: DISARMED + dry -> neutral outputs"
pub_wet_burst false
pub_mode_burst 0
wait_list_close "wing(disarmed)" "${WING_CMD_TOPIC}" "0.0,0.0"
wait_list_close "pos(disarmed)" "${TEST_POS_CMD_TOPIC}" "0.0,0.0"

echo "[INFO] Case 2: AIR + dry -> neutral wings"
pub_wet_burst false
pub_mode_burst 1
wait_list_close "wing(air)" "${WING_CMD_TOPIC}" "0.0,0.0"
wait_list_close "pos(air)" "${TEST_POS_CMD_TOPIC}" "0.0,0.0"

echo "[INFO] Case 3: AIR + wet -> TRANSITION command"
pub_mode_burst 1
pub_wet_burst true
wait_list_close "wing(transition)" "${WING_CMD_TOPIC}" "-0.8,0.8"
wait_list_close "pos(transition)" "${TEST_POS_CMD_TOPIC}" "-0.8,0.8"

echo "[INFO] Case 4: transition elapsed + wet -> UNDERWATER command"
sleep "$(sleep_transition_elapsed)"
wait_list_close "wing(underwater)" "${WING_CMD_TOPIC}" "-1.2,1.2"
wait_list_close "pos(underwater)" "${TEST_POS_CMD_TOPIC}" "-1.2,1.2"

echo "[INFO] Case 5: allocator timeout after input stops -> neutral"
kill "${STATE_PID}" 2>/dev/null || true
wait "${STATE_PID}" 2>/dev/null || true
STATE_PID=""
sleep 1.1
wait_list_close "pos(timeout-neutral)" "${TEST_POS_CMD_TOPIC}" "0.0,0.0"

echo "[OK] Decision-control acceptance test passed."
