#! /bin/bash

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

KEEPALIVED_LOG=/var/log/monitoring.log
ID=monitoring

QUORUM_ACTIONS_DIR=/etc/monitoring/quorum-state-changed-actions
NODE_STATE_ACTIONS_DIR=/etc/monitoring/node-state-changed-actions

function log()
{
    local priority=$1
    shift
    local message=$1

    logger $priority "${FUNCNAME[2]} ${message}"
    echo "$(date) ($priority) $ID ${FUNCNAME[2]} ${message}" >> $KEEPALIVED_LOG
}

function execute_actions()
{
    DIR=$1
    shift
    for file in $(ls $DIR/*.sh); do
        log info "Running $file"
        bash $file $*
        log info "Result $?"
    done
}
