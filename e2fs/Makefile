.PHONY: all clean install

# Versions
E2FSPROGS_VER  := 1.47.2
LIBARCHIVE_VER := 3.8.1
XZ_VER         := 5.4.5
ZSTD_VER       := 1.5.5

JOBS := $(shell sysctl -n hw.ncpu 2>/dev/null || echo 4)
ROOT := $(CURDIR)

all: install/bin/mke2fs-hy

# Build dependencies
build/deps/.done:
	@echo "===> Building dependencies"
	@mkdir -p build/deps
	
	# Extract and build zstd
	cd build && tar -xf ../sources/zstd-$(ZSTD_VER).tar.gz
	cd build/zstd-$(ZSTD_VER) && make -j$(JOBS) lib-nomt
	
	# Extract and build xz/liblzma
	cd build && tar -xf ../sources/xz-$(XZ_VER).tar.xz
	cd build/xz-$(XZ_VER) && ./configure --disable-shared --enable-static --disable-xz --disable-xzdec && make -j$(JOBS)
	
	# Extract and build libarchive
	cd build && tar -xf ../sources/libarchive-$(LIBARCHIVE_VER).tar.xz
	cd build/libarchive-$(LIBARCHIVE_VER) && \
		ac_cv_sizeof_wchar_t=4 \
		CPPFLAGS="-I../zstd-$(ZSTD_VER)/lib -I../xz-$(XZ_VER)/src/liblzma/api" \
		LDFLAGS="-L../zstd-$(ZSTD_VER)/lib -L../xz-$(XZ_VER)/src/liblzma/.libs" \
		./configure --disable-shared --enable-static --with-zstd --with-lzma \
		          --disable-bsdtar --disable-bsdcpio --disable-bsdcat --disable-bsdunzip && \
		make -j$(JOBS)
	
	@touch $@

# Build e2fsprogs
build/e2fsprogs-$(E2FSPROGS_VER)/misc/mke2fs: build/deps/.done
	@echo "===> Building e2fsprogs $(E2FSPROGS_VER)"
	cd build && tar -xf ../sources/e2fsprogs-$(E2FSPROGS_VER).tar.gz
	cd build/e2fsprogs-$(E2FSPROGS_VER) && \
		CC="gcc" \
		CPPFLAGS="-I$(ROOT)/build/libarchive-$(LIBARCHIVE_VER)/libarchive -I../zstd-$(ZSTD_VER)/lib -I../xz-$(XZ_VER)/src/liblzma/api -DHAVE_ARCHIVE_H" \
		LDFLAGS="-L../libarchive-$(LIBARCHIVE_VER)/.libs -L../zstd-$(ZSTD_VER)/lib -L../xz-$(XZ_VER)/src/liblzma/.libs" \
		LIBS="$(ROOT)/build/libarchive-$(LIBARCHIVE_VER)/.libs/libarchive.a $(ROOT)/build/zstd-$(ZSTD_VER)/lib/libzstd.a $(ROOT)/build/xz-$(XZ_VER)/src/liblzma/.libs/liblzma.a -lbz2 -lz -liconv -lxml2 -lpthread" \
		./configure --build=$(shell gcc -dumpmachine) --with-libarchive=direct && \
		make -j$(JOBS)

# Install binaries
install/bin/mke2fs-hy: build/e2fsprogs-$(E2FSPROGS_VER)/misc/mke2fs
	@echo "===> Installing binaries"
	@mkdir -p install/bin
	cp build/e2fsprogs-$(E2FSPROGS_VER)/misc/mke2fs install/bin/mke2fs-hy
	cp build/e2fsprogs-$(E2FSPROGS_VER)/resize/resize2fs install/bin/resize2fs-hy
	cp build/e2fsprogs-$(E2FSPROGS_VER)/e2fsck/e2fsck install/bin/e2fsck-hy
	cp build/e2fsprogs-$(E2FSPROGS_VER)/debugfs/debugfs install/bin/debugfs-hy
	strip -x install/bin/*

clean:
	rm -rf build install 