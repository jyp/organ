all: Organ.pdf

clean:
	rm -f *.aux *.pdf *.log *.blg *.bbl

%.md.lhs: %.lhs template.tex
	pandoc --template=template.tex -s -f markdown+lhs -t latex+lhs --tab-stop=2 $< -o $@

%.tex: %.md.lhs
	lhs2TeX < $< >$@

%.pdf: %.tex
	pdflatex $*
	bibtex $*
	pdflatex $*
