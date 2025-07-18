# Apple-Foundation-Model-Reasoning-Swift-Demo
Experiment to increase the reasoning capabilities of Apple's Foundation Model.

Available modes:
- Zero-Shot
- Zero-Shot-Chain-of-Thought
- Self-Consistency

Currently every answer will be generated with these configurations:
- Sampling Method: random sampling with a top-k filter of 5
- Seed: not set (random)
- Temperature: 0.2

The modes and prompts were created based on the paper "Prompt Engineering" by Lee Boonstra (Google) -> https://www.kaggle.com/whitepaper-prompt-engineering

(The code currently uses a lot of repeated code for testing, will be removed later)

