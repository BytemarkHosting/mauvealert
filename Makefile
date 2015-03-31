#
# Makefile for mauve -- mostly for generating manpages
#
##

OPENBSD_SETUP_FLAGS = --prefix=/usr/local --installdirs=site --ruby-path=/usr/local/bin/ruby18 --mandir=\$$prefix/man/man1 --siteruby=\$$libdir/ruby/site_ruby --siterubyver=\$$siteruby/1.8

all: man man/mauvesend.1 man/mauveserver.1 man/mauveconsole.1

man:
	mkdir -p man

man/%.1: bin/%
	ruby -I lib $< --manual | txt2man -t $(notdir $<) -s 1  > $@

clean:
	$(RM) -r man
	$(RM) -r tmp
	
# NOP task to keep au happy
release:
	true

distclean: clean

test:
	ruby -Ilib:test:. test/test_mauve.rb

.PHONY: all clean test distclean release

