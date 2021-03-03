from pathlib import Path

rule all:
  input: expand("data/plots/n{nsize}-s{scaled}-a{abundance}.matrix.png", nsize=[1], scaled=[1], abundance=[0, 1])

rule download:
  output: "data/book.epub"
  shell: """
    wget -c https://libcom.org/files/The%20Dispossessed%20-%20Ursula%20K.%20Le%20Guin_0.epub -O {output}
  """

rule extract_chapters:
  output: expand("data/OEBPS/Chapter{number}.xhtml", number=range(1, 14))
  input: "data/book.epub"
  shell: """
    cd data && unzip book.epub 'OEBPS/Chapter*.xhtml'
  """

rule convert_chapter:
  output: "data/txt/chp{num}.txt"
  input: "data/OEBPS/Chapter{num}.xhtml"
  shell: """
    pandoc -t plain {input} -o {output}
  """

rule sketch:
  output: "data/sketches/chp{num}-n{nsize}-s{scaled}.sig"
  input:
    sig="data/txt/chp{num}.txt",
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

rule compile:
  output: "ansible/target/release/ansible"
  input:
    "ansible/src/main.rs",
    "ansible/Cargo.lock",
    "ansible/Cargo.toml"
  shell: """
    cd ansible && cargo build --release
  """

rule compare:
  output: "data/matrices/n{nsize}-s{scaled}-a{abundance}"
  input:  expand("data/sketches/chp{num}-n{{nsize}}-s{{scaled}}.sig", num=range(1, 14))
  params:
      abundance = lambda w: "--ignore-abundance" if w.abundance == "0" else ""
  shell: """
    sourmash compare {params.abundance} {input} -o {output}
  """

rule plot:
  output: "data/plots/n{nsize}-s{scaled}-a{abundance}.matrix.png"
  input: "data/matrices/n{nsize}-s{scaled}-a{abundance}"
  params:
    outdir = lambda wildcards, output: Path(output[0]).parent,
  shell: """
    sourmash plot {input} \
      --output-dir {params.outdir} \
      --labels
  """
