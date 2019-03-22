#! /bin/bash

# Copyright 2019 Nokia

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

echo "active-cold-standby started"

SERVICESDIR=/etc/monitoring/active-standby-services/
VIP=$1
while [ 1 ]; do
    allocated=$(/usr/sbin/ip -4 a | grep $VIP | wc -l)
    if [ $allocated -gt 0 ]; then
        for service in $(ls $SERVICESDIR); do
            /bin/systemctl is-active --quiet $service
            if [ $? -ne 0 ]; then
                echo "monitoring starting $service"
                systemctl start --no-block $service
            fi
        done
    else
        for service in $(ls $SERVICESDIR); do
            /bin/systemctl is-active --quiet $service
            if [ $? -eq 0 ]; then
                echo "monitoring stopping $service"
                systemctl stop --no-block $service
            fi
        done
    fi
    sleep 10
done
