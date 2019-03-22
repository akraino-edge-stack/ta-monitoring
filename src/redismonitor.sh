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

echo "redis monitor started"

filename=/etc/redis.conf
passwd=$(egrep -e "^requirepass" $filename | awk '{print $2}')

while [ 1 ]; do
    redis-cli -a $passwd info | grep "role:master" 2> /dev/null 1>&2
    master=$?

    systemctl status rediscontroller 2> /dev/null 1>&2
    active=$?

    if [ $active -eq 0 -a $master -ne 0 ]; then
        echo "Changing redis db to master"
        /opt/monitoring/become-redis-master.sh
    elif [ $active -ne 0 -a $master -eq 0 ]; then
        echo "Changing redis db to slave"
        /opt/monitoring/become-redis-slave.sh $1
    fi

    sleep 10
done
