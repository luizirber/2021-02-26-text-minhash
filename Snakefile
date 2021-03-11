from pathlib import Path

rule all:
  input:
    expand("data/plots/{exp}/{subset}/n{nsize}-s{scaled}-a{abundance}.matrix.png",
             nsize=[1],
             scaled=[1],
             abundance=[0, 1],
             subset=["full", "sub"],
             exp=["dispossessed"]),
    "data/sacred-n1-s1.txt",
    "data/plots/sacred-n1-s1.png"

## Rules for preparing The Dispossessed

rule download:
  output: "data/books/dispossessed/book.epub"
  shell: """
    wget -c https://libcom.org/files/The%20Dispossessed%20-%20Ursula%20K.%20Le%20Guin_0.epub -O {output}
  """

rule extract_chapters:
  output: expand("data/books/dispossessed/OEBPS/Chapter{number}.xhtml", number=range(1, 14))
  input: "data/books/dispossessed/book.epub"
  shell: """
    cd data/books/dispossessed && unzip book.epub 'OEBPS/Chapter*.xhtml'
  """

rule convert_chapter:
  output: "data/txt/dispossessed/chp{num}.txt"
  input: "data/books/dispossessed/OEBPS/Chapter{num}.xhtml"
  shell: """
    pandoc -t plain {input} -o {output}
  """

rule sketch:
  output: "data/sketches/dispossessed/full/chp{num}-n{nsize}-s{scaled}.sig"
  input:
    sig="data/txt/dispossessed/chp{num}.txt",
    bin="ansible/target/release/ansible"
  params:
    nsize = "{nsize}",
    scaled = "{scaled}"
  shell: """
    {input.bin} sketch \
      -n {params.nsize} \
      --scaled {params.scaled} \
      -o {output} \
      {input.sig}
  """

## Compile ansible (the Rust program for sketching text)

rule compile:
  output: "ansible/target/release/ansible"
  input:
    "ansible/src/main.rs",
    "ansible/Cargo.lock",
    "ansible/Cargo.toml"
  shell: """
    cd ansible && cargo build --release
  """

## Compare, plot, intersect and subtract for dispossessed
## (similarity, many chapters)

rule compare:
  output: "data/matrices/dispossessed/{exp}/n{nsize}-s{scaled}-a{abundance}"
  input: expand("data/sketches/dispossessed/{{exp}}/chp{num}-n{{nsize}}-s{{scaled}}.sig", num=range(1, 14))
  params:
      abundance = lambda w: "--ignore-abundance" if w.abundance == "0" else ""
  shell: """
    sourmash compare {params.abundance} {input} -o {output}
  """

rule plot:
  output: "data/plots/dispossessed/{exp}/n{nsize}-s{scaled}-a{abundance}.matrix.png"
  input: "data/matrices/dispossessed/{exp}/n{nsize}-s{scaled}-a{abundance}"
  params:
    outdir = lambda wildcards, output: Path(output[0]).parent,
  shell: """
    sourmash plot {input} \
      --output-dir {params.outdir} \
      --labels
  """

rule intersect:
  output:
    intersection = "data/sketches/dispossessed/intersection-n{nsize}-s{scaled}.sig",
    siglist = temp("data/sketches/dispossessed/intersection-n{nsize}-s{scaled}-siglist")
  input:
    sigs=expand("data/sketches/dispossessed/full/chp{num}-n{{nsize}}-s{{scaled}}.sig", num=range(1, 14)),
    bin="ansible/target/release/ansible"
  params:
    nsize = "{nsize}",
    scaled = "{scaled}"
  run:
      # sourmash equivalent: sourmash sig intersect -o {output.intersection} {input.sigs}
      with open(output.siglist, 'w') as f:
          for sig in input.sigs:
              f.write(sig + '\n')

      shell("""
        {input.bin} intersect \
          -n {params.nsize} \
          --scaled {params.scaled} \
          -o {output.intersection} \
          {output.siglist}
      """)

rule subtract:
  output:
    subtracted = "data/sketches/dispossessed/sub/chp{num}-n{nsize}-s{scaled}.sig",
  input:
    intersection = "data/sketches/dispossessed/intersection-n{nsize}-s{scaled}.sig",
    sig="data/sketches/dispossessed/full/chp{num}-n{nsize}-s{scaled}.sig",
    bin="ansible/target/release/ansible"
  params:
    nsize = "{nsize}",
    scaled = "{scaled}"
  shell: """
    {input.bin} subtract \
      -n {params.nsize} \
      --scaled {params.scaled} \
      -o {output.subtracted} \
      {input.sig} {input.intersection}
  """
  # sourmash equivalent: sourmash sig subtract --flatten -o {output.subtracted} {input.sig} {input.intersection}

## Rules for preparing Bible and Torah

rule download_torah:
  output: "data/books/torah/book.epub"
  shell: """
    wget -c 'https://chaver.com/Torah-New/English/Text/The%20Structured%20Torah%20-%20Moshe%20Kline.epub' -O {output}
  """

rule download_bible:
  output: "data/txt/bible.txt"
  shell: """
    wget -c https://www.gutenberg.org/ebooks/10900.txt.utf-8 -O {output}
  """

rule extract_chapters_torah:
  output: expand("data/books/torah/index_split_{number:03d}.html", number=range(9, 100))
  input: "data/books/torah/book.epub"
  shell: """
    cd data/books/torah && unzip book.epub 'index_split_*'
  """

rule convert_torah:
  output: "data/txt/torah.txt"
  input: expand("data/books/torah/index_split_{num:03d}.html", num=range(9, 100))
  shell: """
    pandoc -t plain -o {output} {input}
  """

rule sketch_sacred:
  output: "data/sketches/{book}/{book}-n{nsize}-s{scaled}.sig"
  input:
    sig="data/txt/{book}.txt",
    bin="ansible/target/release/ansible"
  params:
    nsize = "{nsize}",
    scaled = "{scaled}"
  shell: """
    {input.bin} sketch \
      -n {params.nsize} \
      --scaled {params.scaled} \
      -o {output} \
      {input.sig}
  """

## For Bible/Torah we don't need plots, only similarity/containment with sourmash sig overlap
rule compare_sacred:
  output: "data/sacred-n{nsize}-s{scaled}.txt"
  input:
    expand("data/sketches/{book}/{book}-n{{nsize}}-s{{scaled}}.sig", book=["torah", "bible"])
  shell: """
    sourmash sig overlap \
      <(sourmash sig flatten -o - {input[0]}) \
      <(sourmash sig flatten -o - {input[1]}) > {output}
  """

rule plot_venn:
  output: "data/plots/sacred-n{nsize}-s{scaled}.png"
  input: "data/sacred-n{nsize}-s{scaled}.txt"
  run:
    from matplotlib_venn import venn2
    from ficus import FigureManager
    import numpy as np

    first = 0
    second = 0
    only_first = 0
    only_second = 0
    common = 0
    total = 0
    with open(input[0], 'r') as f:
        for line in f:
            line = line.strip()
            if line.startswith("number of hashes in first"):
                first = int(line.split(":")[-1])
            elif line.startswith("number of hashes in second"):
                second = int(line.split(":")[-1])
            elif line.startswith("only in first"):
                only_first = int(line.split(":")[-1])
            elif line.startswith("only in second"):
                only_second = int(line.split(":")[-1])
            elif line.startswith("number of hashes in common"):
                common = int(line.split(":")[-1])
            elif line.startswith("total"):
                total = int(line.split(":")[-1])

    with FigureManager(figsize=(4, 3), filename=output[0]) as (fig, ax):
       v = venn2(
         {
            "01": only_first,
            "10": only_second,
            "11": common
         },
         set_labels = ["", ""],
         ax=ax
       )

       ax.text(-.95, -0.05, "Bible", fontsize=16)
       ax.text(.6, -0.05, "Torah", fontsize=16)
       fig.tight_layout()
