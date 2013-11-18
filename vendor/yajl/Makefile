.PHONY: all clean distclean install package test distro
all: distro doc test

distro:
	@cd build && make

doc:
	@cd build && make doc

test:
	@cd build && make test

clean:
	@cd build && make clean

distclean:
	@rm -rf Makefile build
	@rm -f yajl-*.tgz

install: all
	@cd build && make install

package: all
	@echo "compressing to `basename build/yajl-*`.tgz"
	@cd build && tar czf ../`basename yajl-*`.tgz yajl-*
