THIS := $(lastword $(MAKEFILE_LIST))

$(info MAKEFILE_LIST: $(MAKEFILE_LIST))
$(info a.mk? $(THIS))
$(info )
