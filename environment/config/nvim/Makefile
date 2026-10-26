.PHONY: test test-filter test-file bench bench-check coverage lint format format-check check ci install-deps clean

LUA_VERSION ?= 5.1

GIT_ENV := GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always

Luacheck_CANDIDATES := luacheck $(HOME)/.luarocks/bin/luacheck
LuaCov_CANDIDATES := luacov $(HOME)/.luarocks/bin/luacov
Stylua_CANDIDATES := stylua $(HOME)/.cargo/bin/stylua

test:
	$(GIT_ENV) vusted

test-filter:
	$(GIT_ENV) vusted --filter="$(FILTER)"

test-file:
	$(GIT_ENV) vusted $(FILE)

bench:
	nvim --headless -c 'luafile bench/harness.lua'

bench-check:
	@test -n "$(BENCH_BUDGET_MS)" || (echo "set BENCH_BUDGET_MS to a millisecond budget" && exit 1)
	BENCH_BUDGET_MS=$(BENCH_BUDGET_MS) nvim --headless -c 'luafile bench/harness.lua'

coverage:
	$(GIT_ENV) vusted --coverage
	@if [ -n "$(LUA_COV)" ]; then \
		$(LUA_COV); \
	else \
		echo "luacov not installed. Run make install-deps."; \
		exit 1; \
	fi

define find_tool
$(shell for c in $(1); do if command -v $$c >/dev/null 2>&1; then echo $$c; exit; fi; done)
endef

LUA_CHECK := $(call find_tool,$(Luacheck_CANDIDATES))
LUA_COV := $(call find_tool,$(LuaCov_CANDIDATES))
STYLUA := $(call find_tool,$(Stylua_CANDIDATES))

lint:
	@if [ -n "$(LUA_CHECK)" ]; then \
		$(LUA_CHECK) . --config .luacheckrc; \
	else \
		echo "luacheck not installed. Skipping..."; \
	fi

format:
	@if [ -n "$(STYLUA)" ]; then \
		$(STYLUA) --config-path stylua.toml lua/; \
	else \
		echo "stylua not installed. Skipping..."; \
	fi

format-check:
	@if [ -n "$(STYLUA)" ]; then \
		$(STYLUA) --check --config-path stylua.toml lua/; \
	else \
		echo "stylua not installed. Skipping..."; \
	fi

check: lint format-check

install-deps:
	luarocks --lua-version=$(LUA_VERSION) install vusted
	luarocks --lua-version=$(LUA_VERSION) install luacheck
	luarocks --lua-version=$(LUA_VERSION) install luacov

clean:
	rm -rf luacov.stats.out luacov.report.out

ci: check test