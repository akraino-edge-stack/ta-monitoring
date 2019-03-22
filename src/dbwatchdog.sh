#!/bin/bash

# Copyright 2019 Nokia

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

DBAGENT_LOG=/var/log/dbwatchdog.log
DOMAIN=galera
OWNNODE=$(hostname)
DSSCLI=/usr/local/bin/dsscli
BECOMEMASTERATTR=become-master
LOCKNAME=galera
LOCKTIMEOUT=60
LOCKCLI=/usr/local/bin/lockcli
LOCKNAME=galera
LOCKHOLDER=$OWNNODE
LOCKUUID=0
LOCKUUID_FILE=/var/run/.$DOMAIN.lock.uuid

declare -a dbnodes
dbnodes_count=1

function get_db_nodes() 
{
    IFS=',' read -a dbnodes <<< $1
    dbnodes_count=${#dbnodes[@]}
}



function log()
{
    local priority=$1
    shift
    local message=$1

    logger $priority "${FUNCNAME[2]} ${message}"
    echo "$(date) ($priority) ${FUNCNAME[2]} ${message}" >> $DBAGENT_LOG
}

function log_info()
{
    log info "$@"
}

function log_error()
{
    log error "$@"
}

function run_cmd()
{
    local result
    local ret
    log_info "Running $*"
    result=$(eval "$*" 2>&1)
    ret=$?
    if [ $ret -ne 0 ]; then
           log_error "Failed with error $result"
       else
           log_info "Command succeeded: $result"
       fi
    echo "$result"
    return $ret
}

function is_db_instance_running()
{
    output=$(/usr/bin/mysql -h $node -e "select 1" 2>&1)
    if [ $? -eq 0 ]; then
        log_info "DB instance in $node is up"
        return 1
    fi

    echo $output | grep "Access denied"
    if [ $? -eq 0 ]; then
        log_info "DB instance in $node is up"
        return 1
    fi

    return 0
}

function is_single_node()
{
    log_info "Checking if we are running in single-node environment"
    if [ $dbnodes_count -gt 1 ]; then
        return 0
    fi

    return 1
}

function lock()
{
    log_info "Acquiring lock"
    while [ 1 ]; do
        output=$($LOCKCLI lock --id $LOCKNAME --timeout $LOCKTIMEOUT)
        if [ $? -eq 0 ]; then
            LOCKUUID=$(echo $output | grep "uuid=" | /bin/awk -F= '{print $2}')
            break
        fi
        log_info "Cannot acquire lock, waiting..."
        sleep 5
    done
}

function unlock()
{
    log_info "Releasing lock"
    uuid=$(cat $LOCKUUID_FILE)
    run_cmd "$LOCKCLI unlock --id $LOCKNAME --uuid $uuid"
    return 0
}

function set_becoming_master()
{
    log_info "Setting becoming master"
    run_cmd "$DSSCLI set --domain $DOMAIN --name $BECOMEMASTERATTR --value $OWNNODE"

    ret=$?

    if [ $ret -eq 0 ]; then
        while [ 1 ]; do
            log_info "Waiting for become master to be set"
            is_becoming_master_set
            if [ $? -eq 1 ]; then
                break
            fi
            sleep 1
        done
    fi

    return $ret
}

function is_becoming_master_set()
{
    log_info "Checking if becoming master is set"
    value=$(run_cmd "$DSSCLI get --domain $DOMAIN --name $BECOMEMASTERATTR")
    if [ $? -ne 0 ]; then
        value=none
    fi
    if [ "z$value" != "znone" ]; then
        return 1
    fi
    return 0
}

function get_becoming_master_node()
{
    log_info "Getting the node trying to become master"
    value=$(run_cmd "$DSSCLI get --domain $DOMAIN --name $BECOMEMASTERATTR")
    ret=$?
    if [ $ret -ne 0 ]; then
        value=none
    fi
    echo $value
    return $ret
}

function unset_becoming_master()
{
    log_info "Unsetting becoming master"
    run_cmd "$DSSCLI set --domain $DOMAIN --name $BECOMEMASTERATTR --value none"
}


function set_wsrep_new_cluster()
{
    log_info "Setting new cluster and safe to bootstrap"
    run_cmd "sed -i 's/^safe_to_bootstrap: 0/safe_to_bootstrap: 1/g' /var/lib/mysql/grastate.dat"
    run_cmd "systemctl set-environment _WSREP_NEW_CLUSTER='--wsrep-new-cluster'"
}

function unset_wsrep_new_cluster()
{
    log_info "Clearing new cluster flag and safe to bootstrap"
    run_cmd "sed -i 's/^safe_to_bootstrap: 1/safe_to_bootstrap: 0/g' /var/lib/mysql/grastate.dat"
    run_cmd "systemctl set-environment _WSREP_NEW_CLUSTER=''"
}

### own attributes
function set_running()
{
    log_info "Setting running flag to true"
    run_cmd "$DSSCLI set --domain $DOMAIN --name ${OWNNODE}.running --value true"
}

function unset_running()
{
    log_info "Setting running flag to false"
    run_cmd "$DSSCLI set --domain $DOMAIN --name ${OWNNODE}.running --value false"
    
}

function write_state()
{
    uuid=$(grep uuid /var/lib/mysql/grastate.dat  | awk '{print $2}')
    seqno=$(grep seqno /var/lib/mysql/grastate.dat  | awk '{print $2}')
    run_cmd "$DSSCLI set --domain $DOMAIN --name ${OWNNODE}.uuid --value $uuid"
    run_cmd "$DSSCLI set --domain $DOMAIN --name ${OWNNODE}.seqno --value $seqno"
}

### query functions
function get_node_uuid()
{   
    node=$1
    log_info "Getting uuid of node $node"
    uuid=$(run_cmd "$DSSCLI get --domain $DOMAIN --name ${node}.uuid")
    ret=$?
    if [ $ret -ne 0 ]; then
        uuid=0
    fi
    echo $uuid
    return $ret
}

function get_node_seqno()
{   
    node=$1
    log_info "Getting seqno of node $node"
    seqno=$(run_cmd "$DSSCLI get --domain $DOMAIN --name ${node}.seqno")
    ret=$?
    if [ $ret -ne 0 ]; then
        seqno=-1
    fi
    echo $seqno
    return $ret
}

function do_others_have_good_seqno()
{   
    node=$1
    log_info "Checking if any node have a valid seqno"
    for no in $($DSSCLI get-domain --domain $DOMAIN | grep seqno | awk '{print $3}'); do
        if [ $no -gt 0 ]; then
            log_info "Some node have a valid seqno"
            return 1
        fi
    done
    log_info "No node with valid seqno found"
    return 0
}

function get_node_running()
{
    node=$1
    log_info "Getting if $node is running"
    running=$(run_cmd "$DSSCLI get --domain $DOMAIN --name ${node}.running")
    if [ $? -ne 0 ]; then
        log_info "command failed with error $running"
        running='false'
    fi
    log_info "Total running $running"
    if [ "z$running" == "ztrue" ]; then
        return 1
    fi
    return 0
}


function is_any_db_instance_running()
{
    log_info "Getting nodes in which the db is running"
    total_initializing=0
    for node in "${dbnodes[@]}"; do
        if [ "x$node" == "x$OWNNODE" ]; then
            continue
        fi

        is_db_instance_running $node
        if [ $? -eq 1 ]; then
            log_info "DB instance in $node is up"
            return 1
        fi
    done

    return 0
}
function is_cluster_running()
{
    log_info "Checking if an existing galera cluster is running"

    #check if any instance of the db is up and running
    is_any_db_instance_running
    if [ $? -eq 1 ]; then
        return 1
    fi

    return 0
}

function wait_cluster_running()
{
    log_info "Waiting for cluster to become running"
    while [ 1 ]; do
        lock
        is_cluster_running
        cluster_running=$?
        if [ $cluster_running -eq 1 ]; then
            log_info "cluster is running"
            unlock
            return 0
        fi
        unlock
        sleep 5
    done
}
function start_pre()
{
    log_info "start_pre called"
    #check for single node case
    is_single_node
    single_node=$?
    if [ $single_node -eq 1 ]; then
        echo "Doing nothing as we are running in a single-node environment"
        return 0
    fi
    #acquire lock
    lock
    is_cluster_running
    cluster_running=$?
    if [ $cluster_running -eq 1 ]; then
        log_info "starting normally as a galera cluster is already running"
        return 0
    fi

    #check if we have good seqno, if not then we need to wait for the active
    #as we cannot become master
    log_info "checking own sequence number"
    seqno=$(get_node_seqno $OWNNODE)
    if [ $seqno -le 0 ]; then
        #check the seqno of others
        do_others_have_good_seqno
        if [ $? -eq 1 ]; then
            log_info "bad seqno $seqno we need to wait for cluster to become running"
            unlock
            wait_cluster_running
            lock
            return 0
        fi
    fi

    if [ $seqno -le 0 ]; then
        log_info "no one seems to have a good seqno"
    else
        log_info "no running galera cluster found and we have good seqno"
    fi

    log_info "check if someone is trying to become master"
    is_becoming_master_set
    becoming_master=$?
    if [ $becoming_master -eq 1 ]; then
        log_info "someone is trying to become master, backing off"
        unlock
        wait_cluster_running
        lock
        return 0
    fi

    log_info "no one is trying to become master, let us become master"
    set_becoming_master
    set_wsrep_new_cluster
    return 0
}

function start_post()
{
    log_info "start_post setting running state to true"
    #check for single node case
    is_single_node
    single_node=$?
    if [ $single_node -eq 1 ]; then
        echo "Doing nothing as we are running in a single-node environment"
        return 0
    fi
    is_in_quorum
    qm=$?
    if [ $qm -eq 1 ]; then
        become_master_node=$(get_becoming_master_node)
        if [ "x$become_master_node" == "x$OWNNODE" ]; then
            unset_becoming_master
        fi
    fi

    set_running
    unset_wsrep_new_cluster
    unlock

    return 0
}

function stop_post()
{
    log_info "stop_post setting running state to false"
    #check for single node case
    is_single_node
    single_node=$?
    if [ $single_node -eq 1 ]; then
        echo "Doing nothing as we are running in a single-node environment"
        return 0
    fi
    is_in_quorum
    qm=$?
    if [ $qm -eq 1 ]; then
        become_master_node=$(get_becoming_master_node)
        if [ "x$become_master_node" == "x$OWNNODE" ]; then
            unset_becoming_master
        fi
    fi
    
    unset_wsrep_new_cluster
    if [ $qm -eq 1 ]; then
        write_state
        unset_running
        for ((i=0; i<10; i++)); do
            log_info "Waiting for own state to become not running"
            get_node_running $OWNNODE
            if [ $? -eq 0 ]; then
                log_info "Own state is updated"
                break
            fi
            sleep 2
        done
    fi
    unlock
    return 0
}

function stop()
{
    log_info "waiting until clustercheck is ok"
    is_single_node
    single_node=$?
    if [ $single_node -eq 1 ]; then
        log_info "Doing nothing as we are running in a single-node environment"
        return 0
    fi

    while true; do
        /usr/local/bin/clustercheck
        if [ $? -eq 0 ]; then
            log_info "clustercheck is ok"
            break
        fi
        sleep 2
    done
}

function get_states()
{
    log_info "Getting states"
    run_cmd "$DSSCLI get-domain --domain $DOMAIN"
    run_cmd "$DSSCLI get-domain --domain _locks"
    is_in_quorum
    if [ $? -eq 1 ]; then
        echo "Nodes have quorum"
    else
        echo "Nodes don't have quorum"
    fi
}

function is_in_quorum()
{
    log_info "Checking if peer nodes are running"
    nodes=$($DSSCLI get-domain --domain galera | grep running | awk -F. '{print $1}')
    if [ $? -ne 0 ]; then
        return 0
    fi

    count=0
    down=0
    up=0
    for node in "${dbnodes[@]}"; do
        let count=$count+1
        is_db_instance_running $node
        if [ $? -eq 1 ]; then
            let up=$up+1
        else
            let down=$down+1
        fi
    done

    log_info "Total $count, up $up, down $down"

    if [ $count -eq 1 ]; then
        return 1
    fi

    if [ $up -gt $down ]; then
        return 1
    fi

    return 0
}


function kill_old()
{
    log_info "Checking for hanging mysqld services"
    mysqlpid=$(/usr/sbin/pidof mysqld)
    if [ "x$mysqlpid" == "x" ]; then
        return
    fi
    kill -9 $mysqlpid
}

if [ $# -ne 2 ]; then
    echo "Usage:$0 start-pre|start-post|stop|stop-post|get-states|set-running|kill-old|do-others-have-good-seqno <comma separted list of db node names>"
    exit 1
fi

get_db_nodes $2

if [ $1 == "start-pre" ]; then
    start_pre
elif [ $1 == "start-post" ]; then
    start_post
elif [ $1 == "stop" ]; then
    stop
elif [ $1 == "stop-post" ]; then
    stop_post
elif [ $1 == "get-states" ]; then
    get_states
elif [ $1 == "set-running" ]; then
    set_running
elif [ $1 == "kill-old" ]; then
    kill_old
elif [ $1 == "do-others-have-good-seqno" ]; then
    do_others_have_good_seqno
elif [ $1 == "is-any-db-instance-running" ]; then
    is_any_db_instance_running
    result=$?
    echo "Result is $result"
else
    echo "Invalid option provided"
    echo "Usage:$0 start-pre|start-post|stop|stop-post|get-states|set-running|kill-old|do-others-have-good-seqno|is-any-db-instance-running"
    exit 1
fi
