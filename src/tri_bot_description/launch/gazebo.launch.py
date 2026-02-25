# Launch tri_bot in Gazebo Harmonic with gz_ros2_control.
# Stack: ROS 2 Humble, Gazebo Harmonic, gz_ros2_control, ros_gz_sim.
# Requires: gz-harmonic, ros-humble-ros-gz-harmonic, ros-humble-gz-ros2-control (build from source with GZ_VERSION=harmonic for Humble+Harmonic).
#   ros2 launch tri_bot_description gazebo.launch.py

import os
import subprocess
import tempfile

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, ExecuteProcess, IncludeLaunchDescription, TimerAction
from launch.conditions import IfCondition
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description():
    pkg_share = get_package_share_directory('tri_bot_description')
    model_path = os.path.join(pkg_share, 'urdf', 'tri_bot.xacro')
    controllers_path = os.path.join(pkg_share, 'config', 'controllers.yaml')

    # Generate URDF with controllers_file for gz_ros2_control
    urdf_path = os.path.join(tempfile.gettempdir(), 'tri_bot_gazebo.urdf')
    subprocess.run(
        ['xacro', model_path, 'controllers_file:=' + controllers_path, '-o', urdf_path],
        check=True,
    )
    with open(urdf_path, 'r') as f:
        robot_description = f.read()

    use_sim_time = LaunchConfiguration('use_sim_time', default='true')
    start_gazebo = LaunchConfiguration('start_gazebo', default='true')

    # Gazebo Harmonic: gz sim with empty world (ros_gz_sim)
    try:
        pkg_ros_gz_sim = get_package_share_directory('ros_gz_sim')
        gz_sim_launch = os.path.join(pkg_ros_gz_sim, 'launch', 'gz_sim.launch.py')
        start_gz_sim = IncludeLaunchDescription(
            PythonLaunchDescriptionSource(gz_sim_launch),
            launch_arguments={'gz_args': 'empty.sdf'}.items(),
            condition=IfCondition(start_gazebo),
        )
    except Exception:
        start_gz_sim = None  # User starts gz sim manually if ros_gz_sim not found

    robot_state_publisher_node = Node(
        package='robot_state_publisher',
        executable='robot_state_publisher',
        name='robot_state_publisher',
        output='screen',
        parameters=[
            {'robot_description': robot_description},
            {'use_sim_time': use_sim_time},
        ],
    )

    # Spawn model into gz sim (ros_gz_sim create)
    spawn_entity_cmd = ExecuteProcess(
        cmd=['ros2', 'run', 'ros_gz_sim', 'create', '-file', urdf_path, '-name', 'tri_bot', '-z', '0.5'],
        output='screen',
    )

    spawn_joint_state_broadcaster = ExecuteProcess(
        cmd=[
            'ros2', 'run', 'controller_manager', 'spawner',
            'joint_state_broadcaster',
            '--controller-manager-timeout', '30',
        ],
        output='screen',
    )
    spawn_position_controller = ExecuteProcess(
        cmd=[
            'ros2', 'run', 'controller_manager', 'spawner',
            'position_controller',
            '--controller-manager-timeout', '30',
        ],
        output='screen',
    )

    actions = [
        DeclareLaunchArgument('use_sim_time', default_value='true', description='Use sim time'),
        DeclareLaunchArgument(
            'start_gazebo',
            default_value='true',
            description='If true, start gz sim with empty.sdf (Gazebo Harmonic)',
        ),
        robot_state_publisher_node,
        TimerAction(period=3.0, actions=[spawn_entity_cmd]),
        TimerAction(period=6.0, actions=[spawn_joint_state_broadcaster]),
        TimerAction(period=7.0, actions=[spawn_position_controller]),
    ]
    if start_gz_sim is not None:
        actions.insert(2, start_gz_sim)

    return LaunchDescription(actions)
