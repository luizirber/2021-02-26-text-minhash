rule all:
    input: expand("data/chp{num}.txt", num=range(1, 14))

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
  output: "data/chp{num}.txt"
  input: "data/OEBPS/Chapter{num}.xhtml"
  shell: """
    pandoc -t plain {input} -o {output}
  """
