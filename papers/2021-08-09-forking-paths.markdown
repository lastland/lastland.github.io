---
title: Reasoning about the Garden of Forking Paths
authors: Yao Li, Li-yao Xia, Stephanie Weirich
venue: Proceedings of the ACM on Programming Languages, 5(ICFP), 2021
link: "https://doi.org/10.1145/3473585"
openaccess: true
preprint: "https://arxiv.org/pdf/2103.07543.pdf"
featured: true
artifact: "https://doi.org/10.5281/zenodo.4771438"
talk: "https://www.youtube.com/watch?v=YSVFUjUcWzo"
---

Lazy evaluation is a powerful tool for functional programmers. It enables the
concise expression of on-demand computation and a form of compositionality not
available under other evaluation strategies. However, the stateful nature of
lazy evaluation makes it hard to analyze a program's computational cost, either
informally or formally. In this work, we present a novel and simple framework
for formally reasoning about lazy computation costs based on a recent model of
lazy evaluation: clairvoyant call-by-value. The key feature of our framework is
its simplicity, as expressed by our definition of the clairvoyance monad. This
monad is both simple to define (around 20 lines of Coq) and simple to reason
about. We show that this monad can be effectively used to mechanically reason
about the computational cost of lazy functional programs written in Coq.
