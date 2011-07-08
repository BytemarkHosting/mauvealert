#
# Makefile for mauve -- mostly for generating manpages
#
##

all: man/mauveclient.1

man/%.1: bin/%
	mkdir -p man
	ruby -I lib $< --help | txt2man -t $(notdir $<) -s 1  > $@; \

clean:
	$(RM) -r man

.PHONY: all clean

