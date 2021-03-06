#------------------------#
# NYC-DB                 #
#------------------------#

# CONNECTION VARIABLES
DB_HOST='127.0.0.1'
DB_DATABASE=nycdb
DB_USER=nycdb
DB_PASSWORD=nycdb

# exporting allows these variables
# to be accessed in the subshells
# required for template.sh to work
export DB_HOST
export DB_DATABASE
export DB_USER
export DB_PASSWORD

# use BASH as our sell
SHELL=/bin/bash

tasks = pluto \
	dobjobs \
	dofsales \
	hpd-registrations \
	hpd-violations \
	rentstab \
	verify


default: help

# This central task that builds the database
# Most of the individual databases can also be run on their own:
#    i.e. make hpd-violations
# However both dobjobs and hpd-registrations require tables from Pluto
nyc-db: $(tasks)

verify:
	python3 ./scripts/check_installation.py -H $(DB_HOST) -U $(DB_USER) -P $(DB_PASSWORD) -D $(DB_DATABASE)

download:
	./scripts/download.sh all

download-pluto-all:
	./scripts/download.sh all --pluto-all

pluto:
	./scripts/template.sh > ./modules/pluto/pg_setup.sh
	echo "pluto_root=$(shell pwd)/data/pluto/" >> modules/pluto/pg_setup.sh
	cd modules/pluto && make && ./pluto16v2.sh

JOB_FILINGS_PATH=$(shell pwd)/data/dobjobs/job_filings.csv

.ONESHELL: dobjobs
dobjobs:
	@echo "Inserting DOB data into postgres"
	set -eu
	./scripts/template.sh > ./modules/dobjobs/env.sh
	cd modules/dobjobs
	make install
	./venv/bin/dobjobs  --psql -H $(DB_HOST) -U $(DB_USER) -P $(DB_PASSWORD) -D $(DB_DATABASE) "$(JOB_FILINGS_PATH)"
	@echo "Indexing and Processing DOB Data"
	source env.sh
	execute_sql sql/geocode.sql
	execute_sql sql/add_columns.sql
	execute_sql sql/index.sql
	rm env.sh

DOF_SALES_PATH=$(shell pwd)/data/dofsales

dofsales:
	@echo "***DOF ROLLING SALES***"
	./scripts/template.sh > ./modules/dof-sales/env.sh
	cd modules/dof-sales && make && bash to_postgres.sh $(DOF_SALES_PATH)

hpd-registrations:
	@echo "***HPD Registrations***"
	./scripts/template.sh > ./modules/hpd/env.sh
	./scripts/hpd_registrations.sh

hpd-violations:
	@echo "***HPD Violations***"
	./scripts/template.sh > ./modules/hpd-violations/pg_setup.sh
	echo "HPD_VIOLATIONS_DATA_FOLDER=$(shell pwd)/data/hpd_violations/data" >> ./modules/hpd-violations/pg_setup.sh
	cd modules/hpd-violations && ./unzip.sh && ./to_postgres.sh
	rm $(shell pwd)/modules/hpd-violations/pg_setup.sh

RENTSTAB_FILE=$(shell pwd)/data/rentstab/joined.csv

rentstab:
	@echo "**Rent Stabilization Unit Counts**"
	@echo "NOTICE: The data used for this module is licensed CC-BY-SA by John Krauss (github.com/talos)"
	@echo "See https://github.com/talos/nyc-stabilization-unit-counts for more information"
	cd modules/rentstab && python3 rentstab.py -H $(DB_HOST) -U $(DB_USER) -P $(DB_PASSWORD) -D $(DB_DATABASE) "$(RENTSTAB_FILE)"

docker-setup:
	mkdir -p postgres-data
	docker pull aepyornis/nyc-db:0.0.2
	docker pull postgres:9.6

docker-download:
	docker-compose run nycdb bash -c "cd /opt/nyc-db && make download"

docker-run:
	docker-compose run nycdb bash -c "cd /opt/nyc-db && make nyc-db DB_DATABASE=postgres DB_USER=postgres DB_HOST=pg"

docker-psql-shell:
	PGPASSWORD=$(DB_PASSWORD) psql -U postgres -h 127.0.0.1 -d postgres

docker-db-standalone:
	docker run --name nycdb -v "/home/zy/code/nyc-db/postgres-data:/var/lib/postgresql/data" -e POSTGRES_PASSWORD=nycdb -d -p 127.0.0.1:5432:5432  postgres:9.6

docker-dump:
	docker-compose run pg pg_dump --no-owner --clean --if-exists -h pg -U postgres --file=/opt/nyc-db/nyc-db.sql postgres 

db-dump:
	PGPASSWORD=$(DB_PASSWORD) pg_dump --no-owner --clean --if-exists -U $(DB_USER) -h $(DB_HOST) $(DB_DATABASE) "nyc-db-$$(date +%F).sql"

db-dump-bzip:
	bzip2 --keep nyc-db*.sql

remove-venv:
	find ./modules -type d -name 'venv' -print0 | xargs -0 -r rm -r

clean: remove-venv
	rm -rf postgres-data
	type docker-compose > /dev/null 2>&1 && docker-compose rm -f || /bin/true

help:
	@echo 'NYC-DB: Postgres database of NYC housing data'
	@echo 'Copyright (C) 2017 Ziggy Mintz'
	@echo "This program is free software: you can redistribute it and/or modify"
	@echo "it under the terms of the GNU General Public License as published by"
	@echo "the Free Software Foundation, either version 3 of the License, or"
	@echo '(at your option) any later version.'
	@echo '---------------------------------------------------------------'
	@echo 'To use without docker:'
	@echo '  1) create a postgres database: createdb nycdb'
	@echo '  2) download the files: make download'
	@echo '  3) create the database: make nyc-db DB_USER=YOURPGUSER DB_PASS=YOURPASS'
	@echo '---------------------------------------------------------------'
	@echo ''
	@echo 'To use WITH docker:'
	@echo '   1) Setup: make docker-setup'
	@echo '   2) Download: make download'
	@echo '   3) Build db: make docker-run'
	@echo ''
	@echo 'If things get messed up try: '
	@echo ' $ sudo make remove-venv to clean the python environments'
	@echo '   or  '
	@echo ' $ sudo make clean to remove the postgres directory (and the database data!)'
	@echo 'Look at the README or Makefile for additional scripts'


.PHONY: $(tasks) nyc-db
.PHONY: download download-pluto-all
.PHONY: db-dump db-dump-bzip 
.PHONY: docker-setup docker-download docker-run docker-psql-shell docker-db-standalone docker-dump
.PHONY: clean remove-venv default help
