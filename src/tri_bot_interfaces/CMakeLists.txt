cmake_minimum_required(VERSION 3.8)
project(tri_bot_interfaces)

if(CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

find_package(ament_cmake REQUIRED)
# 1. Find the Message Generator
find_package(rosidl_default_generators REQUIRED)
find_package(std_msgs REQUIRED)

# 2. Declare which messages to compile
rosidl_generate_interfaces(${PROJECT_NAME}
  "msg/VehicleState.msg"
  "msg/TvcSetpoint.msg"
  DEPENDENCIES std_msgs
)

ament_export_dependencies(rosidl_default_runtime)
ament_package()