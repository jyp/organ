all: Organ-HaskeLL.pdf

%.tool: %.hs
	ghc --make $*
	mv -f $* $@

PaperTools/bibtex/jp.short.bib: PaperTools/bibtex/jp.short.bib
	make -C PaperTools/bibtex

clean:
	rm -f *.aux *.pdf *.log *.blg *.bbl

%.sp.lhs: %.lhs Spekify.tool
	./Spekify.tool <$< >$@

%.md.lhs: %.sp.lhs template.tex
	pandoc --template=template.tex -s -f markdown+lhs -t latex+lhs --tab-stop=2 $< -o $@

%.tex: %.md.lhs CleanTex.tool
	lhs2TeX < $*.md.lhs | ./CleanTex.tool >$@

%.pdf: %.tex PaperTools/bibtex/jp.short.bib
	pdflatex $*
	bibtex $*
	pdflatex $*

gist:
	cp Organ.lhs ../fadd6e8a2a0aa98ae94d
	(cd ../fadd6e8a2a0aa98ae94d && git pull && git commit -a -m "sync" && git push)

Talk.tex: Talk.md Makefile
	pandoc --template=talktemplate.tex --highlight-style=tango -s -f markdown+yaml_metadata_block -t beamer --tab-stop=2 $< -o $@

Talk.pdf: Talk.tex
	pdflatex Talk.tex

TalkEdinburgh.tex: TalkEdinburgh.md Makefile
	pandoc --template=talktemplate.tex --highlight-style=tango -s -f markdown+yaml_metadata_block -t beamer --tab-stop=2 $< -o $@

TalkEdinburgh.pdf: TalkEdinburgh.tex
	pdflatex TalkEdinburgh.tex

TalkDundee.tex: TalkDundee.md Makefile
	pandoc --template=talktemplate.tex --highlight-style=tango -s -f markdown+yaml_metadata_block -t beamer --tab-stop=2 $< -o $@

TalkDundee.pdf: TalkDundee.tex
	pdflatex TalkDundee.tex
