#include <algorithm>
#include <array>
#include <chrono>
#include <memory>

#include "rclcpp/rclcpp.hpp"
#include "std_msgs/msg/float32_multi_array.hpp"
#include "std_msgs/msg/float64_multi_array.hpp"

using namespace std::chrono_literals;

class TvcAllocatorNode : public rclcpp::Node
{
public:
  TvcAllocatorNode()
  : Node("tvc_allocator"),
    timeout_seconds_(declare_parameter<double>("command_timeout_s", 0.5)),
    publish_rate_hz_(declare_parameter<double>("publish_rate_hz", 50.0))
  {
    // V1 contract: input is wing-only command [left_wing, right_wing].
    wing_cmd_sub_ = create_subscription<std_msgs::msg::Float32MultiArray>(
      "wing_fold_cmd", 10,
      std::bind(&TvcAllocatorNode::on_wing_command, this, std::placeholders::_1));

    // Output contract: [left_wing, right_wing, tvc_pitch, tvc_yaw].
    position_cmd_pub_ = create_publisher<std_msgs::msg::Float64MultiArray>(
      "/position_controller/commands", 10);

    publish_period_ = std::chrono::duration<double>(1.0 / std::max(1.0, publish_rate_hz_));
    publish_timer_ = create_wall_timer(
      std::chrono::duration_cast<std::chrono::nanoseconds>(publish_period_),
      std::bind(&TvcAllocatorNode::on_publish_timer, this));

    // Start in neutral state.
    current_cmd_ = {0.0, 0.0, 0.0, 0.0};
    last_cmd_time_ = now();

    RCLCPP_INFO(
      get_logger(),
      "tvc_allocator started: timeout=%.2fs, rate=%.1fHz (TVC locked at 0 for V1)",
      timeout_seconds_, publish_rate_hz_);
  }

private:
  static double clamp(double value, double low, double high)
  {
    return std::max(low, std::min(value, high));
  }

  void on_wing_command(const std_msgs::msg::Float32MultiArray::SharedPtr msg)
  {
    if (msg->data.size() < 2) {
      RCLCPP_WARN_THROTTLE(
        get_logger(), *get_clock(), 2000,
        "wing_fold_cmd requires at least 2 values: [left_wing, right_wing]");
      return;
    }

    // Joint limits from model:
    // left_wing_fold_joint:  [-1.57, 0.0]
    // right_wing_fold_joint: [0.0,  1.57]
    current_cmd_[0] = clamp(static_cast<double>(msg->data[0]), -1.57, 0.0);
    current_cmd_[1] = clamp(static_cast<double>(msg->data[1]), 0.0, 1.57);

    // V1 MVP: keep TVC locked at neutral.
    current_cmd_[2] = 0.0;
    current_cmd_[3] = 0.0;

    last_cmd_time_ = now();
  }

  void on_publish_timer()
  {
    const auto elapsed = (now() - last_cmd_time_).seconds();
    if (elapsed > timeout_seconds_) {
      // Safety fallback: no recent command => neutral.
      current_cmd_ = {0.0, 0.0, 0.0, 0.0};
    }

    std_msgs::msg::Float64MultiArray out;
    out.data = {current_cmd_[0], current_cmd_[1], current_cmd_[2], current_cmd_[3]};
    position_cmd_pub_->publish(out);
  }

  rclcpp::Subscription<std_msgs::msg::Float32MultiArray>::SharedPtr wing_cmd_sub_;
  rclcpp::Publisher<std_msgs::msg::Float64MultiArray>::SharedPtr position_cmd_pub_;
  rclcpp::TimerBase::SharedPtr publish_timer_;

  std::array<double, 4> current_cmd_{};
  rclcpp::Time last_cmd_time_;
  std::chrono::duration<double> publish_period_{};
  double timeout_seconds_{0.5};
  double publish_rate_hz_{50.0};
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  rclcpp::spin(std::make_shared<TvcAllocatorNode>());
  rclcpp::shutdown();
  return 0;
}
