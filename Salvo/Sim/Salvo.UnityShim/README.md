# UnityEngine shim

## What this is

Just enough of `UnityEngine` and `UnityEditor` to compile `Unity/Assets/Salvo/Runtime` and
`Unity/Assets/Salvo/Editor` on a machine with no Unity installed.

## What it proves, and what it does not

It **does** prove that the bridge code is internally consistent C#: no typos, no wrong
argument counts, no calls into `Salvo.Sim` members that do not exist. That last one is the
point. The simulation is the half that moves, and a rename there silently breaking the Unity
layer is the most likely way this project breaks between now and the first time anyone opens
it in the editor.

It **does not** prove the code matches real Unity. Every declaration here was written from
memory of Unity's API; where that memory is wrong, the shim is wrong in the same way and the
compile passes anyway. So a green build here means "the bridge is consistent with itself and
with the simulation", not "this will compile in Unity 6".

The first person to open the project in Unity should expect to fix something. That is
expected, not a fault — and it will be a smaller something than it would have been.

## Rules

- Only add what the bridge actually uses. A shim that grows to cover Unity is a liability:
  more surface to get wrong, and more false confidence.
- Never reference this project from `Salvo.Sim`. The simulation does not know Unity exists,
  and `Salvo.Sim.asmdef` sets `noEngineReferences: true` to keep it that way.
- Never ship it. It is referenced only by `Salvo.Bridge.Check`.
