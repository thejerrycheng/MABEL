# MABEL: Mobile Base & Lift Assembly

This repository contains the MuJoCo simulation environment and control scripts for **MABEL**, a mobile bimanual robot featuring a 3-module delta swerve drive base and a highly stable Z-axis lift mechanism.

This project is optimized for stable Whole-Body Control (WBC) and Reinforcement Learning, featuring a clean kinematic tree, realistic motor limits, and a robust inverse kinematics (IK) motion model.

---

## 📂 File Structure

```
├── components/
│   ├── mabel_assembled.xml   # Core robot definition (Chassis, Swerve Modules, Lift)
│   └── test_scene.xml        # Physics environment, integrator settings, and obstacles
└── scripts/
    └── motion_model.py       # Pynput-based teleop and Swerve IK controller
```

---

## 🏗️ Hardware Configuration & MuJoCo Architecture

### 1. Unified Floating Base

To optimize the kinematic tree for Whole-Body Control (WBC) and prevent unstable physics cross-coupling, the **mobile chassis** and the **lift base** are defined as a single, unified rigid `<body>`.

- This provides a true Center of Mass (CoM) near the geometric center (`X=0, Y=0`).
- Control math relies on this stable, centralized CoM rather than an arbitrary offset.

### 2. Collision Management

Instead of blindly toggling `contype` and `conaffinity` (which can cause the robot to fall through the floor), internal collisions are resolved strictly using MuJoCo's `<contact>` block. Specific `<exclude>` tags prevent the chassis from fighting the nested wheel grandchildren and moving lift segments, while preserving 100% collision accuracy with the external world.

### 3. Actuator Stability

- **Lift Constraints:** Soft constraints (`solimp` and `solref`) on the equality tags prevent "infinitely stiff" physics explosions during high-speed actuation.
- **Motor Torques:** Both the drive and steering motors utilize explicit `forcerange` limits. This prevents "Hand of God" instant acceleration, simulating real stall torques and allowing the Anti-Slip algorithm to function properly.

---

## 🧮 Swerve Inverse Kinematics (IK) Motion Model

The mobile base uses a 3-module delta swerve configuration. To achieve pure holonomic drive, the `motion_model.py` script calculates the exact steering angle and wheel rotation speed for all three modules simultaneously based on the target robot velocities.

### Target Velocity Vectors

Let the robot's target linear velocity be $V = [v_x, v_y]^T$ and its target angular velocity around its Center of Mass be $\omega$.

The target velocity vector $\mathbf{v}_i$ for any given wheel $i$ is the vector sum of the robot's overall translation, plus the tangential velocity caused by the robot's rotation:

$$\mathbf{v}_i = \mathbf{V} + \vec{\omega} \\times \mathbf{r}_i$$

Where $\mathbf{r}_i = [x_i, y_i]^T$ is the physical position of the wheel relative to the robot's center. In our 2D planar case, the cross product simplifies to:

$$v_{ix} = v_x - \omega \cdot y_i$$
$$v_{iy} = v_y + \omega \cdot x_i$$

### Actuator Commands

Once the target velocity vector $[v_{ix}, v_{iy}]$ for a wheel is established, we map this to the MuJoCo actuators:

**1. Steering Angle ($\theta_i$)** Calculated using the arctangent function to determine the wheel's required heading:
$$\theta_i = \\text{atan2}(v_{iy}, v_{ix})$$

**2. Drive Velocity ($\dot{\phi}_i$)** The magnitude of the target vector, divided by the wheel radius ($R$) to convert linear speed to rotational speed (rad/s):
$$\dot{\phi}_i = \\frac{\\sqrt{v_{ix}^2 + v_{iy}^2}}{R}$$

---

## 🛡️ Control Optimizations

The IK solver includes two critical algorithms to ensure the robot moves like a physical machine rather than a mathematical abstraction:

1. **Shortest-Path Steering Optimization:** If a commanded turn is greater than $90^\\circ$ ($\\pi/2$), it is mechanically inefficient for the steering column to sweep the long way around. The controller mathematically flips the target angle by $180^\\circ$ and multiplies the drive velocity by $-1.0$. The wheel steers a minimal distance and simply drives backward.

2. **Cosine Rule (Anti-Slip):** If the robot is commanded to instantly strafe left, the steering motors take a fraction of a second to sweep from $0^\\circ$ to $90^\\circ$. The drive power is scaled by the cosine of the steering error:  
   $$\\text{Drive Power} = \\max(0, \\cos(|\\theta_{target} - \\theta_{current}|))$$  
   If the wheel is out of alignment by more than $25^\\circ$ (0.45 rad), drive power is choked to `0.0` entirely until the steering column catches up, completely preventing tire scrubbing and physics engine jumping.

---

## 🚀 Usage

To launch the interactive teleop simulation:

```bash
# Ensure you are in the scripts directory or run via absolute path
python scripts/motion_model.py
```

**Controls:**

- **Arrow Keys**: Translate (Forward/Backward/Left/Right)
- **W / S**: Rotate (Counter-Clockwise / Clockwise)
- **E / D**: Raise / Lower the Lift
- **I / K**: Increase / Decrease Max Linear Speed
- **O / L**: Increase / Decrease Max Angular Speed
