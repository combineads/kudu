#!/bin/bash
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Starts a Kudu Tablet Server
#
# chkconfig: 345 92 8
# description: Kudu Tablet Server
#
# Notes on service/facility dependencies:
#   -- Kudu server components require local file systems
#      to be mounted during start and stop to have access to config, data
#      and log files (which are usually placed at local filesystems).
#   -- If remote filesystems (NFS, etc.) are present, some related data
#      might reside there, so $remote_fs is also in the dependencies.
#   -- Kudu is a distributed system and usually deployed at multiple machines,
#      so $network is in the dependencies for start and stop.
#   -- Kudu server components use precision timing provided by hardware clock,
#      so $time is in the dependencies for start.
#   -- Kudu assumes time is synchronized between participating machines,
#      so ntpd service required for the start phase.
#
### BEGIN INIT INFO
# Provides:          kudu-tserver
# Short-Description: Kudu Tablet Server
# Default-Start:     3 4 5
# Default-Stop:      0 1 2 6
# Required-Start:    $time $local_fs $network ntpd
# Required-Stop:     $local_fs $network
# Should-Start:      $remote_fs
# Should-Stop:       $remote_fs
### END INIT INFO

export KUDU_HOME=${KUDU_HOME:-/home/hadoop/kudu}

. /lib/lsb/init-functions
. $KUDU_HOME/etc/default/kudu-tserver

RETVAL_SUCCESS=0

STATUS_RUNNING=0
STATUS_DEAD=1
STATUS_DEAD_AND_LOCK=2
STATUS_NOT_RUNNING=3
STATUS_OTHER_ERROR=102


ERROR_PROGRAM_NOT_INSTALLED=5
ERROR_PROGRAM_NOT_CONFIGURED=6


RETVAL=0
SLEEP_TIME=5
DAEMON="kudu-tserver"
DESC="Kudu Tablet Server"
EXEC_PATH="$KUDU_HOME/sbin/$DAEMON"
KUDU_CLI_PATH="$KUDU_HOME/bin/kudu"
SVC_USER="hadoop"
CONF_PATH="$KUDU_HOME/etc/kudu/conf/tserver.gflagfile"
PIDFILE="$KUDU_HOME/var/run/kudu/$DAEMON-kudu.pid"
LOCKDIR="$KUDU_HOME/var/lock/subsys"
LOCKFILE="$LOCKDIR/$DAEMON"

# Print something and exit.
kudu_die() {
  echo $2
  exit $1
}

# Check if the server is alive, looping for a little while.
kudu_check() {
  for i in $(seq 1 $SLEEP_TIME); do
    $KUDU_CLI_PATH tserver status "$FLAGS_rpc_bind_addresses" 1>/dev/null 2>&1
    if [ $? -eq 0 ]; then
      return $STATUS_RUNNING
    fi
    sleep 1
  done
  return $STATUS_DEAD
}

[ -n "$FLAGS_rpc_bind_addresses" ] || kudu_die $ERROR_PROGRAM_NOT_CONFIGURED \
  "Missing FLAGS_rpc_bind_addresses environment variable"
[ -n "$FLAGS_log_dir" ] || kudu_die $ERROR_PROGRAM_NOT_CONFIGURED \
  "Missing FLAGS_log_dir environment variable"

install -d -m 0755 -o hadoop -g hadoop $KUDU_HOME/var/run/kudu 1>/dev/null 2>&1 || :
[ -d "$LOCKDIR" ] || install -d -m 0755 $LOCKDIR 1>/dev/null 2>&1 || :

start() {
  [ -x $EXEC_PATH ] || kudu_die $ERROR_PROGRAM_NOT_INSTALLED \
    "Could not find binary $EXEC_PATH"
  [ -r $CONF_PATH ] || kudu_die $ERROR_PROGRAM_NOT_CONFIGURED \
    "Could not find config path $CONF_PATH"

  checkstatus >/dev/null 2>/dev/null
  status=$?
  if [ "$status" -eq "$STATUS_RUNNING" ]; then
    log_success_msg "${DESC} is running"
    exit 0
  fi


  /bin/bash -c "/bin/bash -c 'cd ~ && echo \$\$ > ${PIDFILE} && exec ${EXEC_PATH} --flagfile=${CONF_PATH} > ${FLAGS_log_dir}/${DAEMON}.out 2>&1' &"
  RETVAL=$?

  if [ $RETVAL -eq $STATUS_RUNNING ]; then
    kudu_check
    RETVAL=$?
    if [ $RETVAL -eq $STATUS_RUNNING ]; then
      touch $LOCKFILE
      log_success_msg "Started ${DESC} (${DAEMON}): "
      return $RETVAL
    fi
  fi
  log_failure_msg "Failed to start ${DESC}. Return value: $RETVAL"

  return $RETVAL
}
stop() {
  killproc -p $PIDFILE $EXEC_PATH
  RETVAL=$?

  if [ $RETVAL -eq $RETVAL_SUCCESS ]; then
    log_success_msg "Stopped ${DESC}: "
    rm -f $LOCKFILE $PIDFILE
  else
    log_failure_msg "Failure to stop ${DESC}. Return value: $RETVAL"
  fi

  return $RETVAL
}
restart() {
  stop
  start
}

checkstatusofproc(){
  pidofproc -p $PIDFILE $DAEMON > /dev/null
}

checkstatus(){
  checkstatusofproc
  status=$?

  case "$status" in
    $STATUS_RUNNING)
      log_success_msg "${DESC} is running"
      ;;
    $STATUS_DEAD)
      log_failure_msg "${DESC} is dead and pid file exists"
      ;;
    $STATUS_DEAD_AND_LOCK)
      log_failure_msg "${DESC} is dead and lock file exists"
      ;;
    $STATUS_NOT_RUNNING)
      log_failure_msg "${DESC} is not running"
      ;;
    *)
      log_failure_msg "${DESC} status is unknown"
      ;;
  esac
  return $status
}

condrestart(){
  [ -e $LOCKFILE ] && restart || :
}

service() {
  case "$1" in
    start)
      start
      ;;
    stop)
      stop
      ;;
    status)
      checkstatus
      RETVAL=$?
      ;;
    restart)
      restart
      ;;
    condrestart|try-restart)
      condrestart
      ;;
    *)
      echo $"Usage: $0 {start|stop|status|restart|try-restart|condrestart}"
      exit 1
  esac
}

service "$@"

exit $RETVAL
