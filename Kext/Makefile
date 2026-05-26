NAME := DisableTurboBoost
KEXT := build/$(NAME).kext
BIN  := $(KEXT)/Contents/MacOS/$(NAME)
INFO := $(KEXT)/Contents/Info.plist

SDKROOT := $(shell xcrun --sdk macosx --show-sdk-path)
KERNELDIR := $(SDKROOT)/System/Library/Frameworks/Kernel.framework/Headers

CFLAGS := -arch x86_64 -mkernel -nostdlib -fno-builtin -fno-stack-protector \
          -static -Xlinker -kext -Xlinker -sectcreate -Xlinker __KEXT -Xlinker __info_plist \
          -Xlinker Info.plist -isysroot $(SDKROOT)
CPPFLAGS := -I$(KERNELDIR) -I$(KERNELDIR)/.. -DKERNEL -D__KERNEL__
LDFLAGS := -lkmod -r

all: $(BIN)

$(BIN): $(NAME).c Info.plist
	@mkdir -p $(KEXT)/Contents/MacOS
	$(CC) $(CFLAGS) $(CPPFLAGS) $(NAME).c -o $@ $(LDFLAGS)
	cp Info.plist $(INFO)

load: $(BIN)
	sudo chown -R root:wheel $(KEXT)
	sudo kextutil -v $(KEXT)

unload:
	sudo kextunload -v $(KEXT)

clean:
	rm -rf build

.PHONY: all load unload clean
