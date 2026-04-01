"""Minimal rule-based mode state machine for tri_bot V1."""

from enum import IntEnum

import rclpy
from rclpy.node import Node
from std_msgs.msg import Bool, Float32MultiArray, UInt8
from tri_bot_interfaces.msg import VehicleState


class Mode(IntEnum):
    """Internal mode enum matching VehicleState constants."""

    DISARMED = int(VehicleState.MODE_DISARMED)
    AIR = int(VehicleState.MODE_AIR_FLIGHT)
    TRANSITION = int(VehicleState.MODE_TRANSITION)
    UNDERWATER = int(VehicleState.MODE_UNDERWATER)


class MinimalStateMachine(Node):
    """Rule-based state machine for DISARMED/AIR/TRANSITION/UNDERWATER."""

    def __init__(self) -> None:
        """Initialize subscriptions, publishers, parameters, and timer."""
        super().__init__("state_machine")
        # V1 note:
        # We intentionally use a single TRANSITION mode for both directions
        # (AIR -> UNDERWATER and UNDERWATER -> AIR).
        # TODO(V2): split into direction-aware modes, e.g.
        # TRANSITION_TO_WATER and TRANSITION_TO_AIR, with separate rules/timings.

        self.transition_seconds = self.declare_parameter(
            "transition_seconds", 2.0
        ).value
        self.publish_rate_hz = self.declare_parameter("publish_rate_hz", 10.0).value

        self.mode = Mode.DISARMED
        self.is_wet = False
        self.transition_start_s = 0.0

        self.vehicle_state_pub = self.create_publisher(VehicleState, "vehicle_state", 10)
        self.wing_cmd_pub = self.create_publisher(Float32MultiArray, "wing_fold_cmd", 10)

        self.set_mode_sub = self.create_subscription(
            UInt8, "set_mode", self._on_set_mode, 10
        )
        self.wet_sub = self.create_subscription(Bool, "is_wet", self._on_is_wet, 10)

        period = 1.0 / max(1.0, float(self.publish_rate_hz))
        self.timer = self.create_timer(period, self._on_timer)

        self.get_logger().info(
            f"state_machine started (transition={self.transition_seconds:.2f}s, "
            f"rate={self.publish_rate_hz:.1f}Hz)"
        )

    def _on_set_mode(self, msg: UInt8) -> None:
        """Handle manual mode command from /set_mode."""
        try:
            requested = Mode(msg.data)
        except ValueError:
            self.get_logger().warn(f"Ignored invalid mode command: {msg.data}")
            return

        self._set_mode(requested)

    def _on_is_wet(self, msg: Bool) -> None:
        """Update water-contact status from /is_wet."""
        self.is_wet = bool(msg.data)

    def _set_mode(self, new_mode: Mode) -> None:
        """Apply mode change and mark transition start time when needed."""
        if new_mode == self.mode:
            return

        old = self.mode
        self.mode = new_mode
        if self.mode == Mode.TRANSITION:
            self.transition_start_s = self.get_clock().now().nanoseconds / 1e9
        self.get_logger().info(f"Mode changed: {old.name} -> {self.mode.name}")

    def _transition_elapsed(self) -> bool:
        """Return True when transition dwell time is complete."""
        now_s = self.get_clock().now().nanoseconds / 1e9
        return (now_s - self.transition_start_s) >= float(self.transition_seconds)

    def _auto_transition_rules(self) -> None:
        """Execute automatic rule-based transitions."""
        if self.mode == Mode.AIR and self.is_wet:
            self._set_mode(Mode.TRANSITION)
            return

        if self.mode == Mode.UNDERWATER and not self.is_wet:
            self._set_mode(Mode.TRANSITION)
            return

        if self.mode == Mode.TRANSITION and self._transition_elapsed():
            if self.is_wet:
                self._set_mode(Mode.UNDERWATER)
            else:
                self._set_mode(Mode.AIR)

    def _wing_cmd_for_mode(self) -> list[float]:
        """Return V1 wing command [left, right] for current mode."""
        if self.mode == Mode.DISARMED:
            return [0.0, 0.0]
        if self.mode == Mode.AIR:
            return [0.0, 0.0]
        if self.mode == Mode.TRANSITION:
            return [-0.8, 0.8]
        return [-1.2, 1.2]

    def _publish_vehicle_state(self) -> None:
        """Publish current state as tri_bot_interfaces/VehicleState."""
        msg = VehicleState()
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.system_mode = int(self.mode)
        msg.is_wet = self.is_wet
        msg.battery_voltage = 0.0
        self.vehicle_state_pub.publish(msg)

    def _publish_wing_cmd(self) -> None:
        """Publish wing command for the current mode."""
        cmd = Float32MultiArray()
        cmd.data = self._wing_cmd_for_mode()
        self.wing_cmd_pub.publish(cmd)

    def _on_timer(self) -> None:
        """Run rules and publish current outputs."""
        self._auto_transition_rules()
        self._publish_vehicle_state()
        self._publish_wing_cmd()


def main(args=None) -> None:
    """Run the minimal state machine node."""
    rclpy.init(args=args)
    node = MinimalStateMachine()
    rclpy.spin(node)
    node.destroy_node()
    rclpy.shutdown()


if __name__ == "__main__":
    main()
