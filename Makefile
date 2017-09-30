PROG ?= mtomb
PREFIX ?= /usr
DESTDIR ?=
LIBDIR ?= $(PREFIX)/lib
SYSTEM_EXTENSION_DIR ?= $(LIBDIR)/password-store/extensions

all:
	@echo "pass-$(PROG) is a shell script and does not need compilation, it can be simply executed."
	@echo ""
	@echo "To install it try \"make install\" instead."
	@echo
	@echo "To run pass $(PROG) one needs to have some tools installed on the system:"
	@echo "     Tomb and password store"

install:
	@install -v -d "$(DESTDIR)$(SYSTEM_EXTENSION_DIR)/"
	@install -v -m 0755 $(PROG).bash "$(DESTDIR)$(SYSTEM_EXTENSION_DIR)/$(PROG).bash"
	@install -v -m 0755 open.bash "$(DESTDIR)$(SYSTEM_EXTENSION_DIR)/open.bash"
	@install -v -m 0755 close.bash "$(DESTDIR)$(SYSTEM_EXTENSION_DIR)/close.bash"
	@echo
	@echo "pass-$(PROG) is installed succesfully"
	@echo

uninstall:
	@rm -vrf \
		"$(DESTDIR)$(SYSTEM_EXTENSION_DIR)/$(PROG).bash" \
		"$(DESTDIR)$(SYSTEM_EXTENSION_DIR)/open.bash" \
		"$(DESTDIR)$(SYSTEM_EXTENSION_DIR)/close.bash" \

lint:
	shellcheck -s bash -e SC2181,SC2024 $(PROG).bash


.PHONY: install uninstall lint
