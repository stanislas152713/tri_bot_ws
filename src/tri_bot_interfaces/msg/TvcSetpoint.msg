# Thrust Vector Setpoint

std_msgs/Header header

# Target Vector (-1.0 to 1.0)
float32 pitch_demand   # Pitch intent
float32 yaw_demand     # Yaw intent
float32 throttle       # Throttle/Thrust

# Flags
bool fluid_lock        # If True, force lock vector (prevent wiggling in air)