import os
import sys
import time
import select
import tty
import termios
import serial
from dynamixel_sdk import * # --- System Configuration ---
DEVICENAME          = '/dev/cu.usbserial-FTB8HR1Y'  
BAUDRATE            = 3000000         
PROTOCOL_VERSION    = 2.0             

# --- XL330-M288-T Control Table Constants ---
ADDR_TORQUE_ENABLE    = 64
ADDR_GOAL_PWM         = 100  
ADDR_GOAL_POSITION    = 116
ADDR_PRESENT_POSITION = 132  

LEN_GOAL_PWM          = 2
LEN_GOAL_POSITION     = 4               
LEN_PRESENT_POSITION  = 4

TORQUE_ENABLE         = 1
TORQUE_DISABLE        = 0

# --- Teleop & Grasping Settings ---
POS_STEP            = 50   
MIN_POS             = 0    
MAX_POS             = 4095 
MAX_TORQUE_PWM      = 885  # Full electrical power

# --- THE VIRTUAL SPRING TENSION ---
# Increased from 150 to 450.
# This creates a much larger error gap, forcing the motor's PID controller 
# to pull aggressively to overcome the static friction of the dual tendons.
MAX_LEAD            = 450  

def get_key():
    if select.select([sys.stdin], [], [], 0) == ([sys.stdin], [], []):
        c = sys.stdin.read(1)
        if c == '\x1b':
            c2 = sys.stdin.read(1)
            c3 = sys.stdin.read(1)
            if c2 == '[':
                if c3 == 'A': return 'UP'
                elif c3 == 'B': return 'DOWN'
                elif c3 == 'C': return 'RIGHT'
                elif c3 == 'D': return 'LEFT'
        elif c == '\n' or c == '\r':
            return 'ENTER'
        return c
    return None

def main():
    portHandler = PortHandler(DEVICENAME)
    packetHandler = PacketHandler(PROTOCOL_VERSION)
    
    groupSyncWrite = GroupSyncWrite(portHandler, packetHandler, ADDR_GOAL_POSITION, LEN_GOAL_POSITION)
    groupSyncRead = GroupSyncRead(portHandler, packetHandler, ADDR_PRESENT_POSITION, LEN_PRESENT_POSITION)

    if not portHandler.openPort() or not portHandler.setBaudRate(BAUDRATE):
        print("Failed to open the port. Check connection.")
        quit()

    # 1. Dynamic Motor Discovery
    print("Scanning for connected motors...")
    active_ids = []
    for dxl_id in range(1, 17):
        dxl_model_number, dxl_comm_result, dxl_error = packetHandler.ping(portHandler, dxl_id)
        if dxl_comm_result == COMM_SUCCESS:
            active_ids.append(dxl_id)
            groupSyncRead.addParam(dxl_id)
            
    if not active_ids:
        print("No motors detected. Exiting.")
        portHandler.closePort()
        quit()

    print(f"Active Motor Array: {active_ids}")

    # 2. Restore Max Power
    print(f"Setting full power limits (Goal PWM: {MAX_TORQUE_PWM}/885)...")
    for dxl_id in active_ids:
        packetHandler.write2ByteTxRx(portHandler, dxl_id, ADDR_GOAL_PWM, MAX_TORQUE_PWM)

    # 3. Read Startup Positions
    targets = {} 
    for dxl_id in active_ids:
        dxl_present_position, dxl_comm_result, dxl_error = packetHandler.read4ByteTxRx(portHandler, dxl_id, ADDR_PRESENT_POSITION)
        if dxl_comm_result == COMM_SUCCESS:
            targets[dxl_id] = dxl_present_position
        else:
            targets[dxl_id] = 2048

    # 4. Enable Torque
    print("Enabling Torque...")
    for dxl_id in active_ids:
        packetHandler.write1ByteTxRx(portHandler, dxl_id, ADDR_TORQUE_ENABLE, TORQUE_ENABLE)

    selected_mode = "ALL" 
    print("\n--- Heavy-Lift Teleop Active ---")
    print("Press [ENTER] to switch between Single/All mode")
    print("Press 'q' or Ctrl+C to quit\n")

    old_term_settings = termios.tcgetattr(sys.stdin)
    tty.setcbreak(sys.stdin.fileno())
    
    try:
        while True:
            try:
                # --- A. READ SENSORS ---
                actual_positions = {}
                dxl_comm_result = groupSyncRead.txRxPacket()
                if dxl_comm_result == COMM_SUCCESS:
                    for dxl_id in active_ids:
                        if groupSyncRead.isAvailable(dxl_id, ADDR_PRESENT_POSITION, LEN_PRESENT_POSITION):
                            actual_positions[dxl_id] = groupSyncRead.getData(dxl_id, ADDR_PRESENT_POSITION, LEN_PRESENT_POSITION)

                # --- B. PROCESS INPUT ---
                key = get_key()
                if key == 'ENTER':
                    termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_term_settings)
                    user_input = input("\n\nEnter Motor ID to control (or press Enter for ALL): ").strip()
                    if user_input == "" or user_input.lower() == "all":
                        selected_mode = "ALL"
                    else:
                        try:
                            input_id = int(user_input)
                            if input_id in active_ids: selected_mode = input_id
                        except ValueError: pass
                    print(f"-> Mode set to: {selected_mode}\n")
                    tty.setcbreak(sys.stdin.fileno())

                elif key in ['UP', 'RIGHT', 'DOWN', 'LEFT']:
                    direction = 1 if key in ['UP', 'RIGHT'] else -1
                    delta = direction * POS_STEP

                    if selected_mode == "ALL":
                        for dxl_id in active_ids:
                            targets[dxl_id] = max(MIN_POS, min(MAX_POS, targets[dxl_id] + delta))
                        print(f"\r[ALL] Target adjusted...      ", end="")
                    else:
                        targets[selected_mode] = max(MIN_POS, min(MAX_POS, targets[selected_mode] + delta))
                        print(f"\r[ID {selected_mode}] Target: {targets[selected_mode]}      ", end="")
                elif key == 'q' or key == '\x03':
                    break

                # --- C. THE VIRTUAL SPRING CLAMP ---
                if actual_positions:
                    for dxl_id in active_ids:
                        actual_pos = actual_positions[dxl_id]
                        target_pos = targets[dxl_id]
                        
                        # The widened gap (450) forces the motor to fight friction harder
                        if target_pos > actual_pos + MAX_LEAD:
                            targets[dxl_id] = actual_pos + MAX_LEAD
                        elif target_pos < actual_pos - MAX_LEAD:
                            targets[dxl_id] = actual_pos - MAX_LEAD

                # --- D. SEND COMMANDS ---
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

            except serial.SerialException:
                print("\r[WARNING] Serial connection dropped momentarily. Retrying...   ", end="")
                time.sleep(0.1)
            except Exception as inner_e:
                pass 

    except KeyboardInterrupt:
        pass 
        
    finally:
        termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_term_settings)
        print("\n\nDisabling Torque...")
        for dxl_id in active_ids:
            packetHandler.write1ByteTxRx(portHandler, dxl_id, ADDR_TORQUE_ENABLE, TORQUE_DISABLE)
        portHandler.closePort()
        print("Port closed.")

if __name__ == '__main__':
    main()