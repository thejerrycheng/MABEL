import os
import time
from dynamixel_sdk import * # --- System Configuration ---
DEVICENAME          = '/dev/cu.usbserial-FTB8HR1Y'  
BAUDRATE            = 3000000         
PROTOCOL_VERSION    = 2.0             

# --- Control Table Constants ---
ADDR_TORQUE_ENABLE    = 64
ADDR_GOAL_PWM         = 100  
ADDR_GOAL_POSITION    = 116
ADDR_PRESENT_POSITION = 132  
ADDR_PRESENT_CURRENT  = 126  # Used to read torque feedback

LEN_GOAL_PWM          = 2
LEN_GOAL_POSITION     = 4               
LEN_PRESENT_POSITION  = 4
LEN_PRESENT_CURRENT   = 2

TORQUE_ENABLE         = 1
TORQUE_DISABLE        = 0

# --- Calibration Settings ---
# LOW power for safe bumping against hard stops
CALIBRATION_PWM       = 200   
# Step size in ticks to move during the sweep
SWEEP_STEP            = 10    
# If the motor draws more than this many mA, it has hit the limit
STALL_THRESHOLD_MA    = 180   

def get_signed_current(raw_value):
    """Convert the 2-byte unsigned data from Dynamixel to a signed integer (mA)"""
    if raw_value > 32767:
        raw_value -= 65536
    return raw_value

def map_actuator_to_joint(raw_tick, min_tick, max_tick):
    """
    Linear Mapping: Converts raw Dynamixel ticks to a normalized 0.0 - 1.0 joint space.
    0.0 = Fully Open (min_tick)
    1.0 = Fully Closed (max_tick)
    """
    # Clamp to limits to prevent > 1.0 or < 0.0 if the tendon stretches
    clamped_tick = max(min_tick, min(max_tick, raw_tick))
    normalized_pos = (clamped_tick - min_tick) / (max_tick - min_tick)
    return normalized_pos

def calibrate_joint(portHandler, packetHandler, dxl_id, direction):
    """Sweeps the joint in one direction until it stalls, returns the limit position."""
    
    # Read starting position
    present_pos, _, _ = packetHandler.read4ByteTxRx(portHandler, dxl_id, ADDR_PRESENT_POSITION)
    target_pos = present_pos
    
    print(f"      Sweeping {'FORWARD' if direction == 1 else 'REVERSE'}...")
    
    while True:
        target_pos += (SWEEP_STEP * direction)
        
        # Write new position
        packetHandler.write4ByteTxRx(portHandler, dxl_id, ADDR_GOAL_POSITION, target_pos)
        time.sleep(0.02) # Give motor time to move
        
        # Read Torque (Current) Feedback
        raw_current, _, _ = packetHandler.read2ByteTxRx(portHandler, dxl_id, ADDR_PRESENT_CURRENT)
        actual_current_ma = abs(get_signed_current(raw_current))
        
        # Read Actual Position
        actual_pos, _, _ = packetHandler.read4ByteTxRx(portHandler, dxl_id, ADDR_PRESENT_POSITION)
        
        print(f"\r        Pos: {actual_pos} | Current: {actual_current_ma} mA   ", end="")
        
        # Check if we hit the hard stop
        if actual_current_ma > STALL_THRESHOLD_MA:
            print(f"\n      -> Limit Reached at Pos: {actual_pos} (Spike: {actual_current_ma} mA)")
            # Back off slightly to relieve tension
            packetHandler.write4ByteTxRx(portHandler, dxl_id, ADDR_GOAL_POSITION, actual_pos - (50 * direction))
            time.sleep(0.5)
            return actual_pos

        # Failsafe: Don't exceed 0-4095 bounds
        if target_pos > 4095 or target_pos < 0:
            print("\n      -> Error: Hit encoder bounds before physical limit.")
            return actual_pos

def main():
    portHandler = PortHandler(DEVICENAME)
    packetHandler = PacketHandler(PROTOCOL_VERSION)

    if not portHandler.openPort() or not portHandler.setBaudRate(BAUDRATE):
        print("Failed to open port.")
        quit()

    print("Scanning for connected motors...")
    active_ids = []
    for dxl_id in range(1, 17):
        if packetHandler.ping(portHandler, dxl_id)[1] == COMM_SUCCESS:
            active_ids.append(dxl_id)
            
    if not active_ids:
        print("No motors found.")
        quit()
        
    print(f"Found IDs: {active_ids}\n")
    print("--- STARTING AUTO-CALIBRATION ---")
    print("WARNING: Keep hands clear. Motors will find their mechanical limits.")
    time.sleep(2)

    joint_limits = {}

    for dxl_id in active_ids:
        print(f"\n[ Calibrating Motor ID {dxl_id} ]")
        
        # Set low torque for safe bumping
        packetHandler.write2ByteTxRx(portHandler, dxl_id, ADDR_GOAL_PWM, CALIBRATION_PWM)
        packetHandler.write1ByteTxRx(portHandler, dxl_id, ADDR_TORQUE_ENABLE, TORQUE_ENABLE)
        time.sleep(0.5)

        # 1. Sweep Forward (Closing the finger)
        max_limit = calibrate_joint(portHandler, packetHandler, dxl_id, direction=1)
        
        # 2. Sweep Reverse (Opening the finger)
        min_limit = calibrate_joint(portHandler, packetHandler, dxl_id, direction=-1)
        
        # Store limits
        # Sort them just in case forward/reverse logic is physically flipped on the hand
        actual_min = min(min_limit, max_limit)
        actual_max = max(min_limit, max_limit)
        joint_limits[dxl_id] = {"min": actual_min, "max": actual_max}

        # 3. Return to safe center position
        center_pos = int((actual_max + actual_min) / 2)
        print(f"      Returning ID {dxl_id} to center ({center_pos})...")
        packetHandler.write4ByteTxRx(portHandler, dxl_id, ADDR_GOAL_POSITION, center_pos)
        
        # Disable torque to let motor cool before next one
        time.sleep(1.0)
        packetHandler.write1ByteTxRx(portHandler, dxl_id, ADDR_TORQUE_ENABLE, TORQUE_DISABLE)

    print("\n\n=== CALIBRATION COMPLETE ===")
    print("Store this dictionary in your main script:")
    print("ORCA_LIMITS = {")
    for dxl_id, limits in joint_limits.items():
        print(f"    {dxl_id}: {{'min': {limits['min']}, 'max': {limits['max']}}},")
    print("}")

    # Example of the Linear Mapping
    print("\n--- Linear Mapping Example ---")
    example_id = active_ids[0]
    test_tick = int((joint_limits[example_id]['min'] + joint_limits[example_id]['max']) / 2)
    norm = map_actuator_to_joint(test_tick, joint_limits[example_id]['min'], joint_limits[example_id]['max'])
    print(f"ID {example_id} at center tick {test_tick} maps to normalized joint state: {norm:.2f}")

    portHandler.closePort()

if __name__ == '__main__':
    main()