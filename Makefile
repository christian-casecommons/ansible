SHELL := /bin/bash

release:
	# ensure system directory exists and remove and previous
	# symlinks
	mkdir -p ./host_vars
	rm -rf ./host_vars/*

	# execute rake task to rebuild hosts and hosts_vars
	-bundle exec rake ansible:build_facts[./]

	# get default host ipv4 and copy THIS host facts to /etc/ansible/facts
	# should those facts exist
	$(eval ip = $(shell echo "`ip route get 1 | awk '{ print $$NF; exit }'`"))
	-cp ./host_vars/host-$(ip) ./facts

	# add ansible galaxy
	mkdir -p ./vendors
	-rm -rf /etc/ansible/vendors/*

	# for the roles that are available, we install in the usual manner
	# NOTE: this will NOT overwrite roles that are not available and were
	# provided via s3 pull
	-ansible-galaxy install \
		--ignore-errors \
		-r ./requirements.yml \
		--roles-path ./vendors
