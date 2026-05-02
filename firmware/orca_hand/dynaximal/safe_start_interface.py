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
ADDR_TORQUE_ENABLE    = 64
ADDR_GOAL_POSITION    = 116
ADDR_PRESENT_POSITION = 132  # Added to read absolute startup position
LEN_GOAL_POSITION     = 4               
LEN_PRESENT_POSITION  = 4
TORQUE_ENABLE         = 1
TORQUE_DISABLE        = 0

# --- Teleop Settings ---
POS_STEP            = 50   # How much the motor moves per arrow key press
MIN_POS             = 0    # XL330 minimum position
MAX_POS             = 4095 # XL330 maximum position

def get_key():
    """Reads a keypress from the terminal without blocking the control loop."""
    if select.select([sys.stdin], [], [], 0) == ([sys.stdin], [], []):
        c = sys.stdin.read(1)
        # Handle Arrow Keys (3-character escape sequence)
        if c == '\x1b':
            c2 = sys.stdin.read(1)
            c3 = sys.stdin.read(1)
            if c2 == '[':
                if c3 == 'A': return 'UP'
                elif c3 == 'B': return 'DOWN'
                elif c3 == 'C': return 'RIGHT'
                elif c3 == 'D': return 'LEFT'
        # Handle Enter key (Carriage Return or Line Feed)
        elif c == '\n' or c == '\r':
            return 'ENTER'
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
        dxl_model_number, dxl_comm_result, dxl_error = packetHandler.ping(portHandler, dxl_id)
        if dxl_comm_result == COMM_SUCCESS:
            active_ids.append(dxl_id)
            print(f" -> Found Motor ID: {dxl_id}")
            
    if not active_ids:
        print("No motors detected on the bus. Exiting.")
        portHandler.closePort()
        quit()

    print(f"\nActive Motor Array: {active_ids}")

    # 2. Hardware-Safe Startup: Read Present Positions
    print("Reading absolute positions to prevent startup overshoot...")
    targets = {} # Dictionary to store individual target positions for each motor
    
    for dxl_id in active_ids:
        dxl_present_position, dxl_comm_result, dxl_error = packetHandler.read4ByteTxRx(portHandler, dxl_id, ADDR_PRESENT_POSITION)
        if dxl_comm_result == COMM_SUCCESS:
            targets[dxl_id] = dxl_present_position
            print(f"    ID {dxl_id} starting at position: {dxl_present_position}")
        else:
            print(f"    Warning: Could not read ID {dxl_id}. Defaulting to 2048.")
            targets[dxl_id] = 2048

    # 3. Enable Torque
    print("Enabling Torque (Motors will hold their current poses)...")
    for dxl_id in active_ids:
        packetHandler.write1ByteTxRx(portHandler, dxl_id, ADDR_TORQUE_ENABLE, TORQUE_ENABLE)

    # Teleop Variables
    selected_mode = "ALL" # Can be "ALL" or an integer ID
    print("\n--- Keyboard Teleop Active ---")
    print("Mode: Controlling ALL motors synced")
    print("Use UP/RIGHT arrows to increase position")
    print("Use DOWN/LEFT arrows to decrease position")
    print("Press [ENTER] to switch to Single Motor mode")
    print("Press 'q' or Ctrl+C to quit\n")

    # Save standard terminal settings
    old_term_settings = termios.tcgetattr(sys.stdin)
    
    try:
        # Enter unbuffered key-reading mode
        tty.setcbreak(sys.stdin.fileno())
        
        while True:
            key = get_key()
            
            if key == 'ENTER':
                # Temporarily restore normal terminal so the user can type properly
                termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_term_settings)
                
                print("\n\n--- SELECTION MODE ---")
                user_input = input("Enter Motor ID to control (or press Enter again for ALL): ").strip()
                
                if user_input == "" or user_input.lower() == "all":
                    selected_mode = "ALL"
                    print("-> Mode set: Controlling ALL motors.\n")
                else:
                    try:
                        input_id = int(user_input)
                        if input_id in active_ids:
                            selected_mode = input_id
                            print(f"-> Mode set: Controlling ONLY Motor ID {selected_mode}.\n")
                        else:
                            print(f"-> Error: ID {input_id} is not connected. Staying in '{selected_mode}' mode.\n")
                    except ValueError:
                        print(f"-> Invalid input. Staying in '{selected_mode}' mode.\n")
                
                # Re-enter unbuffered key-reading mode
                tty.setcbreak(sys.stdin.fileno())

            elif key in ['UP', 'RIGHT', 'DOWN', 'LEFT']:
                direction = 1 if key in ['UP', 'RIGHT'] else -1
                delta = direction * POS_STEP

                # Update the target dictionary based on the current mode
                if selected_mode == "ALL":
                    for dxl_id in active_ids:
                        targets[dxl_id] = max(MIN_POS, min(MAX_POS, targets[dxl_id] + delta))
                    print(f"\r[ALL] Updating positions... (+/- {POS_STEP})        ", end="")
                else:
                    # Update only the selected motor
                    targets[selected_mode] = max(MIN_POS, min(MAX_POS, targets[selected_mode] + delta))
                    print(f"\r[ID {selected_mode}] Target Position: {targets[selected_mode]}        ", end="")
                    
            elif key == 'q' or key == '\x03':
                break

            # Send SyncWrite packet to all active motors continuously
            # Even if only one motor is moving, the others receive commands to actively hold their positions
            groupSyncWrite.clearParam()
            for dxl_id in active_ids:
                target = targets[dxl_id]
                param_goal_position = [DXL_LOBYTE(DXL_LOWORD(target)), 
                                       DXL_HIBYTE(DXL_LOWORD(target)), 
                                       DXL_LOBYTE(DXL_HIWORD(target)), 
                                       DXL_HIBYTE(DXL_HIWORD(target))]
                groupSyncWrite.addParam(dxl_id, param_goal_position)

            groupSyncWrite.txPacket()
            time.sleep(0.01)

    except Exception as e:
        print(f"\nError: {e}")

    finally:
        # Clean shutdown
        termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_term_settings)
        print("\nDisabling Torque...")
        for dxl_id in active_ids:
            packetHandler.write1ByteTxRx(portHandler, dxl_id, ADDR_TORQUE_ENABLE, TORQUE_DISABLE)
        portHandler.closePort()
        print("Port closed.")

if __name__ == '__main__':
    main()