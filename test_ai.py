"""
AI Car Parking - Watch AI Drive!
Loads trained model and sends actions to Godot in real-time.

Usage:
  1. Open Godot → open test_drive.tscn → Press Play
  2. Run: python test_ai.py
  3. (Optional) python test_ai.py --model runs/parking_XXXX/parking_ppo_final.zip
"""

import os
import sys
import glob
import argparse
from godot_rl.wrappers.stable_baselines_wrapper import StableBaselinesGodotEnv
from stable_baselines3 import PPO


def find_latest_model():
    """Find the most recently trained model"""
    patterns = [
        "runs/*/parking_ppo_final.zip",
        "runs/*/checkpoints/parking_ppo_*_steps.zip",
    ]
    all_models = []
    for pattern in patterns:
        all_models.extend(glob.glob(pattern))

    if not all_models:
        return None

    # Sort by modification time, newest first
    all_models.sort(key=os.path.getmtime, reverse=True)
    return all_models[0]


def main():
    parser = argparse.ArgumentParser(description="Watch AI drive!")
    parser.add_argument("--model", type=str, default=None,
                        help="Path to model .zip (default: latest)")
    parser.add_argument("--episodes", type=int, default=0,
                        help="Number of episodes to watch (0 = infinite)")
    args = parser.parse_args()

    # Find model
    model_path = args.model or find_latest_model()
    if not model_path:
        print("ERROR: No trained model found!")
        print("Train first: python train.py --export_onnx")
        sys.exit(1)

    print("=" * 50)
    print("  AI Car Parking - Watch AI Drive!")
    print("=" * 50)
    print(f"  Model: {model_path}")
    print("=" * 50)

    # Connect to Godot (test_drive.tscn must be running)
    print("\nConnecting to Godot...")
    print("(Open test_drive.tscn in Godot and press Play)")
    env = StableBaselinesGodotEnv(
        show_window=True,
        speedup=1,       # Real-time speed for watching
        action_repeat=4,
    )

    print(f"  Obs space:  {env.observation_space}")
    print(f"  Act space:  {env.action_space}")
    print(f"  Num envs:   {env.num_envs}")

    # Load model
    print(f"\nLoading model...")
    model = PPO.load(model_path, env=env)
    print("Model loaded! Watching AI drive...\n")

    # Run
    obs = env.reset()
    episode = 0
    step = 0
    try:
        while True:
            action, _ = model.predict(obs, deterministic=True)
            obs, rewards, dones, infos = env.step(action)
            step += 1

            for i, done in enumerate(dones):
                if done:
                    episode += 1
                    print(f"  Episode {episode} done! (step {step}, reward: {rewards[i]:.2f})")

                    if args.episodes > 0 and episode >= args.episodes:
                        print(f"\n{args.episodes} episodes complete!")
                        env.close()
                        return

    except KeyboardInterrupt:
        print(f"\nStopped after {episode} episodes, {step} steps")

    env.close()
    print("Done!")


if __name__ == "__main__":
    main()
