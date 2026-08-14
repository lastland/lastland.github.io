---
title: Displaying Proof Goals with Alectryon
date: 2026-08-13
description: A draft post showing Rocq proof states rendered inline by Alectryon.
alectryon: []
alectryon-cache: "alectryon-cache/demo"
---

This post exercises the Alectryon integration: every `coq` and `rocq` fence
below is executed by Coq, and the proof state after each sentence is recorded.
Not every sentence produces a state (the closing `Qed.`, for instance, produces
none), so only the steps that do are marked with a trailing dot. Hover a marked
step, or tap it, to reveal the goals it produces.

## A trivial proof

```coq
Goal True /\ True.
  split.
  - exact I.
  - exact I.
Qed.
```

## The same proof written with a rocq fence

The `rocq` fence is normalized to `alectryon` just like the `coq` fence, so it
is executed in the same session.

```rocq
Goal 1 + 1 = 2.
Proof. reflexivity. Qed.
```

Both blocks share one Coq session, in source order.
