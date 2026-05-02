import os
import sys
import time
import select
import tty
import termios
from dynamixel_sdk import * # Uses Dynamixel SDK library

# --- System Configuration ---
DEVICENAME          = '/dev/cu.usbserial-FTB8HR1Y'  
BAUDRATE            = 3000000         
PROTOCOL_VERSION    = 2.0             

# --- XL330-M288-T Control Table Constants ---
ADDR_TORQUE_ENABLE  = 64
ADDR_GOAL_POSITION  = 116
LEN_GOAL_POSITION   = 4               
TORQUE_ENABLE       = 1
TORQUE_DISABLE      = 0

# --- Teleop Settings ---
POS_STEP            = 50   # How much the motor moves per arrow key press
MIN_POS             = 0    # XL330 minimum position
MAX_POS             = 4095 # XL330 maximum position

def get_key():
    """Reads a keypress from the terminal without blocking the control loop."""
    if select.select([sys.stdin], [], [], 0) == ([sys.stdin], [], []):
        c = sys.stdin.read(1)
        # Handle Arrow Keys (which send a 3-character escape sequence)
        if c == '\x1b':
            c2 = sys.stdin.read(1)
            c3 = sys.stdin.read(1)
            if c2 == '[':
                if c3 == 'A': return 'UP'
                elif c3 == 'B': return 'DOWN'
                elif c3 == 'C': return 'RIGHT'
                elif c3 == 'D': return 'LEFT'
        return c
    return None

def main():
    portHandler = PortHandler(DEVICENAME)
    packetHandler = PacketHandler(PROTOCOL_VERSION)
    groupSyncWrite = GroupSyncWrite(portHandler, packetHandler, ADDR_GOAL_POSITION, LEN_GOAL_POSITION)

    if not portHandler.openPort() or not portHandler.setBaudRate(BAUDRATE):
        print("Failed to open the port or set baudrate. Check connection.")
        quit()
    print("Port opened successfully.")

    # 1. Dynamic Motor Discovery (ID Proofing)
    print("Scanning for connected motors (IDs 1-16)...")
    active_ids = []
    for dxl_id in range(1, 17):
        # Ping the motor
        dxl_model_number, dxl_comm_result, dxl_error = packetHandler.ping(portHandler, dxl_id)
        if dxl_comm_result == COMM_SUCCESS:
            active_ids.append(dxl_id)
            print(f" -> Found Motor ID: {dxl_id}")
            
    if not active_ids:
        print("No motors detected on the bus. Exiting.")
        portHandler.closePort()
        quit()

    print(f"\nActive Motor Array: {active_ids}")

    # 2. Enable Torque for Detected Motors
    print("Enabling Torque...")
    for dxl_id in active_ids:
        packetHandler.write1ByteTxRx(portHandler, dxl_id, ADDR_TORQUE_ENABLE, TORQUE_ENABLE)

    # Teleop Variables
    global_target = 2048 # Start at center
    print("\n--- Keyboard Teleop Active ---")
    print("Use UP/RIGHT arrows to increase position")
    print("Use DOWN/LEFT arrows to decrease position")
    print("Press 'q' or Ctrl+C to quit\n")

    # Save terminal settings to safely read keystrokes
    old_term_settings = termios.tcgetattr(sys.stdin)
    
    try:
        # Set terminal to cbreak mode (reads keys instantly without waiting for Enter)
        tty.setcbreak(sys.stdin.fileno())
        
        while True:
            # Check for keyboard input
            key = get_key()
            if key in ['UP', 'RIGHT']:
                global_target = min(global_target + POS_STEP, MAX_POS)
                print(f"\rTarget Position: {global_target}    ", end="")
            elif key in ['DOWN', 'LEFT']:
                global_target = max(global_target - POS_STEP, MIN_POS)
                print(f"\rTarget Position: {global_target}    ", end="")
            elif key == 'q' or key == '\x03': # q or Ctrl+C
                break

            # SyncWrite to all *detected* motors
            groupSyncWrite.clearParam()
            for dxl_id in active_ids:
                param_goal_position = [DXL_LOBYTE(DXL_LOWORD(global_target)), 
                                       DXL_HIBYTE(DXL_LOWORD(global_target)), 
                                       DXL_LOBYTE(DXL_HIWORD(global_target)), 
                                       DXL_HIBYTE(DXL_HIWORD(global_target))]
                groupSyncWrite.addParam(dxl_id, param_goal_position)

            # Fire packet
            groupSyncWrite.txPacket()

            # Small delay to prevent maxing out the CPU and serial bus
            time.sleep(0.01)

    except Exception as e:
        print(f"\nError: {e}")

    finally:
        # Restore terminal to normal operation
        termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_term_settings)
        
        print("\nDisabling Torque...")
        for dxl_id in active_ids:
            packetHandler.write1ByteTxRx(portHandler, dxl_id, ADDR_TORQUE_ENABLE, TORQUE_DISABLE)
        portHandler.closePort()
        print("Port closed.")

if __name__ == '__main__':
    main()