#!/bin/bash

function usage() {

cat << EOF

    USAGE: $0 [help | init | release] iaas env name [OPTIONS]

    COMMANDS:

        ACTION:
          help - Show this message.
          init - Deploy Bosh.
          release - Deploy Release.

        iaas - Folder container templates for the target IaaS
        env - Folder container the environment variables (i.e. boshrc) 
        name - Name of the manifest file without the extension to use for deployment (found in the IaaS template folder)

    OPTIONS:

    EXAMPLES:

EOF
}

function process_template() {

ruby - $1 <<END
require 'erb'

include ERB::Util

@vars = ENV.to_hash

if !File.exist?(ARGV[0])
    puts "ERB template #{ARGV[0]} does not exist."
    exit 1
end

template = IO.read(ARGV[0])
result = ERB.new(template, nil, '-<>').result(binding)
puts result
END
}

function initialize() {
    local iaas=$1
    local env=$2

    if [ -z $iaas ] || [ ! -d "$ROOT_DIR/templates/$iaas" ]; then
        echo "ERROR! IaaS must be one of:"
        for d in $(ls $ROOT_DIR/templates/$iaas); do echo "  - $d"; done
        exit 1
    fi
    if [ "$iaas" == "openstack" ]; then
        pip freeze | grep python-novaclient 2>&1 > /dev/null
        if [ $? -ne 0 ]; then
            echo "ERROR! Unable to find python or openstack clients."
            exit 1
        fi
    fi
    if [ -z $env ] || [ ! -d "$ROOT_DIR/environments/$env" ]; then
        echo "ERROR! Env must be one of:"
        for d in $(ls $ROOT_DIR/environments); do echo "  - $d"; done
        exit 1
    fi

    which bosh 2>&1 > /dev/null
    if [ $? -ne 0 ]; then
        echo "ERROR! Unable to find bosh CLI in system path."
        exit 1
    fi
    which bosh-init 2>&1 > /dev/null
    if [ $? -ne 0 ]; then
        echo "ERROR! Unable to find bosh-init CLI in system path."
        exit 1
    fi

    TEMPLATES_DIR=$ROOT_DIR/templates/$iaas
    ENVIRONMENT_DIR=$ROOT_DIR/environments/$env

    MANIFEST=$3
    MANIFEST_TEMPLATE="$TEMPLATES_DIR/$MANIFEST.yml.erb"
    BOSHRC_ENV="$ENVIRONMENT_DIR/boshrc"

    WORKSPACE_DIR=$ENVIRONMENT_DIR/.workspace
    mkdir -p $WORKSPACE_DIR

    if [ ! -e "$MANIFEST_TEMPLATE" ]; then
        echo "ERROR! Manifest must be one of:"
        for d in $(ls $TEMPLATES_DIR); do echo "  - ${d%.yml*}"; done
        exit 1
    fi
    if [ ! -e "$BOSHRC_ENV" ]; then
        echo "ERROR! Bosh environment variable file '$BOSHRC_ENV' not found."
        exit 1
    fi

    source $BOSHRC_ENV

    STEMCELL_DIR=$ROOT_DIR/.stemcells
    mkdir -p $STEMCELL_DIR

    if [ -z $BOSH_STEMCELL_URL ]; then
        echo "BOSH_STEMCELL_URL environment variable is empty."
        exit 1
    fi

    STEMCELL_BASE=$(basename $BOSH_STEMCELL_URL) 
    STEMCELL_NAME=${STEMCELL_BASE%\?*}
    STEMCELL_VERSION=${STEMCELL_BASE#*\?v=}

    if [ ! -e "$STEMCELL_DIR/$STEMCELL_NAME.tgz" ]; then
        curl -k -J -L https://bosh.io/d/stemcells/bosh-openstack-kvm-ubuntu-trusty-go_agent-raw?v=2968 -o $STEMCELL_DIR/$STEMCELL_NAME.tgz
    fi

    SHA1=$(openssl sha1 .stemcells/bosh-openstack-kvm-ubuntu-trusty-go_agent-raw.tgz)
    export BOSH_STEMCELL_SHA1=${SHA1#*= }
}

function bosh_init_deploy() {

    process_template $MANIFEST_TEMPLATE > $WORKSPACE_DIR/$MANIFEST.yml
}

ROOT_DIR=$(cd $(dirname $0) && pwd)

case "$1" in
    help)
        usage
        ;;
    init)
        initialize $2 $3 $4
        bosh_init_deploy
        ;;
    release)
        initialize $2 $3 $4
        ;;
    *)
        usage
        exit 1
esac
