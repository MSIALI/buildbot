# developer utilities
DOCKERBUILD := docker build --build-arg http_proxy=$$http_proxy --build-arg https_proxy=$$https_proxy

.PHONY: docs pylint flake8

PIP?=pip

# build rst documentation
docs:
	$(MAKE) -C master/docs

# check rst documentation
docschecks:
	$(MAKE) -C master/docs SPHINXOPTS=-W spelling
	$(MAKE) -C master/docs SPHINXOPTS=-q linkcheck

# pylint the whole sourcecode (validate.sh will do that as well, but only process the modified files)
pylint:
	$(MAKE) -C master pylint; master_res=$$?; \
	$(MAKE) -C worker pylint; worker_res=$$?; \
	if [ $$master_res != 0 ] || [ $$worker_res != 0 ]; then exit 1; fi

# flake8 the whole sourcecode (validate.sh will do that as well, but only process the modified files)
flake8:
	$(MAKE) -C master flake8
	$(MAKE) -C worker flake8
	flake8 --config=common/flake8rc www/*/buildbot_*/
	flake8 --config=common/flake8rc www/*/setup.py

# rebuild front-end from source
frontend:
	$(PIP) install -e pkg
	$(PIP) install mock
	for i in base codeparameter console_view waterfall_view nestedexample; do $(PIP) install -e www/$$i || exit 1; done

# do installation tests. Test front-end can build and install for all install methods
frontend_install_tests:
	$(PIP) install -e pkg
	$(PIP) install mock wheel
	trial pkg/test_buildbot_pkg.py

prebuilt_frontend:
	$(PIP) install -U http://ftp.buildbot.net/pub/latest/buildbot_www-1latest-py2-none-any.whl
	$(PIP) install -U http://ftp.buildbot.net/pub/latest/buildbot_codeparameter-1latest-py2-none-any.whl
	$(PIP) install -U http://ftp.buildbot.net/pub/latest/buildbot_console_view-1latest-py2-none-any.whl
	$(PIP) install -U http://ftp.buildbot.net/pub/latest/buildbot_waterfall_view-1latest-py2-none-any.whl

# install git hooks for validating patches at commit time
hooks:
	cp common/hooks/* `git rev-parse --git-dir`/hooks
rmpyc:
	find . \( -name '*.pyc' -o -name '*.pyo' \) -exec rm -v {} \;

isort:
	isort -rc worker master
	git diff --name-only --stat "HEAD" | grep '.py$$' | xargs autopep8 -i
	git commit -a -m "isort+autopep8 run"


docker: docker-buildbot-worker docker-buildbot-worker-node docker-buildbot-master docker-buildbot-master-ubuntu
	echo done
docker-buildbot-worker:
	$(DOCKERBUILD) -t buildbot/buildbot-worker:master worker
docker-buildbot-worker-node:
	$(DOCKERBUILD) -t buildbot/buildbot-worker-node:master master/contrib/docker/pythonnode_worker
docker-buildbot-master:
	$(DOCKERBUILD) -t buildbot/buildbot-master:master master
docker-buildbot-master-ubuntu:
	$(DOCKERBUILD) -t buildbot/buildbot-master-ubuntu:master -f master/Dockerfile.ubuntu master


release:
	test ! -z "$(VERSION)"  #  usage: make release VERSION=0.9.2
	yes | towncrier --version $(VERSION) --date `date -u  +%F`
	git commit -m "relnotes for $(VERSION)"
	GPG_TTY=`tty` git tag -a -s $VERSION -m "TAG $(VERSION)"
	./common/maketarballs.sh
	./common/smokedist.sh
	make docs
	echo twine upload --sign dist/*
