---
title: Embracing a Mechanized Formalization Gap
authors: Antal Spector-Zabusky, Joachim Breitner, Yao Li, Stephanie Weirich
preprint: "https://arxiv.org/pdf/1910.11724.pdf"
talk: "https://youtu.be/1NA6yV3cxNY"
draft: true
---

If a code base is so big and complicated that complete mechanical verification
is intractable, can we still apply and benefit from verification methods? We
show that by allowing a deliberate mechanized formalization gap we can shrink
and simplify the model until it is manageable, while still retaining a
meaningful, declaratively documented connection to the original, unmodified
source code. Concretely, we translate core parts of the Haskell compiler GHC
into Coq, using hs-to-coq, and verify invariants related to the use of term
variables.
