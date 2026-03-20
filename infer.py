"""
AI Car Parking - Inference Script
Loads a trained model and runs it in Godot (via socket, same as training).

Usage:
  1. Open Godot → run test_drive.tscn (control_mode = TRAINING)
  2. Run: python infer.py
  3. Watch สมศักดิ์ drive!

  Options:
    --model_path  Path to saved model (default: latest run)
    --deterministic  Use deterministic actions (no randomness)
"""

import os
import argparse
import glob

from godot_rl.wrappers.stable_baselines_wrapper import StableBaselinesGodotEnv
from stable_baselines3 import PPO
from stable_baselines3.common.vec_env import VecMonitor
import numpy as np


def find_latest_model():
    """Find the most recent training run's final model"""
    runs = sorted(glob.glob("runs/parking_*/parking_ppo_final.zip"))
    if runs:
        return runs[-1]
    return None


def parse_args():
    parser = argparse.ArgumentParser(description="Run trained AI parking agent")
    parser.add_argument("--model_path", type=str, default=None,
                        help="Path to model .zip (default: latest run)")
    parser.add_argument("--deterministic", action="store_true", default=True,
                        help="Use deterministic actions")
    parser.add_argument("--episodes", type=int, default=0,
                        help="Number of episodes to run (0 = infinite)")
    return parser.parse_args()


def main():
    args = parse_args()

    # Find model
    model_path = args.model_path or find_latest_model()
    if not model_path or not os.path.exists(model_path):
        print("ERROR: No trained model found!")
        print("  Train first: python train.py --export_onnx")
        print("  Or specify:  python infer.py --model_path path/to/model.zip")
        return

    print("=" * 60)
    print("  AI Car Parking - สมศักดิ์ Inference")
    print("=" * 60)
    print(f"  Model: {model_path}")
    print(f"  Deterministic: {args.deterministic}")
    print("=" * 60)

    # Connect to Godot
    print("\nConnecting to Godot...")
    print("(Make sure test_drive.tscn is running in Godot Editor)")
    env = StableBaselinesGodotEnv(show_window=True, speedup=1, action_repeat=1)
    env = VecMonitor(env)

    # Load model
    print(f"Loading model: {model_path}")
    model = PPO.load(model_path, env=env)
    print("Model loaded! สมศักดิ์ is driving...\n")

    # Run inference loop
    obs = env.reset()
    episode = 0
    step = 0

    try:
        while True:
            action, _ = model.predict(obs, deterministic=args.deterministic)
            obs, reward, done, info = env.step(action)
            step += 1

            if any(done):
                episode += 1
                print(f"  Episode {episode} done (step {step})")
                if args.episodes > 0 and episode >= args.episodes:
                    break

    except KeyboardInterrupt:
        print(f"\n\nStopped after {episode} episodes, {step} steps.")

    env.close()
    print("Done!")


if __name__ == "__main__":
    main()
