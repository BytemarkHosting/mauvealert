#
# Makefile for mauve -- mostly for generating manpages
#
##

OPENBSD_SETUP_FLAGS = --prefix=/usr/local --installdirs=site --ruby-path=/usr/local/bin/ruby18 --mandir=\$$prefix/man/man1 --siteruby=\$$libdir/ruby/site_ruby --siterubyver=\$$siteruby/1.8

all: man man/mauvesend.1 man/mauveserver.1 man/mauveconsole.1

man:
	mkdir -p man

man/%.1: bin/%
	bundle exec $< --manual | txt2man -t $(notdir $<) -s 1  > $@
	test -s $@

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
	$(RM) -r OpenBSD
	$(RM) setup.rb
	

distclean: clean
	if [ -e ./setup.rb ] ; then ruby ./setup.rb distclean ; fi
	$(RM) setup.rb
	$(RM) -r OpenBSD

test: setup.rb
	ruby ./setup.rb test

setup.rb: /usr/lib/ruby/1.8/setup.rb
	ln -sf /usr/lib/ruby/1.8/setup.rb .

OpenBSD: OpenBSD/sha256.asc

OpenBSD/sha256: OpenBSD/ruby-mauvealert.tar.gz OpenBSD/ruby-protobuf.tar.gz
	#
	# rejig sha256sum to openbsd sha256
	# 
	$(RM) OpenBSD/sha256
	cd OpenBSD && sha256sum * | sed -e 's/\([^ ]\+\)  \(.*\)$$/SHA256 (\2) = \1/' > sha256

OpenBSD/sha256.asc: OpenBSD/sha256
	#
	# Sign it.
	#
	gpg --clearsign OpenBSD/sha256

OpenBSD/ruby-mauvealert.tar.gz: all setup.rb
	mkdir -p tmp/ruby-mauvealert
	ruby ./setup.rb config ${OPENBSD_SETUP_FLAGS}
	ruby ./setup.rb setup
	ruby ./setup.rb install --prefix=tmp/ruby-mauvealert
	mkdir -p OpenBSD
	tar -C tmp/ruby-mauvealert -czvf $@ .

OpenBSD/ruby-protobuf.tar.gz:
	mkdir -p tmp/ruby-protobuf-source
	git clone https://github.com/macks/ruby-protobuf.git tmp/ruby-protobuf-source
	cd tmp/ruby-protobuf-source && git checkout -b v0.4.5
	ln -sf /usr/lib/ruby/1.8/setup.rb tmp/ruby-protobuf-source/
	cd tmp/ruby-protobuf-source && ruby ./setup.rb config ${OPENBSD_SETUP_FLAGS} 
	cd tmp/ruby-protobuf-source && ruby ./setup.rb setup
	cd tmp/ruby-protobuf-source && ruby ./setup.rb install --prefix=../ruby-protobuf
	mkdir -p OpenBSD
	tar -C tmp/ruby-protobuf -czvf $@ .

.PHONY: all clean openbsd_tarball test distclean OpenBSD

