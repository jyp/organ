all: Organ.pdf

%.md.lhs: %.lhs
	pandoc --variable mainfont="DejaVu Serif" --variable header-includes="%include local.fmt" -s -f markdown+lhs -t latex+lhs $< -o $@

%.tex: %.md.lhs local.fmt
	lhs2TeX < $< >$@

%.pdf: %.tex
	pdflatex $*
