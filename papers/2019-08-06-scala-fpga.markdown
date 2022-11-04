---
title: A Scala based Framework for Developing Acceleration Systems with FPGAs
authors: Yanqiang Liu, Yao Li, Zhengwei Qi, Haibing Guan
venue: Journal of Systems Architecture, 98, 2019
link: "https://doi.org/10.1016/j.sysarc.2019.08.001"
---

Field-Programmable Gate Arrays (FPGAs) in heterogeneous computing have been
attracting more and more attention. Development of acceleration systems based on
FPGAs involves the cooperation of both hardware and software
developers. However, although most hardware acceleration systems are motivated
by software developers, software developers are difficult to participant in the
system building because of the steep learning curve of the hardware concept and
design tools. Moreover, due to the complexity of hardware-software integration
in traditional ways, end-to-end performance is hard to evaluate before trivial
engineering effort. To address these concerns, we propose an open-source
Domain-Specific Language (DSL) based framework called VeriScala1 to support
hardware defining in a high-level language, programmatical testing, and rapid
acceleration system deploying. By adopting DSL embedded in Scala language, we
introduce modern software development concepts into hardware design and provide
a familiar environment to software developers. And by building a stack of middle
layers from hardware to software, we provide reduced hardware abstraction and
communication interface to facilitate both software and hardware development and
system deployment. Through the evaluation of some basic components and
real-world demos, we show that VeriScala provides a practical approach to rapid
prototyping of hardware acceleration systems.
