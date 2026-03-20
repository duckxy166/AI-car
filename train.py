"""
AI Car Parking - PPO Training Script
Uses godot-rl + stable-baselines3 to train a parking agent

Usage:
  1. Open Godot project → set main scene to res://scenes/training.tscn
  2. Run: python train.py
  3. Press Play in Godot (or use --env_path to auto-launch)
  4. After training, export ONNX model for inference
"""

import os
import argparse
from datetime import datetime

from godot_rl.wrappers.stable_baselines_wrapper import StableBaselinesGodotEnv
from stable_baselines3 import PPO
from stable_baselines3.common.callbacks import CheckpointCallback, EvalCallback
from stable_baselines3.common.vec_env import VecMonitor


def parse_args():
    parser = argparse.ArgumentParser(description="Train AI parking agent")
    parser.add_argument("--env_path", type=str, default=None,
                        help="Path to Godot executable (None = connect to running editor)")
    parser.add_argument("--speedup", type=int, default=8,
                        help="Training speedup factor")
    parser.add_argument("--total_timesteps", type=int, default=2_000_000,
                        help="Total training timesteps")
    parser.add_argument("--lr", type=float, default=3e-4,
                        help="Learning rate")
    parser.add_argument("--batch_size", type=int, default=64,
                        help="Mini-batch size")
    parser.add_argument("--n_steps", type=int, default=2048,
                        help="Steps per rollout per env")
    parser.add_argument("--n_epochs", type=int, default=10,
                        help="Number of PPO epochs per update")
    parser.add_argument("--gamma", type=float, default=0.99,
                        help="Discount factor")
    parser.add_argument("--gae_lambda", type=float, default=0.95,
                        help="GAE lambda")
    parser.add_argument("--clip_range", type=float, default=0.2,
                        help="PPO clip range")
    parser.add_argument("--ent_coef", type=float, default=0.01,
                        help="Entropy coefficient")
    parser.add_argument("--vf_coef", type=float, default=0.5,
                        help="Value function coefficient")
    parser.add_argument("--max_grad_norm", type=float, default=0.5,
                        help="Max gradient norm")
    parser.add_argument("--resume", type=str, default=None,
                        help="Path to model zip to resume training from")
    parser.add_argument("--export_onnx", action="store_true",
                        help="Export ONNX after training")
    parser.add_argument("--export_only", type=str, default=None,
                        help="Export ONNX from saved model (no training). Pass path to .zip model")
    return parser.parse_args()


def main():
    args = parse_args()

    # Export-only mode: no training needed, no Godot connection
    if args.export_only:
        export_from_saved(args.export_only)
        return

    # Create output directories
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_dir = f"runs/parking_{timestamp}"
    os.makedirs(log_dir, exist_ok=True)
    os.makedirs(f"{log_dir}/checkpoints", exist_ok=True)

    print("=" * 60)
    print("  AI Car Parking - PPO Training")
    print("=" * 60)
    print(f"  Log dir:         {log_dir}")
    print(f"  Total timesteps: {args.total_timesteps:,}")
    print(f"  Learning rate:   {args.lr}")
    print(f"  Batch size:      {args.batch_size}")
    print(f"  N steps:         {args.n_steps}")
    print(f"  Speedup:         {args.speedup}x")
    print("=" * 60)

    # Create Godot RL environment
    env_kwargs = {
        "show_window": True,
        "speedup": args.speedup,
        "action_repeat": 4,
    }
    if args.env_path:
        env_kwargs["env_path"] = args.env_path

    print("\nConnecting to Godot environment...")
    print("(Make sure training.tscn is running in Godot Editor)")
    env = StableBaselinesGodotEnv(**env_kwargs)
    env = VecMonitor(env)

    print(f"  Observation space: {env.observation_space}")
    print(f"  Action space:      {env.action_space}")
    print(f"  Num envs:          {env.num_envs}")

    # Create or load PPO model
    if args.resume:
        print(f"\nResuming from: {args.resume}")
        model = PPO.load(args.resume, env=env)
    else:
        model = PPO(
            "MultiInputPolicy",
            env,
            learning_rate=args.lr,
            n_steps=args.n_steps,
            batch_size=args.batch_size,
            n_epochs=args.n_epochs,
            gamma=args.gamma,
            gae_lambda=args.gae_lambda,
            clip_range=args.clip_range,
            ent_coef=args.ent_coef,
            vf_coef=args.vf_coef,
            max_grad_norm=args.max_grad_norm,
            verbose=1,
            tensorboard_log=f"{log_dir}/tb_logs",
            policy_kwargs={
                "net_arch": dict(pi=[256, 256], vf=[256, 256]),
            },
        )

    # Callbacks
    checkpoint_cb = CheckpointCallback(
        save_freq=max(args.total_timesteps // 20, 10_000),
        save_path=f"{log_dir}/checkpoints",
        name_prefix="parking_ppo",
    )

    # Train
    print("\nStarting training...")
    try:
        model.learn(
            total_timesteps=args.total_timesteps,
            callback=checkpoint_cb,
            progress_bar=True,
        )
    except KeyboardInterrupt:
        print("\n\nTraining interrupted by user.")

    # Save final model
    final_path = f"{log_dir}/parking_ppo_final"
    model.save(final_path)
    print(f"\nModel saved to: {final_path}.zip")

    # Export ONNX if requested
    if args.export_onnx:
        # Get obs size from Dict observation space
        obs_size = env.observation_space["obs"].shape[0]
        export_to_onnx(model, log_dir, obs_size)

    env.close()
    print("\nDone!")


def export_to_onnx(model, log_dir, obs_size=21):
    """Export trained model to ONNX format for Godot inference"""
    try:
        import torch
        import torch.onnx

        onnx_path = f"{log_dir}/parking_model.onnx"
        print(f"\nExporting ONNX model to: {onnx_path}")

        policy = model.policy
        dummy_input = torch.randn(1, obs_size)

        class PolicyWrapper(torch.nn.Module):
            def __init__(self, policy):
                super().__init__()
                # Copy the layers directly so torch.onnx can trace them
                self.features_extractor = policy.features_extractor
                self.mlp_extractor = policy.mlp_extractor
                self.action_net = policy.action_net
                self.log_std = policy.log_std

            def forward(self, obs):
                # MultiInputPolicy features_extractor expects dict,
                # but for ONNX we extract the 'obs' key's extractor directly
                features = self.features_extractor.extractors["obs"](obs)
                latent_pi = self.mlp_extractor.forward_actor(features)
                mean_actions = self.action_net(latent_pi)
                return torch.cat([mean_actions, self.log_std.expand_as(mean_actions)], dim=-1)

        wrapper = PolicyWrapper(policy)
        wrapper.eval()

        torch.onnx.export(
            wrapper,
            dummy_input,
            onnx_path,
            input_names=["obs"],
            output_names=["output"],
            dynamic_axes={"obs": {0: "batch"}, "output": {0: "batch"}},
            opset_version=15,
            dynamo=False,
        )

        print(f"ONNX model exported successfully!")
        print(f"Copy to: model/parking_model.onnx")

        # Auto-copy to model/ folder
        model_dir = "model"
        os.makedirs(model_dir, exist_ok=True)
        import shutil
        dest = os.path.join(model_dir, "parking_model.onnx")
        shutil.copy2(onnx_path, dest)
        print(f"Copied to: {dest}")

    except Exception as e:
        import traceback
        print(f"ONNX export failed: {e}")
        traceback.print_exc()


def export_from_saved(model_path: str):
    """Export ONNX from a previously saved model (no Godot needed)"""
    print("=" * 60)
    print("  ONNX Export from Saved Model")
    print("=" * 60)
    print(f"  Model: {model_path}")

    if not os.path.exists(model_path):
        print(f"ERROR: Model file not found: {model_path}")
        return

    model = PPO.load(model_path)
    log_dir = os.path.dirname(model_path)
    export_to_onnx(model, log_dir)


if __name__ == "__main__":
    main()
