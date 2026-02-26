import os
from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import Command, LaunchConfiguration
from launch_ros.actions import Node
from launch_ros.parameter_descriptions import ParameterValue

def generate_launch_description():
    # 1. Get the package share directory
    pkg_share = get_package_share_directory('tri_bot_description')
    
    # 2. Find the Xacro model file
    default_model_path = os.path.join(pkg_share, 'urdf', 'tri_bot.xacro')
    
    # 3. Process the Xacro file into raw URDF XML
    # Command(['xacro ', model]) runs the xacro tool at runtime
    robot_description = Command(['xacro ', LaunchConfiguration('model')])

    # 4. Define Nodes
    
    # Node A: Robot State Publisher
    # Function: Publishes static TF transforms (e.g., where the wings are relative to the body)
    robot_state_publisher_node = Node(
        package='robot_state_publisher',
        executable='robot_state_publisher',
        parameters=[{'robot_description': ParameterValue(robot_description, value_type=str)}]
    )

    # Node B: Joint State Publisher GUI
    # Function: Opens a small window with sliders to manually control joints (fold wings, move tail)
    joint_state_publisher_gui_node = Node(
        package='joint_state_publisher_gui',
        executable='joint_state_publisher_gui',
        name='joint_state_publisher_gui'
    )

    # Node C: RViz2
    # Function: The 3D visualization tool
    rviz_node = Node(
        package='rviz2',
        executable='rviz2',
        name='rviz2',
        output='screen'
    )

    # 5. Return the Launch Description
    return LaunchDescription([
        # Declare an argument 'model' so we can change the file path from command line if needed
        DeclareLaunchArgument(
            'model', 
            default_value=default_model_path, 
            description='Absolute path to robot urdf file'),
            
        robot_state_publisher_node,
        joint_state_publisher_gui_node,
        rviz_node
    ])