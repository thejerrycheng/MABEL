#!/usr/bin/env python3
import time
from scservo_sdk.port_handler import PortHandler
from scservo_sdk.sms_sts import sms_sts, SMS_STS_ID

# Configuration
PORT_NAME = '/dev/ttyUSB0'
BAUDRATE = 1000000

def setup_id(target_id):
    port = PortHandler(PORT_NAME)
    
    if not port.openPort():
        print("Failed to open port")
        return
    if not port.setBaudRate(BAUDRATE):
        print("Failed to set baudrate")
        return

    sts = sms_sts(port)
    default_id = 1
    
    print(f"Attempting to change servo ID from {default_id} to {target_id}...")
    
    # 1. Unlock EPROM
    sts.unLockEprom(default_id)
    time.sleep(0.1)
    
    # 2. Write new ID
    sts.write1ByteTxRx(default_id, SMS_STS_ID, target_id)
    time.sleep(0.1)
    
    # 3. Lock EPROM
    sts.LockEprom(target_id)
    time.sleep(0.1)
    
    # Verify the change by pinging the new ID
    model_number, result, _ = sts.ping(target_id)
    if result == 0:
        print(f"SUCCESS! Motor is now ID {target_id}. (Model: {model_number})")
        print("Disconnect this motor and plug in the next one.")
    else:
        print("FAILED to verify new ID. Check power and connections.")

    port.closePort()

if __name__ == "__main__":
    # Change this number, run the script, swap the motor, repeat.
    NEW_ID = 2 
    setup_id(NEW_ID)