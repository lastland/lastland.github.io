---
title: Ready, Set, Verify! Applying hs-to-coq to real-world Haskell code (Experience Report)
authors: Joachim Breitner, Antal Spector-Zabusky, Yao Li, Christine Rizkallah, John Wiegley, Stephanie Weirich
link: "https://doi.org/10.1145/3236784"
preprint: "https://arxiv.org/pdf/1803.06960.pdf"
openaccess: true
artifact: "https://doi.org/10.1145/3235036"
talk: "https://www.youtube.com/watch?v=9QL97E0cNk0"
venue: Proceedings of the ACM on Programming Languages, 2(ICFP), 2018
---

Good tools can bring mechanical verification to programs written in mainstream
functional languages. We use hs-to-coq to translate significant portions of
Haskell's containers library into Coq, and verify it against specifications that
we derive from a variety of sources including type class laws, the library's
test suite, and interfaces from Coq's standard library. Our work shows that it
is feasible to verify mature, widely-used, highly optimized, and unmodified
Haskell code. We also learn more about the theory of weight-balanced trees,
extend hs-to-coq to handle partiality, and -- since we found no bugs -- attest
to the superb quality of well-tested functional code.
