---
title: Scala Based FPGA Design Flow (Abstract Only)
authors: Yanqiang Liu, Yao Li, Weilun Xiong, Meng Lai, Cheng Chen, Zhengwei Qi, Haibing Guan
venue: The 2017 ACM/SIGDA International Symposium on Field-Programmable Gate Arrays, FPGA 2017
link: "https://doi.org/10.1145/3020078.3021762"
---

With the rapid growth of data scale, data analysis applications start to meet
the performance bottleneck, and thus requiring the aid of hardware
acceleration. At the same time, Field Programmable Gate Arrays (FPGAs), known
for their high customizability and parallel nature, have gained momentum in the
past decade. However, the efficiency of development for acceleration system
based on FPGAs is severely constrained by the traditional languages and tools,
due to their deficiency in expressibility, extendability, limited libraries and
semantic gap between software and hardware design. This paper proposes a new
open-source DSL based hardware design framework called VeriScala
(https://github.com/VeriScala/VeriScala) that supports highly abstracted
object-oriented hardware defining, programmatical testing, and interactive
on-chip debugging. By adopting DSL embedded in Scala, we introduce modern
software developing concepts into hardware designing including object-oriented
programming, parameterized types, type safety, test automation, etc. VeriScala
enables designers to describe their hardware designs in Scala, generate Verilog
code automatically and interactively debug and test hardware design in real FPGA
environment. Through the evaluation on real world applications and usability
test, we show that VeriScala provides a practical approach for rapid prototyping
of hardware acceleration systems. (This work is supported by the National Key
Research & Development Program of China 2016YFB1000500)
