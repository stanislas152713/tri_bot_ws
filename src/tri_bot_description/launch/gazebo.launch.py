# Launch tri_bot in Gazebo (Harmonic or Fortress).
# Harmonic: gz_ros2_control, ros_gz_sim. Fortress: ign_ros2_control (use_fortress:=true).
# OpenGL 3.3 not supported: use_software_gl:=true for 3D GUI (Mesa software rendering, slower).

import os
import subprocess
import tempfile

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, ExecuteProcess, IncludeLaunchDescription, OpaqueFunction, SetEnvironmentVariable, TimerAction
from launch.conditions import IfCondition
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node
from launch_ros.parameter_descriptions import ParameterValue


def _launch_setup(context, *args, **kwargs):
    use_fortress_val = LaunchConfiguration('use_fortress', default='true').perform(context)
    gazebo_fortress_xacro = '1' if use_fortress_val.lower() in ('true', '1', 'yes') else '0'
    pkg_share = get_package_share_directory('tri_bot_description')
    model_path = os.path.join(pkg_share, 'urdf', 'tri_bot.xacro')
    controllers_path = os.path.join(pkg_share, 'config', 'controllers.yaml')
    urdf_path = os.path.join(tempfile.gettempdir(), 'tri_bot_gazebo.urdf')
    subprocess.run(
        [
            'xacro', model_path,
            'controllers_file:=' + controllers_path,
            'gazebo_fortress:=' + gazebo_fortress_xacro,
            '-o', urdf_path,
        ],
        check=True,
    )
    with open(urdf_path, 'r') as f:
        robot_description = f.read()

    use_sim_time = LaunchConfiguration('use_sim_time', default='true')
    start_gazebo = LaunchConfiguration('start_gazebo', default='true')
    use_software_gl_val = LaunchConfiguration('use_software_gl', default='false').perform(context)

    robot_state_publisher_node = Node(
        package='robot_state_publisher',
        executable='robot_state_publisher',
        name='robot_state_publisher',
        output='screen',
        parameters=[
            {'robot_description': ParameterValue(robot_description, value_type=str)},
            {'use_sim_time': use_sim_time},
        ],
    )
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
        robot_state_publisher_node,
        TimerAction(period=3.0, actions=[spawn_entity_cmd]),
        TimerAction(period=6.0, actions=[spawn_joint_state_broadcaster]),
        TimerAction(period=7.0, actions=[spawn_position_controller]),
    ]

    try:
        pkg_ros_gz_sim = get_package_share_directory('ros_gz_sim')
        gz_sim_launch = os.path.join(pkg_ros_gz_sim, 'launch', 'gz_sim.launch.py')
        start_gz_sim = IncludeLaunchDescription(
            PythonLaunchDescriptionSource(gz_sim_launch),
            launch_arguments={'gz_args': 'empty.sdf'}.items(),
        )
        if IfCondition(start_gazebo).evaluate(context):
            actions.insert(0, start_gz_sim)
    except Exception:
        pass
    # LIBGL_ALWAYS_SOFTWARE=1: Mesa software rendering, 3D GUI without OpenGL 3.3 (slower)
    if use_software_gl_val.lower() in ('true', '1', 'yes'):
        actions.insert(0, SetEnvironmentVariable(name='LIBGL_ALWAYS_SOFTWARE', value='1'))

    return actions


def generate_launch_description():
    return LaunchDescription([
        DeclareLaunchArgument('use_sim_time', default_value='true', description='Use sim time'),
        DeclareLaunchArgument(
            'start_gazebo',
            default_value='true',
            description='Start Gazebo with empty.sdf',
        ),
        DeclareLaunchArgument(
            'use_fortress',
            default_value='true',
            description='Use Gazebo Fortress (ign_ros2_control). Set false for Harmonic (gz_ros2_control).',
        ),
        DeclareLaunchArgument(
            'use_software_gl',
            default_value='false',
            description='Set LIBGL_ALWAYS_SOFTWARE=1 for Mesa software rendering (3D GUI, slower).',
        ),
        OpaqueFunction(function=_launch_setup),
    ])
