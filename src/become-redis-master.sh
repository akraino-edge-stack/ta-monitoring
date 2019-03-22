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

echo "Becoming master..."

filename=/etc/redis.conf
passwd=$(egrep -e "^requirepass" $filename | awk '{print $2}')

for ((i=0; i<5; i++)); do
    redis-cli -a $passwd slaveof no one
    if [ $? -eq 0 ]; then
        break
    fi

    sleep 1
done

exit 0
