# Launch tri_bot in Gazebo Harmonic with ArduPilotPlugin (for SITL).
#
# After this launch is running, start SITL in a separate terminal:
#   cd ~/ardupilot
#   Tools/autotest/sim_vehicle.py -v ArduPlane -f gazebo-zephyr --model JSON --console --map
#
# The ArduPilotPlugin communicates with SITL over UDP (127.0.0.1:9002).

import os
import subprocess
import tempfile

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import (
    DeclareLaunchArgument,
    ExecuteProcess,
    IncludeLaunchDescription,
    OpaqueFunction,
    SetEnvironmentVariable,
    TimerAction,
)
from launch.conditions import IfCondition
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node
from launch_ros.parameter_descriptions import ParameterValue


def _launch_setup(context, *args, **kwargs):
    pkg_share = get_package_share_directory('tri_bot_description')
    pkg_parent = os.path.dirname(pkg_share)
    model_path = os.path.join(pkg_share, 'urdf', 'tri_bot.xacro')
    world_path = os.path.join(pkg_share, 'worlds', 'tri_bot_runway.sdf')
    urdf_path = os.path.join(tempfile.gettempdir(), 'tri_bot_ardupilot.urdf')

    subprocess.run(
        ['xacro', model_path, 'use_ardupilot:=true', '-o', urdf_path],
        check=True,
    )
    with open(urdf_path, 'r') as f:
        robot_description = f.read()

    use_sim_time = LaunchConfiguration('use_sim_time', default='true')
    start_gazebo = LaunchConfiguration('start_gazebo', default='true')
    use_software_gl_val = LaunchConfiguration('use_software_gl', default='false').perform(context)

    # Set env vars via os.environ so they are inherited by ALL child processes
    # (SetEnvironmentVariable launch actions can miss included launch files).
    def _prepend_env(var, *dirs):
        parts = [d for d in dirs if d and os.path.isdir(d)]
        existing = os.environ.get(var, '')
        if existing:
            parts.append(existing)
        os.environ[var] = os.pathsep.join(parts)

    _prepend_env('GZ_SIM_RESOURCE_PATH', pkg_parent)
    _prepend_env('IGN_GAZEBO_RESOURCE_PATH', pkg_parent)
    _prepend_env(
        'GZ_SIM_SYSTEM_PLUGIN_PATH',
        os.path.expanduser('~/ardupilot_gazebo/build'),
        os.path.expanduser('~/ardu_ws/install/ardupilot_gazebo/lib'),
        os.path.expanduser('~/ardu_ws/install/ardupilot_gazebo/lib/ardupilot_gazebo'),
        os.path.expanduser('~/gz_ws/src/ardupilot_gazebo/build'),
        '/opt/ros/humble/lib',
    )

    actions = []

    if use_software_gl_val.lower() in ('true', '1', 'yes'):
        actions.insert(0, SetEnvironmentVariable(name='LIBGL_ALWAYS_SOFTWARE', value='1'))

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

    try:
        pkg_ros_gz_sim = get_package_share_directory('ros_gz_sim')
        gz_sim_launch = os.path.join(pkg_ros_gz_sim, 'launch', 'gz_sim.launch.py')
        start_gz_sim = IncludeLaunchDescription(
            PythonLaunchDescriptionSource(gz_sim_launch),
            launch_arguments={
                'gz_args': f'-r {world_path}',
                'gz_version': '8',
            }.items(),
        )
        if IfCondition(start_gazebo).evaluate(context):
            actions.append(start_gz_sim)
    except Exception:
        pass

    # ros-humble-ros-gz-sim speaks Fortress transport — can't spawn into Harmonic.
    # Use the native gz CLI service call instead.
    spawn_entity_cmd = ExecuteProcess(
        cmd=[
            'gz', 'service',
            '-s', '/world/tri_bot_runway/create',
            '--reqtype', 'gz.msgs.EntityFactory',
            '--reptype', 'gz.msgs.Boolean',
            '--timeout', '10000',
            '--req', (
                f'sdf_filename: "{urdf_path}", '
                'name: "tri_bot", '
                'pose: {position: {z: 0.5}}'
            ),
        ],
        output='screen',
    )

    actions.extend([
        robot_state_publisher_node,
        TimerAction(period=5.0, actions=[spawn_entity_cmd]),
    ])

    return actions


def generate_launch_description():
    return LaunchDescription([
        DeclareLaunchArgument('use_sim_time', default_value='true', description='Use sim time'),
        DeclareLaunchArgument(
            'start_gazebo',
            default_value='true',
            description='Start Gazebo with tri_bot_runway world',
        ),
        DeclareLaunchArgument(
            'use_software_gl',
            default_value='false',
            description='Set LIBGL_ALWAYS_SOFTWARE=1 for Mesa software rendering.',
        ),
        OpaqueFunction(function=_launch_setup),
    ])
