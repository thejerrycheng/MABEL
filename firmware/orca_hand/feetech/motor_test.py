#!/usr/bin/env python3
import time
from scservo_sdk.port_handler import PortHandler
from scservo_sdk.sms_sts import sms_sts, SMS_STS_TORQUE_ENABLE, SMS_STS_PRESENT_POSITION_L
from scservo_sdk.group_sync_read import GroupSyncRead

# Configuration
PORT_NAME = '/dev/ttyUSB0'
BAUDRATE = 1000000
SERVO_IDS = list(range(1, 18))  # IDs 1 through 17

class OrcaHandController:
    def __init__(self, port_name, baudrate, servo_ids):
        self.port = PortHandler(port_name)
        self.servo_ids = servo_ids
        
        if not self.port.openPort():
            raise Exception("Failed to open port!")
        if not self.port.setBaudRate(baudrate):
            raise Exception("Failed to set baudrate!")
            
        self.sts = sms_sts(self.port)
        
        # Initialize SyncRead for 6 bytes starting at PRESENT_POSITION_L (56)
        # This covers Pos (2 bytes), Speed (2 bytes), Load (2 bytes)
        self.sync_read = GroupSyncRead(self.port, SMS_STS_PRESENT_POSITION_L, 6)
        
    def enable_torque(self):
        """Enables torque for all connected motors."""
        for scs_id in self.servo_ids:
            self.sts.write1ByteTxRx(scs_id, SMS_STS_TORQUE_ENABLE, 1)
        print("Torque enabled for all hand actuators.")

    def disable_torque(self):
        """Disables torque for safe handling."""
        for scs_id in self.servo_ids:
            self.sts.write1ByteTxRx(scs_id, SMS_STS_TORQUE_ENABLE, 0)
        print("Torque disabled.")

    def set_sync_targets(self, targets):
        """
        targets: dictionary format { id: (position, speed, acceleration) }
        """
        for scs_id, (pos, speed, acc) in targets.items():
            # Add to SyncWrite queue
            self.sts.SyncWritePosEx(scs_id, pos, speed, acc)
            
        # Fire the bulk packet
        self.sts.groupSyncWrite.txPacket()
        self.sts.groupSyncWrite.clearParam()

    def get_sync_states(self):
        """
        Returns { id: {'pos': int, 'speed': int, 'load': int, 'overload': bool} }
        """
        for scs_id in self.servo_ids:
            self.sync_read.addParam(scs_id)
            
        result = self.sync_read.txRxPacket()
        states = {}
        
        if result == 0: # COMM_SUCCESS
            for scs_id in self.servo_ids:
                if self.sync_read.isAvailable(scs_id, SMS_STS_PRESENT_POSITION_L, 6):
                    # Read Raw Bytes
                    raw_pos = self.sync_read.getData(scs_id, SMS_STS_PRESENT_POSITION_L, 2)
                    raw_speed = self.sync_read.getData(scs_id, SMS_STS_PRESENT_POSITION_L + 2, 2)
                    raw_load = self.sync_read.getData(scs_id, SMS_STS_PRESENT_POSITION_L + 4, 2)
                    
                    # Error byte is extracted internally by group_sync_read during rxPacket
                    # For a tighter loop, we monitor the raw load value for spikes
                    
                    states[scs_id] = {
                        'pos': self.sts.scs_tohost(raw_pos, 15),
                        'speed': self.sts.scs_tohost(raw_speed, 15),
                        'load': self.sts.scs_tohost(raw_load, 10),
                        'overload': abs(self.sts.scs_tohost(raw_load, 10)) > 900 # Threshold tweakable
                    }
                    
        self.sync_read.clearParam()
        return states

if __name__ == "__main__":
    hand = OrcaHandController(PORT_NAME, BAUDRATE, SERVO_IDS)
    
    try:
        hand.enable_torque()
        
        # Example Teleoperation/Data Collection Loop
        while True:
            # 1. Read Current State
            states = hand.get_sync_states()
            
            if states:
                # Example: Print load of finger 1 to monitor for heavy lifting limits
                if 1 in states:
                    print(f"Motor 1 Load: {states[1]['load']}")
                    if states[1]['overload']:
                        print("WARNING: Load spike detected on Motor 1!")

            # 2. Compute new targets (e.g., from MediaPipe tracking)
            # For demonstration, we just command them to hold a zero position
            new_targets = {}
            for scs_id in SERVO_IDS:
                # (position, speed, acceleration)
                new_targets[scs_id] = (2048, 1500, 50) 
                
            # 3. Write Targets
            hand.set_sync_targets(new_targets)
            
            # Maintain loop rate
            time.sleep(0.01) # 100Hz loop

    except KeyboardInterrupt:
        print("\nStopping hand...")
    finally:
        hand.disable_torque()
        hand.port.closePort()