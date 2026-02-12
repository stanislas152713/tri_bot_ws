# File Path: tri_bot_interfaces/msg/VehicleState.msg

# --- Constants (Enums) ---
uint8 MODE_DISARMED = 0     # Locked/Idle
uint8 MODE_AIR_FLIGHT = 1   # Air flight (Surfaces + Main Prop)
uint8 MODE_TRANSITION = 2   # Transforming (Wings folding, servos centering)
uint8 MODE_UNDERWATER = 3   # Underwater Cruise (TVC Active)

# --- Message Content ---
std_msgs/Header header      # Timestamp
uint8 system_mode           # Current mode (matches constants above)
bool is_wet                 # Water contact sensor status (True = In Water)
float32 battery_voltage     # Voltage monitoring