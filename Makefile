
DEV_IMAGE_NAME=fxsv/dev
BUILD_IMAGE_NAME=fxsv/build
INSTANCE_NAME=fxsv_latest
VENV_NAME=venv

# custom build
fxsv.zip: Dockerfile.build-environment.built

upload: fxsv.zip
	@echo "Using AWS credentials for $$AWS_DEFAULT_PROFILE in $$AWS_REGION"
	aws lambda update-function-code \
	    --function-name hwine_ffsv_dev \
	    --zip-file fileb://$(PWD)/fxsv.zip \

.PHONY: upload
publish: upload
	@echo "Using AWS credentials for $$AWS_DEFAULT_PROFILE in $$AWS_REGION"
	aws lambda publish-version \
	    --function-name hwine_ffsv_dev \
	    --code-sha-256 "$$(openssl sha1 -binary -sha256 fxsv.zip | base64 | tee /dev/tty)" \
	    --description "$$(date -u +%Y%m%dT%H%M%S)" \

.PHONY: invoke invoke-no-error invoke-error
invoke-no-error:
	@rm -f invoke_output-no-error.json
	@echo "Using AWS credentials for $$AWS_DEFAULT_PROFILE in $$AWS_REGION"
	@echo "Should not return error (but some 'fail')"
	aws lambda invoke \
		--function-name hwine_ffsv_dev \
		--payload "$$(cat tests/data/S3_event_template-no-error.json)" \
		invoke_output-no-error.json ; \
	    if test -s invoke_output-no-error.json; then \
		jq . invoke_output-no-error.json ; \
	    fi

invoke-error:
	@rm -f invoke_output-error.json
	@echo "Using AWS credentials for $$AWS_DEFAULT_PROFILE in $$AWS_REGION"
	@echo "Should return error"
	aws lambda invoke \
		--function-name hwine_ffsv_dev \
		--payload "$$(cat tests/data/S3_event_template-error.json)" \
		invoke_output-error.json ; \
	    if test -s invoke_output-error.json; then \
		jq . invoke_output-error.json ; \
	    fi

invoke: invoke-no-error invoke-error

# idea from
# https://stackoverflow.com/questions/23032580/reinstall-virtualenv-with-tox-when-requirements-txt-or-setup-py-changes#23039826
.PHONY: tests
tests: .tox/venv.touch
	tox $(REBUILD_FLAG)

.tox/venv.touch: setup.py requirements.txt
	$(eval REBUILD_FLAG := --recreate)
	mkdir -p $$(dirname $@)
	touch $@

Dockerfile.dev-environment.built: Dockerfile.dev-environment
	docker build -t $(DEV_IMAGE_NAME) -f $< .
	docker images $(DEV_IMAGE_NAME) >$@
	test -s $@ || rm $@

Dockerfile.build-environment: Dockerfile.dev-environment.built $(shell find src -name \*.py)
	touch $@

Dockerfile.build-environment.built: Dockerfile.build-environment
	docker build -t $(BUILD_IMAGE_NAME) -f $< .
	# get rid of anything old
	docker rm $(INSTANCE_NAME) || true	# okay if fails
	# retrieve the zip file
	docker run --name $(INSTANCE_NAME) $(BUILD_IMAGE_NAME)
	# delete old version, if any
	rm -f fxsv.zip
	docker cp $(INSTANCE_NAME):/tmp/fxsv.zip .
	# docker's host (VM) likely to have wrong time (on macOS). Update it
	touch fxsv.zip
	docker ps -qa --filter name=$(INSTANCE_NAME) >$@
	test -s $@ || rm $@

$(VENV_NAME):
	virtualenv --python=python2.7 $@
	source $(VENV_NAME)/bin/activate && echo req*.txt | xargs -n1 pip install -r
	@echo "Virtualenv created in $(VENV_NAME). You must activate before continuing."
	false

# vim: noet ts=8
