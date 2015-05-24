all: Organ.pdf

%.tool: %.hs
	ghc --make $*
	mv -f $* $@

clean:
	rm -f *.aux *.pdf *.log *.blg *.bbl

%.sp.lhs: %.lhs Spekify.tool
	./Spekify.tool <$< >$@

%.md.lhs: %.sp.lhs template.tex
	pandoc --template=template.tex -s -f markdown+lhs -t latex+lhs --tab-stop=2 $< -o $@

%.tex: %.md.lhs CleanTex.tool
	lhs2TeX < $*.md.lhs | ./CleanTex.tool >$@

%.pdf: %.tex
	pdflatex $*
	bibtex $*
	pdflatex $*

gist:
	cp Organ.lhs ../fadd6e8a2a0aa98ae94d
	(cd ../fadd6e8a2a0aa98ae94d && git commit -a -m "sync" && git push)
