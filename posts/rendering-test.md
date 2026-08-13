---
title: Rendering Test
date: 2026-08-12
description: A draft post that exercises every rendering feature of the blog.
draft: true
---

This is a draft post that exercises every rendering feature of the blog. It is not a real post; it exists so a rebuild can confirm the pipeline still works.

## Math

Inline math like $e^{i\pi} + 1 = 0$ renders as a KaTeX span, and so does display math:

$$\sum_{i=0}^{n} i = \frac{n(n+1)}{2}$$ {#eq:gauss}

The identity in @eq:gauss is the one Gauss is said to have found in school.

## Figures and tables

@Fig:diagram sketches the shape of this site's rendering pipeline.

![A small commuting diagram](/images/posts/rendering-test/diagram.svg){#fig:diagram}

@Tbl:features lists what this post covers.

| Feature | Where        | Checked |
|---------|--------------|---------|
| Math    | Above        | yes     |
| Figures | This section | yes     |
| Code    | Next section | yes     |

: Rendering features covered by this post. {#tbl:features}

## Code

A Haskell block with a type signature:

```haskell
-- | Sum the integers from 1 to n.
sumTo :: Integer -> Integer
sumTo n = n * (n + 1) `div` 2

main :: IO ()
main = print (sumTo 100)
```

A Coq block:

```coq
Theorem sum_zero : 0 + 0 = 0.
Proof.
  intros.
  reflexivity.
Qed.
```

And the same style written with a rocq fence, which the pipeline normalizes to coq:

```rocq
Theorem one_plus_one : 1 + 1 = 2.
Proof. reflexivity. Qed.
```

## Footnotes, quotes, and links

Footnotes render at the bottom of the post.[^1]

[^1]: This is the footnote body.

> A blockquote, set off by a terracotta rule.

The word **bold** renders as a `<b>` element on this site, and this link jumps back to the [Math](#math) heading.
