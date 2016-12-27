#!/bin/bash

export KUDU_HOME=${KUDU_HOME:-/home/hadoop/kudu}

exec ${KUDU_HOME}/bin/kudu "$@"
