---
title: "From C to Interaction Trees: Specifying, Verifying, and Testing a Networked Server"
authors: Nicolas Koh, Yao Li, Yishuai Li, Li-yao Xia, Lennart Beringer, Wolf Honoré, William Mansky, Benjamin C. Pierce, Steve Zdancewic
venue: The 8th ACM SIGPLAN International Conference on Certified Programs and Proofs, CPP 2019
link: "https://doi.org/10.1145/3293880.3294106"
preprint: "https://arxiv.org/pdf/1811.11911.pdf"
featured: true
openaccess: true
---

We present the first formal verification of a networked server implemented in
C. Interaction trees, a general structure for representing reactive
computations, are used to tie together disparate verification and testing tools
(Coq, VST, and QuickChick) and to axiomatize the behavior of the operating
system on which the server runs (CertiKOS). The main theorem connects a
specification of acceptable server behaviors, written in a straightforward “one
client at a time” style, with the CompCert semantics of the C program. The
variability introduced by low-level buffering of messages and interleaving of
multiple TCP connections is captured using network refinement, a variant of
observational refinement.
