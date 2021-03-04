# Using sourmash with text

This is an experiment about using [sourmash] for working with natural
language (instead of genomic _k_-mers). The goal is to use books for explaining
how MinHash works, and make analogies to why we use _k_-mers for genomic data.

[sourmash]: http://sourmash.bio

## Example 1: The Dispossessed

Plotting the similarity between chapters in [The Dispossessed](http://self.gutenberg.org/articles/The_Dispossessed),
by Ursula K. Le Guin.

I wanted to check this because the book alternates between two different places
(Anarres and Urras) and timeframes (past and present), so do they also cluster
together (even and odd chapters numbers)?

First try, using only the presence of words:
![](https://github.com/luizirber/2021-02-26-text-minhash/raw/gh-pages/dispossessed/full/n1-s1-a0.matrix.png)

Second try, considering the abundance (how many times each word appears):
![](https://github.com/luizirber/2021-02-26-text-minhash/raw/gh-pages/dispossessed/full/n1-s1-a1.matrix.png)

Third try: find the intersection (the words present in all chapters) and remove it.
This removes the common background in all chapters, and maximizes the difference
between them. This plot is also using the abundance.
![](https://github.com/luizirber/2021-02-26-text-minhash/raw/gh-pages/dispossessed/sub/n1-s1-a1.matrix.png)

It is interesting to notice that chapter 1 and 13 are "space travel" chapters,
not totally in one or the other planet,
and the odd/even chapters do group together.

## Example 2: Similarity and Containment

This example aims to show the difference between Similarity and Containment,
and when you might prefer one to the other.
For that, we use the Torah and the Bible as examples.

The Torah is a composed of five books,
which are also the first five books in the Bible.
But, since they have different sizes (the Bible being much larger),
the Similarity score is low (`0.34`) because similarity takes into account the
union of elements from both datasets (the denominator in this equation):
<img src="https://render.githubusercontent.com/render/math?math=J(A, B) = \frac{|A \cap B|}{|A \cup B|}">

The Containment score takes into account the size of each dataset (in the denominator),
and so it is an asymmetrical score.
<img src="https://render.githubusercontent.com/render/math?math=C(A, B) = \frac{|A \cap B|}{|A|}">
Because of this,
Containment of the Torah in the Bible is high (`C(T, B) = 0.91`)
while the Containment of the Bible in the Torah is small (`C(B, T) = 0.35`).

## Code organization

There are two pieces in this repo:
- [`ansible`](./ansible), a very minimal CLI written in Rust for transforming a text file
  into a sourmash signature and performing intersection and subtraction of
  signatures.
- A [Snakemake pipeline](./Snakefile) for downloading data, building signature with
  `ansible`,  and running sourmash `compare` and `plot` commands to generate
  pretty pictures.

## Setup

This projects depends on Snakemake, sourmash, pandoc, wget and a Rust compiler.
If you don't want to download and install them yourself, you can use Nix
to manage it for you:
- Clone the repo.
- [Install nix](https://nixos.org/guides/install-nix.html).
- run `nix-shell` in the repo directory to open a shell with all deps installed.
- run `snakemake -j1` to process the pipeline and generate figures
