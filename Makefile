all: Organ.pdf

CleanTex: CleanTex.hs
	ghc --make CleanTex

clean:
	rm -f *.aux *.pdf *.log *.blg *.bbl

%.md.lhs: %.lhs template.tex
	pandoc --template=template.tex -s -f markdown+lhs -t latex+lhs --tab-stop=2 $< -o $@

%.tex: %.md.lhs CleanTex
	lhs2TeX < $*.md.lhs | ./CleanTex >$@

%.pdf: %.tex
	pdflatex $*
	bibtex $*
	pdflatex $*

gist:
	cp Organ.lhs ../fadd6e8a2a0aa98ae94d
	(cd ../fadd6e8a2a0aa98ae94d && git commit -a -m "sync" && git push)
