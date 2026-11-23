CC = clang

CHOMA_DYLIB_PATH ?= 0
CHOMA_PATH       ?= external/ChOma
CFLAGS            = -O2 -framework Foundation -I$(CHOMA_PATH)/include
CFLAGS_MACOS      = $(CFLAGS)
CFLAGS_IOS        = $(CFLAGS) -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -miphoneos-version-min=15.0 -arch arm64 -arch arm64e
LDFLAGS           = -lcompression

# musnm/ios-ipa-builder has no ldid; bootstrap on first use.
define ENSURE_LDID
	@if ! command -v ldid >/dev/null 2>&1; then \
	  echo "[XPF] ldid missing, bootstrapping..."; \
	  ARCH=$$(uname -m); \
	  case "$$ARCH" in \
	    arm64) URL=https://github.com/ProcursusTeam/ldid/releases/download/v2.1.5-procursus7/ldid_macosx_arm64 ;; \
	    *)     URL=https://github.com/ProcursusTeam/ldid/releases/download/v2.1.5-procursus7/ldid_macosx_x86_64 ;; \
	  esac; \
	  curl -fsSL -o /tmp/ldid "$$URL" && chmod +x /tmp/ldid && \
	  (sudo mv /tmp/ldid /usr/local/bin/ldid 2>/dev/null || mv /tmp/ldid "$$(pwd)/ldid"); \
	  command -v ldid >/dev/null 2>&1 || test -x ./ldid; \
	fi
endef

all: output/macos/libxpf.dylib output/ios/libxpf.dylib output/macos/xpf_test output/ios/xpf_test

ifneq ($(CHOMA_DYLIB_PATH), 0)
CHOMA_DEP = 
LDFLAGS  += -L$(CHOMA_DYLIB_PATH) -lchoma
else
CHOMA_DEP = $(CHOMA_PATH)/src/*.c
endif 

output/macos/libxpf.dylib: $(wildcard src/*.c) $(CHOMA_DEP)
	@mkdir -p $(shell dirname $@)
	$(CC) $(CFLAGS_MACOS) $(LDFLAGS) -dynamiclib -install_name @loader_path/libxpf.dylib -o $@ $^

output/ios/libxpf.dylib: $(wildcard src/*.c) $(CHOMA_DEP)
	@mkdir -p $(shell dirname $@)
	$(CC) $(CFLAGS_IOS) $(LDFLAGS) -dynamiclib -install_name @loader_path/libxpf.dylib -o $@ $^
	$(ENSURE_LDID)
	@if command -v ldid >/dev/null 2>&1; then ldid -S $@; else ./ldid -S $@; fi

output/macos/xpf_test: $(wildcard src/cli/*.c)
	@mkdir -p $(shell dirname $@)
	$(CC) $(CFLAGS_MACOS) $(LDFLAGS) -L$(shell dirname $@) -lxpf -o $@ $^

output/ios/xpf_test: $(wildcard src/cli/*.c)
	@mkdir -p $(shell dirname $@)
	$(CC) $(CFLAGS_IOS) $(LDFLAGS) -L$(shell dirname $@) -lxpf -o $@ $^
	$(ENSURE_LDID)
	@if command -v ldid >/dev/null 2>&1; then ldid -S $@; else ./ldid -S $@; fi

clean:
	@rm -rf output
