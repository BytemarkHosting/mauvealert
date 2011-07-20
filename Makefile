#
# Makefile for mauve -- mostly for generating manpages
#
##

all: man man/mauvesend.1 man/mauveserver.1 man/mauveconsole.1

man:
	mkdir -p man

man/%.1: bin/%
	ruby -I lib $< --manual | txt2man -t $(notdir $<) -s 1  > $@

clean:
	$(RM) -r man

.PHONY: all clean

