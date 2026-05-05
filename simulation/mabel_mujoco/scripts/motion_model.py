import os
import mujoco
import mujoco.viewer
from pynput import keyboard
import numpy as np
import math
import time

# --- Robot Physical Parameters ---
WHEEL_RADIUS = 0.05

# Dynamic Speed Limits
MAX_LIN_SPEED = 0.8  # m/s
MAX_ANG_SPEED = 2.0  # rad/s
LIFT_SPEED = 0.15    # m/s (How fast the lift travels when key is held)

# Acceleration Limits (m/s^2 and rad/s^2)
MAX_LIN_ACCEL = 1.5  
MAX_ANG_ACCEL = 4.0  

# Wheel coordinates [x, y] relative to chassis center
MODULE_POSITIONS = {
    'fl': np.array([0.2, 0.2]),
    'fr': np.array([0.2, -0.2]),
    'bc': np.array([-0.2, 0.0])
}

# --- Teleop State Tracker ---
pressed_keys = set()
current_vx, current_vy, current_omega = 0.0, 0.0, 0.0
target_lift_pos = 0.0  # Starts at bottom (0.0 meters)

def on_press(key):
    global MAX_LIN_SPEED, MAX_ANG_SPEED
    try:
        char = key.char.lower()
        if char not in pressed_keys:
            if char == 'i':
                MAX_LIN_SPEED = min(3.0, MAX_LIN_SPEED + 0.1)
                print(f"[Speed] Max Linear: {MAX_LIN_SPEED:.1f} m/s")
            elif char == 'k':
                MAX_LIN_SPEED = max(0.1, MAX_LIN_SPEED - 0.1)
                print(f"[Speed] Max Linear: {MAX_LIN_SPEED:.1f} m/s")
            elif char == 'o':
                MAX_ANG_SPEED = min(5.0, MAX_ANG_SPEED + 0.2)
                print(f"[Speed] Max Angular: {MAX_ANG_SPEED:.1f} rad/s")
            elif char == 'l':
                MAX_ANG_SPEED = max(0.2, MAX_ANG_SPEED - 0.2)
                print(f"[Speed] Max Angular: {MAX_ANG_SPEED:.1f} rad/s")
                
        pressed_keys.add(char)
    except AttributeError:
        pressed_keys.add(key)

def on_release(key):
    try:
        pressed_keys.discard(key.char.lower())
    except AttributeError:
        pressed_keys.discard(key)

def optimize_steering(target_angle, current_angle):
    """ Prevents the steering column from spinning > 90 degrees. """
    diff = (target_angle - current_angle + math.pi) % (2 * math.pi) - math.pi
    direction_multiplier = 1.0
    
    if diff > math.pi / 2:
        target_angle -= math.pi
        direction_multiplier = -1.0
    elif diff < -math.pi / 2:
        target_angle += math.pi
        direction_multiplier = -1.0
        
    diff = (target_angle - current_angle + math.pi) % (2 * math.pi) - math.pi
    optimal_angle = current_angle + diff
    return optimal_angle, direction_multiplier

def swerve_ik(vx, vy, omega, data):
    """ Calculates and applies actuator commands with Anti-Slip Logic """
    for key, r in MODULE_POSITIONS.items():
        v_ix = vx - omega * r[1]
        v_iy = vy + omega * r[0]
        v_mag = math.sqrt(v_ix**2 + v_iy**2)
        
        steer_actuator = f"act_steer_{key}"
        drive_actuator = f"act_drive_{key}"
        steer_joint = f"steer_{key}"
        current_theta = data.joint(steer_joint).qpos[0]
        
        if v_mag > 1e-3:
            raw_target_theta = math.atan2(v_iy, v_ix)
            optimal_theta, dir_mult = optimize_steering(raw_target_theta, current_theta)
            
            # --- Anti-Slip Logic ---
            angle_error = abs(optimal_theta - current_theta)
            drive_scale = max(0.0, math.cos(angle_error))
            if angle_error > 0.45: 
                drive_scale = 0.0
                
            wheel_omega = (v_mag / WHEEL_RADIUS) * dir_mult * drive_scale
            
            data.actuator(steer_actuator).ctrl[0] = optimal_theta
            data.actuator(drive_actuator).ctrl[0] = wheel_omega
        else:
            data.actuator(steer_actuator).ctrl[0] = current_theta
            data.actuator(drive_actuator).ctrl[0] = 0.0

def main():
    global current_vx, current_vy, current_omega, target_lift_pos
    
    listener = keyboard.Listener(on_press=on_press, on_release=on_release)
    listener.start()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    xml_path = os.path.join(script_dir, "../componments/test_scene.xml")

    model = mujoco.MjModel.from_xml_path(xml_path)
    data = mujoco.MjData(model)

    print("--- Mabel Teleop Initiated ---")
    print("[UP/DOWN]    : Move Forward / Backward (X-Axis)")
    print("[LEFT/RIGHT] : Strafe Left / Right (Y-Axis)")
    print("[W / S]      : Rotate CCW / CW (Z-Axis)")
    print("[E / D]      : Raise / Lower Lift (Z-Axis)")
    print("[I / K]      : Max Linear Speed (+/- 0.1 m/s)")
    print("[O / L]      : Max Angular Speed (+/- 0.2 rad/s)")
    print("---------------------------------------")

    with mujoco.viewer.launch_passive(model, data) as viewer:
        while viewer.is_running():
            step_start = time.time()
            dt = model.opt.timestep
            
            # 1. Read target state from keyboard for Swerve Base
            target_vx, target_vy, target_omega = 0.0, 0.0, 0.0
            if keyboard.Key.up in pressed_keys:    target_vx += MAX_LIN_SPEED
            if keyboard.Key.down in pressed_keys:  target_vx -= MAX_LIN_SPEED
            if keyboard.Key.left in pressed_keys:  target_vy += MAX_LIN_SPEED  
            if keyboard.Key.right in pressed_keys: target_vy -= MAX_LIN_SPEED
            if 'w' in pressed_keys:                target_omega += MAX_ANG_SPEED
            if 's' in pressed_keys:                target_omega -= MAX_ANG_SPEED

            # 2. Read target state from keyboard for the Lift
            if 'e' in pressed_keys: target_lift_pos += LIFT_SPEED * dt
            if 'd' in pressed_keys: target_lift_pos -= LIFT_SPEED * dt
            
            # Clamp the lift position strictly between 0.0 and 0.4 meters
            target_lift_pos = max(0.0, min(0.4, target_lift_pos))

            # 3. Strict Kinematic Acceleration Ramps (Swerve Base)
            if current_vx < target_vx: current_vx = min(target_vx, current_vx + MAX_LIN_ACCEL * dt)
            elif current_vx > target_vx: current_vx = max(target_vx, current_vx - MAX_LIN_ACCEL * dt)
            
            if current_vy < target_vy: current_vy = min(target_vy, current_vy + MAX_LIN_ACCEL * dt)
            elif current_vy > target_vy: current_vy = max(target_vy, current_vy - MAX_LIN_ACCEL * dt)
            
            if current_omega < target_omega: current_omega = min(target_omega, current_omega + MAX_ANG_ACCEL * dt)
            elif current_omega > target_omega: current_omega = max(target_omega, current_omega - MAX_ANG_ACCEL * dt)

            # 4. Apply Commands to Actuators
            swerve_ik(current_vx, current_vy, current_omega, data)
            data.actuator("act_lift").ctrl[0] = target_lift_pos

            mujoco.mj_step(model, data)
            viewer.sync()

            time_until_next_step = dt - (time.time() - step_start)
            if time_until_next_step > 0:
                time.sleep(time_until_next_step)

if __name__ == "__main__":
    main()