all: Organ.pdf

%.md.lhs: %.lhs template.tex
	pandoc --template=template.tex -s -f markdown+lhs -t latex+lhs $< -o $@

%.tex: %.md.lhs
	lhs2TeX < $< >$@

%.pdf: %.tex
	pdflatex $*
	bibtex $*
	pdflatex $*
