# directories needed by the build
DIRS := .build .build/clonedigger

# the development environment
DEV_ENV = dev
DEV_ENV_PATH = .tox/$(DEV_ENV)
DEV_ENV_ABS_PATH = $(PWD)/$(DEV_ENV_PATH)
DEV_ENV_ACTIVATE = $(DEV_ENV_PATH)/bin/activate

# TODO: this should all be handled by git
CURRENT_VERSION = $(shell python -c "import xtraceback; print xtraceback.__version__")

# nose defaults
NOSETESTS ?= nosetests --with-xunit --xunit-file=.build/nosetests-$@.xml

# tox defaults
# XXX: We use tox from https://bitbucket.org/ischium/tox pending
# https://bitbucket.org/hpk42/tox/pull-request/7 as the --develop option is
# required for combined coverage
TOX ?= tox --develop -v -e

# supress tox failure under jenkins since this is (likely) about a failing test
# not a failing build
ifdef JENKINS_HOME
TOX := -$(TOX)
endif

# the tox environments to test
TEST_ENVS = $(shell grep envlist tox.ini | awk -F= '{print $$2}' | tr -d ,)

# for setup.py so that it knows not to install the nose entry point
export XTRACEBACK_NO_NOSE = 1

# vmake: relaunch in virtualenv as required
SUBMAKE := $(MAKE)
VSUBMAKE := . $(DEV_ENV_ACTIVATE) && $(SUBMAKE)

# silence by default
ifndef VENV_MAKE_DEBUG
VSUBMAKE := @$(VSUBMAKE) --no-print-directory
SUBMAKE := @$(SUBMAKE) --no-print-directory
endif

ifneq ($(VIRTUAL_ENV),$(DEV_ENV_ABS_PATH))
define vmake
	$(warning Relaunching in virtualenv $(DEV_ENV_ABS_PATH)...)
	$(VSUBMAKE) $(1)
endef
else
define vmake
	$(SUBMAKE) $(1)
endef
endif

.PHONY: printvars
printvars:
	$(foreach V,$(sort $(.VARIABLES)), \
		$(if $(filter-out environment% default automatic, $(origin $V)), \
			$(warning $V=$($V) ($(value $V)))))

$(DIRS):
	mkdir -p $@

$(DEV_ENV_ACTIVATE):
	virtualenv $(DEV_ENV_ABS_PATH)
	$(TOX) $(DEV_ENV) --notest

.PHONY: virtualenv
virtualenv: $(DEV_ENV_ACTIVATE)

.PHONY: .assert-venv
.assert-venv: virtualenv
	$(if $(VIRTUAL_ENV),,$(error Not in virtualenv $(DEV_ENV_ABS_PATH)))
	$(if $(subst $(DEV_ENV_ABS_PATH),,$(VIRTUAL_ENV)), \
		$(error	Not in correct virtualenv - VIRTUAL_ENV is "$(VIRTUAL_ENV)" \
			when it should be "$(DEV_ENV_ABS_PATH)".))

.PHONY: $(TEST_ENVS)
$(TEST_ENVS): .build
	$(TOX) $@ -- $(NOSETESTS) --with-coverage $(NOSETESTS_ARGS)

.PHONY: tox
tox: $(TEST_ENVS)

.PHONY: test .test
test: virtualenv
	$(call vmake,.test)
.test: .assert-venv
	$(NOSETESTS) $(NOSETESTS_ARGS)

.PHONY: coverage .coverage
coverage: virtualenv tox
	$(call vmake,.coverage)
.coverage:
	coverage combine
	coverage html
	coverage xml -o.build/coverage.xml

.PHONY: metrics .metrics
metrics: virtualenv
	$(call vmake,.metrics)
.metrics: .build/clonedigger .assert-venv
	-pylint --rcfile=.pylintrc -f parseable xtraceback > .build/pylint
	-pep8 --repeat xtraceback > .build/pep8
	clonedigger --cpd-output -o .build/clonedigger.xml xtraceback > /dev/null
	clonedigger -o .build/clonedigger/index.html xtraceback > /dev/null 2>&1
	sloccount --wide --details xtraceback > .build/sloccount

.PHONY: doc
doc: .build/doc/index.html

.build/doc/index.html: virtualenv $(shell find doc -type f)
	$(call vmake,.vdoc)

.vdoc: .assert-venv
	sphinx-build -W -b doctest doc .build/doc
#	sphinx-build -W -b spelling doc .build/doc
	sphinx-build -W -b coverage doc .build/doc
#	sphinx-build -W -b linkcheck doc .build/doc
	sphinx-build -W -b html doc .build/doc

.PHONY: release
release:
	$(if $(VERSION),,$(error VERSION not set))
	git flow release start $(VERSION)
	sed -e "s/$(CURRENT_VERSION)/$(VERSION)/" -i xtraceback/__init__.py
	git commit -m "version bump" xtraceback/__init__.py
	git flow release finish $(VERSION)
	git push --all
	git push --tags
	./setup.py sdist register upload upload_sphinx

.PHONY: clean
clean:
	git clean -fdX

.DEFAULT_GOAL := all
.PHONY: all
all: coverage metrics doc
