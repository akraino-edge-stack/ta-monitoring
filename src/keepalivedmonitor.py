#! /usr/bin/python

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

import socket
import select
import os
import errno
import sys

if __name__ == '__main__':
    host = socket.gethostname()
    ip = socket.gethostbyname(host)
    port = int(sys.argv[1])

    print("Starting listening to port %d" % port)

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.setblocking(0)
    s.bind((ip, port))
    s.listen(1)
    inputs = [s]
    while True:
        try:
            readable, _, _ = select.select(inputs, [], [])
            for f in readable:
                if f is s:
                    client, address = s.accept()
                    client.setblocking(0)
                    inputs.append(client)
                    #print("Accepted connection from %r, total inputs %d" % (address, len(inputs)))
                else:
                    try:
                        result = f.recv()
                        if not result:
                            inputs.remove(f)
                    except Exception as exp:
                        inputs.remove(f)
        except (SystemExit, KeyboardInterrupt):
            break
        except select.error as ex:
            if ex.args[0] == errno.EINTR:
                break

    print("Stopping...")
