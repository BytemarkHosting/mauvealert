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
	# Theoretically this will clean up the shebang munging done by the openbsd_tarball task below.
	if [ -e ./setup.rb ] ; then  \
		ruby ./setup.rb distclean ; \
		ruby ./setup.rb config    ; \
		ruby ./setup.rb setup     ; \
		ruby ./setup.rb clean ; \
	fi
	$(RM) -r tmp

distclean: clean
	[ -e ./setup.rb ] && ruby ./setup.rb distclean
	$(RM) setup.rb
	$(RM) ruby-mauvealert.tar.gz

test: setup.rb
	ruby ./setup.rb test

setup.rb: /usr/lib/ruby/1.8/setup.rb
	ln -sf /usr/lib/ruby/1.8/setup.rb .

openbsd_tarball: ruby-mauvealert.tar.gz

ruby-mauvealert.tar.gz: all setup.rb
	mkdir -p tmp
	ruby ./setup.rb config --prefix=/usr/local --installdirs=site --ruby-path=/usr/local/bin/ruby18 --mandir=\$$prefix/man/man1 --siteruby=\$$libdir/ruby/site_ruby --siterubyver=\$$siteruby/1.8
	ruby ./setup.rb setup
	ruby ./setup.rb install --prefix=tmp/
	tar -C tmp -czvf $@ .

.PHONY: all clean openbsd_tarball test distclean

