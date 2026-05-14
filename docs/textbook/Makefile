# Regenerate PDF and DOCX from the markdown sources.
#
# Usage:
#   make             # everything
#   make handbook    # just the handbook
#   make glossary    # just the glossary
#   make clean
#
# Requires: docker (uses pandoc/latex image, no local pandoc/latex install).

PANDOC := docker run --rm -v "$(PWD):/data" pandoc/latex:latest

HANDBOOK_SRC := platform-engineering-handbook.md
HANDBOOK_PDF := platform-engineering-handbook.pdf
HANDBOOK_DOCX := platform-engineering-handbook.docx

GLOSSARY_SRC := glossary-and-tips.md
GLOSSARY_PDF := glossary-and-tips.pdf
GLOSSARY_DOCX := glossary-and-tips.docx

PDF_OPTS := --pdf-engine=lualatex \
            --toc --toc-depth=3 \
            -V geometry:margin=1in \
            -V fontsize=11pt \
            -V documentclass=report \
            -V colorlinks=true

DOCX_OPTS := --toc --toc-depth=3

.PHONY: all handbook glossary fix-perms clean

all: handbook glossary fix-perms

handbook: $(HANDBOOK_PDF) $(HANDBOOK_DOCX)

glossary: $(GLOSSARY_PDF) $(GLOSSARY_DOCX)

$(HANDBOOK_PDF): $(HANDBOOK_SRC)
	$(PANDOC) -i $(HANDBOOK_SRC) -o $(HANDBOOK_PDF) $(PDF_OPTS)

$(HANDBOOK_DOCX): $(HANDBOOK_SRC)
	$(PANDOC) -i $(HANDBOOK_SRC) -o $(HANDBOOK_DOCX) $(DOCX_OPTS)

$(GLOSSARY_PDF): $(GLOSSARY_SRC)
	$(PANDOC) -i $(GLOSSARY_SRC) -o $(GLOSSARY_PDF) $(PDF_OPTS)

$(GLOSSARY_DOCX): $(GLOSSARY_SRC)
	$(PANDOC) -i $(GLOSSARY_SRC) -o $(GLOSSARY_DOCX) $(DOCX_OPTS)

fix-perms:
	@docker run --rm -v "$(PWD):/data" --entrypoint chown alpine:latest -R $$(id -u):$$(id -g) /data

clean:
	rm -f *.pdf *.docx
