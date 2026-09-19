# Causal World Model — DARPA Cyber Defense Framework
### Godot 4.3 · GDScript · Game Theory × Pearl Causal AI

---

## Overview

A real-time 3D Godot room implementing a **Structural Causal Model (SCM)** for
AI-augmented cyber defense, grounded in game-theoretic equilibrium reasoning.
The system simultaneously runs:

1. **Pearl's Causal Hierarchy** (Layers 1–3) over a live cyber-defense DAG
2. **Nash Equilibrium** solver (support enumeration, 4×4 bimatrix game)
3. **Strong Stackelberg Equilibrium** solver (gradient projection LP)
4. **Counterfactual inference** (abduction → action → prediction)
5. **Regret minimization** via Multiplicative Weights Update (MWU)
6. Live 3D visualization with holographic shaders and interactive interventions

---

## Directory Structure

```
causal_world_model/
├── project.godot                     ← Godot 4 project config + autoloads
├── scenes/
│   ├── main.tscn                     ← Main scene (room + DAG + HUD)
│   ├── CausalNode.tscn               ← Prefab: causal variable sphere
│   └── CausalEdge.tscn               ← Prefab: directed causal arrow
├── scripts/
│   ├── autoloads/
│   │   ├── CausalEngine.gd           ← SINGLETON: SCM core (do-calculus)
│   │   └── GameTheoryEngine.gd       ← SINGLETON: Nash + Stackelberg solvers
│   ├── world/
│   │   ├── CausalWorldModel.gd       ← Main scene controller
│   │   ├── CausalNode3D.gd           ← Per-node visualization + interaction
│   │   └── CausalEdge3D.gd           ← Per-edge animation (ImmediateMesh)
│   └── ui/
│       └── HUD.gd                    ← Full procedural HUD (no .tscn UI)
└── shaders/
    ├── causal_node.gdshader          ← Holographic sphere (fresnel + scanlines)
    └── causal_edge.gdshader          ← Flow-animated directed edge
```

---

## Causal DAG — Variable Definitions

### Exogenous Variables (U — background causes)

| ID              | Label               | Meaning                                              |
|-----------------|---------------------|------------------------------------------------------|
| `atk_cap`       | Attacker Capability | Adversary skill, tooling, zero-day inventory         |
| `net_exposure`  | Network Exposure    | CVE density, attack surface, patch lag               |
| `def_budget`    | Defender Budget     | SOC resources, analyst FTEs, tooling spend           |

### Endogenous Variables (V — causally determined)

| ID                | Layer | Structural Equation (simplified)                                         |
|-------------------|-------|--------------------------------------------------------------------------|
| `threat_level`    | 1     | `0.55·atk_cap + 0.45·net_exposure + U`                                   |
| `honeypot_density`| 1     | `0.28 + 0.35·def_budget − 0.10·threat_level + U`                         |
| `detection_rate`  | 1     | `0.40·def_budget + 0.35·hp_density − 0.30·threat_level + 0.35 + U`      |
| `nash_mixed_p`    | 2     | Indifference condition: `σ_D* = gain_stealth / (gain_probe + gain_stealth)` |
| `stackelberg_gain`| 2     | `0.4·def_budget·nash_mixed_p − 0.15·threat_level + U`                    |
| `attacker_success`| 2     | `0.65·threat − 0.55·detection − 0.40·honeypot − 0.20·sse_gain + U`      |
| `defender_payoff` | 3     | `0.50·(1−atk_succ) + 0.35·hp·detection − 0.25·budget + U`               |
| `info_asymmetry`  | 3     | `hp_density · detection · (1 − atk_success) + U`                         |

### Causal Edges (20 total)

```
atk_cap         →(+) threat_level
net_exposure    →(+) threat_level
def_budget      →(+) honeypot_density
def_budget      →(+) detection_rate
def_budget      →(+) nash_mixed_p
def_budget      →(+) stackelberg_gain
threat_level    →(−) detection_rate
threat_level    →(+) attacker_success
honeypot_density→(+) detection_rate
honeypot_density→(−) attacker_success
honeypot_density→(+) nash_mixed_p
honeypot_density→(+) info_asymmetry
detection_rate  →(−) attacker_success
detection_rate  →(+) defender_payoff
detection_rate  →(+) info_asymmetry
atk_cap         →(+) nash_mixed_p
nash_mixed_p    →(+) stackelberg_gain
stackelberg_gain→(−) attacker_success
attacker_success→(−) defender_payoff
attacker_success→(−) info_asymmetry
```

---

## Game Theory Model

### Bimatrix Game (4 × 4)

**Defender actions:** High Alert IDS | Deploy Honeypots | Normal Ops | Deception Mode
**Attacker actions:** Probe Noisily | Move Stealthily | Social Engineer | Zero-Day Exploit

Payoffs are **causal functions** of live SCM variables — the payoff matrix updates
every 0.5 s as CausalEngine propagates new values.

### Nash Equilibrium (NE)

Solved via **support enumeration**: iterate over all subsets S_D × S_A of action
supports, check indifference conditions, validate no profitable deviation exists.
Returns the NE with highest defender utility (Pareto-dominant NE selection rule).

```
NE condition:
  ∀ d ∈ supp(σ_D):  Σ_a σ_A(a)·U_D(d,a) = V_D     (defender indifferent)
  ∀ a ∈ supp(σ_A):  Σ_d σ_D(d)·U_A(d,a) = V_A     (attacker indifferent)
  ∀ d ∉ supp(σ_D):  Σ_a σ_A(a)·U_D(d,a) ≤ V_D     (no profitable deviation)
```

### Strong Stackelberg Equilibrium (SSE)

Solved via **gradient projection** onto the probability simplex (300 iterations):
defender commits to mixed strategy σ_D; attacker best-responds. SSE always
achieves ≥ NE payoff for the leader (commitment is a strategic advantage).

```
SSE: max_{σ_D} Σ_{d,a} σ_D(d)·BR_A(σ_D)(a)·U_D(d,a)
     s.t.  Σ_d σ_D(d) = 1,  σ_D(d) ≥ 0
           BR_A(σ_D) = argmax_a Σ_d σ_D(d)·U_A(d,a)
```

**Stackelberg Advantage Δ = SSE_payoff − NE_payoff** is displayed live.

### Regret Minimization

**Multiplicative Weights Update (MWU)** tracks cumulative regret per defender
action. Converges to a correlated equilibrium in the long run:

```
σ_D^{t+1}(i) ∝ exp(η · R_D^t(i))
```

---

## Pearl Causal Hierarchy — Implementation

### Layer 1: Association (Observational)
Standard forward propagation through the DAG in topological order.
Gives `P(Y | X = x)`.

### Layer 2: Intervention (do-Calculus)
**Graph surgery**: remove all edges *into* the intervened node, fix its value.
Implemented via `CausalEngine.intervene(var_id, value)`.
Gives `P(Y | do(X = x))`.

```gdscript
CausalEngine.intervene("atk_cap", 0.95)        # Simulate nation-state adversary
CausalEngine.intervene("def_budget", 0.40)      # Budget-constrained defender
CausalEngine.lift_intervention("atk_cap")       # Remove intervention
CausalEngine.lift_all_interventions()            # Reset to observational mode
```

### Layer 3: Counterfactual
Three-step algorithm:
1. **Abduction** — infer noise residuals U_i from observed evidence
2. **Action**    — apply intervention to twin world
3. **Prediction** — propagate twin world with abduced noise

```gdscript
var cf := CausalEngine.counterfactual(
    "defender_payoff",               # target variable
    {"honeypot_density": 0.45},      # hypothetical intervention
    {"honeypot_density": 0.20}       # observed evidence
)
# Returns: P(defender_payoff_{hp=0.45} | hp_observed = 0.20)
```

### Average Treatment Effect (ATE)
```gdscript
var ate := CausalEngine.compute_ate("def_budget", "defender_payoff", 200)
# Returns E[defender_payoff|do(budget=1)] - E[defender_payoff|do(budget=0)]
```

---

## Controls

| Input                        | Action                                         |
|------------------------------|------------------------------------------------|
| Middle-mouse drag            | Orbit camera                                   |
| Scroll wheel                 | Zoom                                           |
| Left-click node              | Select + highlight causal neighborhood         |
| Right-click node             | Open intervention slider                       |
| `Space`                      | Pause / resume simulation                      |
| `R`                          | Reset all interventions                        |
| `Escape`                     | Deselect                                       |
| `F1`                         | Focus: Attacker Success                        |
| `F2`                         | Focus: Defender Payoff                         |
| `F3`                         | Focus: Stackelberg Gain                        |
| `1`                          | Scenario: Nation-State APT (atk_cap=0.95)      |
| `2`                          | Scenario: Zero-Day Campaign (budget=0.40)      |
| `3`                          | Scenario: Stackelberg Defender (budget=0.95)   |
| `4`                          | Scenario: Ransomware (broad exposure)          |

---

## HUD Panels

```
┌─────────────────────────────────────────────────────────────────────┐
│ THREAT STATUS        │   ALERT TICKER (center top)    │  GT ENGINE │
│  threat_level  ████░ │  [ Intervention: do(X=0.95) ]  │  Nash EQ  │
│  atk_cap       ████░ │                                │  SSE      │
│  detection     ███░░ │                                │  Δ Gain   │
│  honeypot      ██░░░ │                                │  Strategy │
│  atk_success   ██░░░ │                                │  Bars     │
│  def_payoff    ████░ │                                │  Rec →    │
├─────────────────────────────────────────────────────────────────────┤
│ VARIABLE DETAIL (on select)     │  TEMPORAL TRACE (sparklines)     │
│  Label / Description            │  ████ threat_level               │
│  VALUE  │ KIND  │ PARENTS       │  ████ detection_rate             │
│  CHILDREN │ ATE │ [CF Button]   │  ████ attacker_success           │
│                                 │  ████ defender_payoff            │
│         INTERVENTION CONSOLE (right-click)                         │
│  do(honeypot_density = x)  [slider] [APPLY] [LIFT] [COUNTERFACT]  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Setup Instructions

### Requirements
- **Godot 4.3+** (Forward+ renderer recommended for glow/SSAO)
- No external plugins required

### Steps
```bash
# 1. Open Godot 4 and import this folder as a project
#    File → Import Project → select causal_world_model/project.godot

# 2. (Optional) Create CausalNode.tscn and CausalEdge.tscn prefabs
#    for full shader support — or let the code use fallback geometry

# 3. Press F5 or click Run to launch
```

### Creating CausalNode.tscn (optional prefab)
```
Node3D  (script: CausalNode3D.gd)
├── SphereMesh    (MeshInstance3D, shader: causal_node.gdshader)
├── RingMesh      (MeshInstance3D, thin torus)
├── InterventionRing (MeshInstance3D, thin torus, hidden)
├── Label3D       (billboard, variable name)
├── ValueLabel    (billboard, live value)
├── InfluenceParticles (GPUParticles3D)
├── InteractionArea (Area3D + SphereShape3D r=0.4)
└── AnimationPlayer
```

---

## Extension Points

### Adding a New Causal Variable
```gdscript
# In CausalEngine.gd → _build_cyber_defense_scm()
_add_var("patch_cadence", "Patch Cadence", VarKind.EXOGENOUS, VarDomain.CONTINUOUS,
    Vector3(2.0, 3.0, 1.0), Color(0.4, 1.0, 0.6),
    "How frequently systems are patched — reduces net_exposure",
    func(_p, u): return clampf(0.6 + u, 0.0, 1.0))

_add_edge("patch_cadence", "net_exposure", 0.70, -1)  # patches reduce exposure
```

### Adding a New Defender Action
```gdscript
# In GameTheoryEngine.gd
defender_actions.append("Zero-Trust Segmentation")
# Then extend _compute_payoff() with matching di cases
```

### Querying the Model from Any Script
```gdscript
# Observational query
var p_breach := CausalEngine.get_var("attacker_success").value

# Interventional query
CausalEngine.intervene("def_budget", 0.90)
var p_breach_highbudget := CausalEngine.get_var("attacker_success").value
CausalEngine.lift_intervention("def_budget")

# d-Separation check
var indep := CausalEngine.d_separated("atk_cap", "defender_payoff", ["threat_level"])
# → false (they remain dependent even conditioned on threat_level, via honeypot path)

# ATE
var ate := CausalEngine.compute_ate("honeypot_density", "attacker_success", 500)
# → approximately -0.35 (more honeypots → lower attacker success)

# SSE recommendation
print(GameTheoryEngine.get_action_recommendation())
# → "SSE → Deploy Honeypots (p=0.62) | Δ_SE = +0.214"
```

---

## Theoretical Foundations

| Component              | Reference                                                     |
|------------------------|---------------------------------------------------------------|
| Structural Causal Model| Pearl, J. (2000). *Causality*. Cambridge University Press     |
| do-Calculus            | Pearl, J. (1995). Causal diagrams for empirical research      |
| Counterfactual         | Pearl & Mackenzie (2018). *The Book of Why*                   |
| Stackelberg Security   | Paruchuri et al. (2008). Playing games for security: ARMOR    |
| PROTECT / TRUSTS       | Pita et al. (2009). Deployed ARMOR protection. AAMAS          |
| Double Oracle          | McMahan et al. (2003). Planning in the presence of cost functions |
| Mult. Weights Update   | Arora et al. (2012). The multiplicative weights update method |
| CyberBattleSim         | Microsoft Research (2021). github.com/microsoft/CyberBattleSim|
| Honeypot Game Theory   | Schlenker et al. (2018). Deceiving cyber adversaries. AAMAS   |
| APT Kill Chain Games   | Hu et al. (2020). Optimal network defense with game theory    |

---

## License
MIT — research and demonstration use.
For DARPA program integration, contact the authoring organization.
