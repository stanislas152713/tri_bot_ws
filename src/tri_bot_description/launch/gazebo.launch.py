# Launch tri_bot in Gazebo Harmonic.
# Uses gz_ros2_control with ros_gz_sim.
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
    pkg_share = get_package_share_directory('tri_bot_description')
    pkg_parent = os.path.dirname(pkg_share)
    model_path = os.path.join(pkg_share, 'urdf', 'tri_bot.xacro')
    controllers_path = os.path.join(pkg_share, 'config', 'controllers.yaml')
    urdf_path = os.path.join(tempfile.gettempdir(), 'tri_bot_gazebo.urdf')
    show_debug_frames_val = LaunchConfiguration('show_debug_frames', default='false').perform(context)
    # Generate URDF for Gazebo Harmonic (gz_ros2_control)
    subprocess.run(
        [
            'xacro', model_path,
            'controllers_file:=' + controllers_path,
            'show_debug_frames:=' + show_debug_frames_val,
            '-o', urdf_path,
        ],
        check=True,
    )
    with open(urdf_path, 'r') as f:
        robot_description = f.read()

    use_sim_time = LaunchConfiguration('use_sim_time', default='true')
    start_gazebo = LaunchConfiguration('start_gazebo', default='true')
    controller_manager_timeout = LaunchConfiguration('controller_manager_timeout', default='90')
    spawn_jsb_delay = float(LaunchConfiguration('spawn_jsb_delay', default='10.0').perform(context))
    spawn_position_delay = float(LaunchConfiguration('spawn_position_delay', default='12.0').perform(context))
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
            '--controller-manager-timeout', controller_manager_timeout,
        ],
        output='screen',
    )
    spawn_position_controller = ExecuteProcess(
        cmd=[
            'ros2', 'run', 'controller_manager', 'spawner',
            'position_controller',
            '--controller-manager-timeout', controller_manager_timeout,
        ],
        output='screen',
    )

    resource_path = os.pathsep.join(
        [p for p in [pkg_parent, os.environ.get('GZ_SIM_RESOURCE_PATH', '')] if p]
    )
    ign_resource_path = os.pathsep.join(
        [p for p in [pkg_parent, os.environ.get('IGN_GAZEBO_RESOURCE_PATH', '')] if p]
    )

    actions = [
        SetEnvironmentVariable(name='GZ_SIM_RESOURCE_PATH', value=resource_path),
        SetEnvironmentVariable(name='IGN_GAZEBO_RESOURCE_PATH', value=ign_resource_path),
    ]

    try:
        pkg_ros_gz_sim = get_package_share_directory('ros_gz_sim')
        gz_sim_launch = os.path.join(pkg_ros_gz_sim, 'launch', 'gz_sim.launch.py')
        start_gz_sim = IncludeLaunchDescription(
            PythonLaunchDescriptionSource(gz_sim_launch),
            launch_arguments={'gz_args': '-r empty.sdf'}.items(),
        )
        if IfCondition(start_gazebo).evaluate(context):
            actions.append(start_gz_sim)
    except Exception:
        pass

    actions.extend([
        robot_state_publisher_node,
        TimerAction(period=3.0, actions=[spawn_entity_cmd]),
        TimerAction(period=spawn_jsb_delay, actions=[spawn_joint_state_broadcaster]),
        TimerAction(period=spawn_position_delay, actions=[spawn_position_controller]),
    ])
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
            'use_software_gl',
            default_value='false',
            description='Set LIBGL_ALWAYS_SOFTWARE=1 for Mesa software rendering (3D GUI, slower).',
        ),
        DeclareLaunchArgument(
            'controller_manager_timeout',
            default_value='90',
            description='Spawner timeout waiting for controller_manager services (seconds).',
        ),
        DeclareLaunchArgument(
            'spawn_jsb_delay',
            default_value='10.0',
            description='Delay before spawning joint_state_broadcaster (seconds).',
        ),
        DeclareLaunchArgument(
            'spawn_position_delay',
            default_value='12.0',
            description='Delay before spawning position_controller (seconds).',
        ),
        DeclareLaunchArgument(
            'show_debug_frames',
            default_value='false',
            description='Render debug spheres at key link/joint origins.',
        ),
        OpaqueFunction(function=_launch_setup),
    ])
