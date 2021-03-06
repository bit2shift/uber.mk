# Obtain the absolute path to ubermakefile's folder.
ÜBER.MK := $(abspath $(realpath $(lastword $(MAKEFILE_LIST)))/..)

# Le makefile.
SHELL := /bin/bash

# Check if jq is installed.
ifeq '' '$(shell jq --version 2> /dev/null)'
$(error error: jq is missing)
endif

# Check if pkg-config is installed.
ifeq '' '$(shell pkg-config --version 2> /dev/null)'
$(error error: pkg-config is missing)
endif

# Detect if CXX is clang++ or g++.
ifneq '' '$(findstring clang++,$(CXX))'
CXXFLAGS += -stdlib=libc++
LDLIBS   += -lc++
else ifneq '' '$(findstring g++,$(CXX))'
LDLIBS   += -lstdc++
endif

.PHONY: all build clean cleanall compile debug depbuild devall release

all: depbuild release
devall: depbuild debug

depbuild:
	@git submodule foreach 'jq -r ".dependencies.\"$$name\".build | arrays, strings | @sh" $$toplevel/ubermakefile.json | xargs -rn1 $(SHELL) -c'

cleanall: clean
	@git submodule foreach 'git clean -dffqx; git reset --hard'
	@$(RM) -r bin

clean:
	@echo 'Cleaning...'
	@$(RM) -r obj

# Common build flags.
$(eval $(shell jq -r '.flags.common // {} | to_entries | .[] | "$$(eval \(.key)+=\(.value))"' ubermakefile.json))

# Debug build flags.
$(eval $(shell jq -r '.flags.debug // {} | to_entries | .[] | "$$(eval debug: export \(.key)+=\(.value))"' ubermakefile.json))
debug: build

# Release build flags.
$(eval $(shell jq -r '.flags.release // {} | to_entries | .[] | "$$(eval release: export \(.key)+=\(.value))"' ubermakefile.json))
release: build

# Precompiled pkg-config invocation.
pc-path = $(eval pc-path := $(shell find $(CURDIR) -name '*.pc' -printf ':%h'))$(pc-path)
pkg-config = $(shell PKG_CONFIG_PATH+='$(pc-path)'; $(shell jq -r '.dependencies // {} | to_entries | map("pkg-config $(1) \([(select(.value.static) | "--static"), .key] | join(" "));") | join(" ")' ubermakefile.json))

# Lazy evaluation.
PKG_CONFIG_CPPFLAGS = $(eval PKG_CONFIG_CPPFLAGS := $(call pkg-config,--cflags))$(PKG_CONFIG_CPPFLAGS)
PKG_CONFIG_LDFLAGS  = $(eval PKG_CONFIG_LDFLAGS  := $(call pkg-config,--libs-only-L --libs-only-other))$(PKG_CONFIG_LDFLAGS)
PKG_CONFIG_LDLIBS   = $(eval PKG_CONFIG_LDLIBS   := $(call pkg-config,--libs-only-l))$(PKG_CONFIG_LDLIBS)

# Dependency flags.
build: export CPPFLAGS += $(PKG_CONFIG_CPPFLAGS)
build: export LDFLAGS  += $(PKG_CONFIG_LDFLAGS)
build: export LDLIBS   += $(PKG_CONFIG_LDLIBS)

# Le build.
build: export CPPFLAGS += -MMD -MP
build: SRC != find src -name '*.cpp' -printf '%P '
build: $(shell jq -r '.targets | to_entries | .[] | "bin/\(.key)"' ubermakefile.json)

bin/%: compile | bin
	@$(MAKE)\
		-Cbin\
		$(shell jq -r '.targets."$*" | (.flags // {} | to_entries | .[] | "\(.key)+=\(.value)"), ("$$(filter \(.objects | (arrays | join(" ")), strings),$$(OBJ))" as $$filter | (select(.static) | "$*(\($$filter))") // $$filter) | @sh "--eval=\("$*: \(.)")"' ubermakefile.json)\
		VPATH='$(CURDIR)/obj'\
		AR='@echo "Adding [$$%] to [$$@]"; mkdir -p $$(@D); $(AR)'\
		CC='@echo "Linking [$$@]"; mkdir -p $$(@D); $(CC)'\
		OBJ='$(SRC:.cpp=.o)'\
		$*

compile: | obj
	@$(MAKE)\
		-Cobj\
		--eval='-include $(SRC:.cpp=.d)'\
		VPATH='$(CURDIR)/src'\
		CXX='@echo "Compiling [$$@]"; mkdir -p $$(@D); $(CXX)'\
		$(SRC:.cpp=.o)

bin obj:
	@mkdir $@
