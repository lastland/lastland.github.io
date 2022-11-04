---
title: "Ready, Set, Verify! Applying hs-to-coq to real-world Haskell code"
authors: Joachim Breitner, Antal Spector-Zabusky, Yao Li, Christine Rizkallah, John Wiegley, Joshua Cohen, Stephanie Weirich
venue: Journal of Functional Programming, 31(e5), 2021
link: "https://doi.org/10.1017/S0956796820000283"
openaccess: true
featured: true
artifact: "https://doi.org/10.1145/3235036"
talk: "https://www.youtube.com/watch?v=9QL97E0cNk0"
---

Good tools can bring mechanical verification to programs written in mainstream
functional languages. We use hs-to-coq to translate significant portions of
Haskell’s containers library into Coq, and verify it against specifications that
we derive from a variety of sources including type class laws, the library’s
test suite, and interfaces from Coq’s standard library. Our work shows that it
is feasible to verify mature, widely used, highly optimized, and unmodified
Haskell code. We also learn more about the theory of weight-balanced trees,
extend hs-to-coq to handle partiality, and – since we found no bugs – attest to
the superb quality of well-tested functional code.
