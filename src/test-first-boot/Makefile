ASFLAGS=-v
AS=asm6809
DEPS=$(wildcard ../includes/*.inc)
BUILD=./build
HOSTFS=~/hostfs/testblitsbc09

TARGET=test-first-boot
TARGET_BIN=$(addprefix $(BUILD)/, $(addsuffix .bin, $(TARGET)))
TARGET_INF=$(addsuffix .bin.inf, $(TARGET))

X:=$(shell mkdir -p $(BUILD))

all::	$(TARGET_BIN)

hostfs:: all
	$(shell if [[ ! -d $(HOSTFS) ]]; then mkdir -p $(HOSTFS); fi)
	cp $(TARGET_BIN) $(HOSTFS)
	cp $(TARGET_INF) $(HOSTFS)
	cp _21BOOT.* $(HOSTFS)
	

$(BUILD)/%.bin:	%.asm $(DEPS)
	$(AS) $(ASFLAGS) -B -3 --define=NATIVE -o $@ -l $(basename $@).lst $<
