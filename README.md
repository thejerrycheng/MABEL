
# 🤖 MABEL: Mobile Animated Bimanual Extensible Platform

[![ROS 2](https://img.shields.io/badge/ROS_2-Humble-blue.svg)](https://docs.ros.org/en/humble/)
[![Python 3.10](https://img.shields.io/badge/Python-3.10-blue.svg)](https://www.python.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Simulation](https://img.shields.io/badge/Simulation-MuJoCo_%7C_Isaac_Lab-orange.svg)]()

**MABEL** is an open-source, sub-$8k mobile bimanual robot designed for long-horizon dexterous manipulation, active perception, and expressive human-robot interaction. 

Built as the foundation for state-of-the-art PhD research, MABEL combines the rugged mobility of an omnidirectional swerve drive with the high-fidelity dexterity of 17-DOF ORCA hands. Taking design and interactive cues from Apple, Bambu Lab, and Disney Research, MABEL isn't just a research tool—it's a lifelike, expressive platform featuring Vision Pro teleoperation and built-in ML data pipelines.

---

## 🌟 Key Features

* **Holonomic Swerve Base:** 3-module independent swerve drive adapted from First Robotics for agile, omnidirectional navigation.
* **High-DOF Manipulation:** Dual 7-DOF arms (based on Open Arm) ending in 17-DOF ORCA hands (16 for fingers, 1 for wrist). 
* **Dynamic Workspace:** Integrated standing desk lift mechanism and a torso tilt joint for massive vertical and horizontal reach.
* **Active Perception:** 3-DOF rotational head camera, dual wrist cameras for eye-in-hand manipulation, and base LiDAR for SLAM.
* **Lifelike Interaction (HRI):** 13-inch body touchscreen and animated LED matrix eyes that react to the robot's state, taking inspiration from character animation (e.g., Disney's Olaf).
* **Apple Vision Pro Teleoperation:** Custom visionOS app for ultra-low-latency spatial teleoperation and automated data logging.
* **Sub-$8k BOM:** Carefully engineered using 3D printed components, off-the-shelf actuators, and accessible sensors to democratize mobile manipulation.

---

## 🏗️ Hardware Architecture

* **Base:** 3x Swerve Drive modules, 2D Lidar, Base Compute (e.g., Mini PC).
* **Torso:** Linear actuator lift + Tilt motor + 13" Touchscreen.
* **Arms & Hands:** 2x 7-DOF Arms + 2x 17-DOF ORCA hands + Wrist Cameras.
* **Head:** 3-DOF Pan/Tilt/Roll neck + Stereo/RGB-D Camera + LED Matrix Eyes.

*(Detailed CAD files, STL models, and the full Bill of Materials can be found in the `/hardware` and `/docs` directories.)*

---

## 💻 Repository Structure

This repository is modularized to support hardware builders, ML researchers, and software engineers independently.

```text
mabel/
├── docs/                 # Assembly guides, BOM, and API documentation
├── docker/               # Containerized environments for ROS 2 and ML
├── hardware/             # CAD files, STLs, and custom PCB gerbers
├── firmware/             # Microcontroller code (Swerve, Hands, LED eyes)
├── simulation/           # MuJoCo and Isaac Lab environments
├── teleoperation/        # Vision Pro visionOS app and WebRTC streamers
├── learning/             # Data collection pipelines, RL, and IL scripts
├── ui_ux/                # Touchscreen UI and LED animation engine
└── ros_ws/               # Core ROS 2 Workspace
    ├── mabel_base/       # Swerve kinematics and hardware interfaces
    ├── mabel_manipulation/ # MoveIt2 configs for arms and hands
    ├── mabel_slam/       # SLAM Toolbox configurations
    └── mabel_navigation/ # Nav2 configurations for holonomic movement
````

-----

## 🚀 Getting Started

### Prerequisites

  * Ubuntu 22.04 LTS
  * ROS 2 Humble
  * Docker & NVIDIA Container Toolkit (Recommended for ML/Simulation)

### 1\. Installation (via Docker)

We highly recommend using Docker to avoid dependency conflicts.

```bash
git clone [https://github.com/yourusername/mabel.git](https://github.com/yourusername/mabel.git)
cd mabel/docker
docker compose up -d
docker exec -it mabel_core bash
```

### 2\. Building the ROS Workspace (Native)

If running natively on the robot's onboard PC:

```bash
cd mabel/ros_ws
colcon build --symlink-install
source install/setup.bash
```

### 3\. Launching the System

To bring up the entire hardware stack (Base, Arms, Cameras, UI):

```bash
ros2 launch mabel_bringup full_system.launch.py
```

To launch the MuJoCo simulation instead:

```bash
ros2 launch mabel_bringup sim_mujoco.launch.py
```

-----

## 🎮 Teleoperation & Data Collection

MABEL natively supports spatial teleoperation via Apple Vision Pro.

1.  Ensure the Vision Pro and MABEL are on the same local network.
2.  Launch the WebRTC bridge on the robot: `ros2 launch mabel_bringup teleop_bridge.launch.py`
3.  Open the MABEL visionOS app and connect.
4.  Teleoperation data is automatically saved in HDF5/Zarr format in the `~/.mabel_data/` directory, ready for Imitation Learning pipelines (e.g., ALOHA/ACT or Diffusion Policy).

-----

## 📝 Roadmap

  - [x] Base swerve kinematics and ROS 2 integration
  - [x] Arm and hand URDF generation
  - [ ] Vision Pro WebRTC integration
  - [ ] MuJoCo digital twin tuning
  - [ ] Disney-inspired state-machine for LED eye animations
  - [ ] System paper submission (ICRA/IROS)

-----

## 📖 Citation

If you use MABEL's hardware designs or software stack in your research, please cite our upcoming paper:

```bibtex
@article{cheng2026mabel,
  title={MABEL: A Sub-$8k Mobile Bimanual Platform for Dexterous Manipulation},
  author={Cheng, Jerry and [Co-authors]},
  journal={In Submission},
  year={2026}
}
```

## 🤝 Contributing & License

This project is licensed under the MIT License - see the [LICENSE](https://www.google.com/search?q=LICENSE) file for details. Pull requests for bug fixes, new features, or better documentation are highly encouraged\!


