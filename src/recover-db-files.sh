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

if [ $# -ne 2 ]; then
	echo "Usage:$0 <node> <backup-dir>"
	exit 1
fi

node_arg=$1
backup_dir=$2
node=$(hostname)

if [ $node_arg -ne $node ]; then
    echo "You need to run the script from the same node where the corrupted db is"
    exit 1
fi

echo "Creating backup directory $backup_dir"

mkdir -p $backup_dir

if [ $? -ne 0 ]; then
	echo "Failed to create $backup_dir"
	exit 1
fi

echo "Locking db service"
/opt/nokia/bin/hascli -l -o /$node/mariadb/mariadb
if [ $? -ne 0 ]; then
    echo "Failed to lock /$node/mariadb/mariadb"
    exit 1
fi

echo "Copying existing db files"
cp -r /var/lib/mysql $backup_dir

echo "Removing old db files"
rm -rf /var/lib/mysql

echo "Recreating db directory"
mkdir /var/lib/mysql
chown mysql:mysql /var/lib/mysql
chmod 2755 /var/lib/mysql

echo "Installing the db"
/usr/bin/mysql_install_db --datadir=/var/lib/mysql --user=mysql
if [ $? -ne 0 ]; then
    echo "db installation failed"
    exit 1
fi
chown -R mysql:mysql /var/lib/mysql/
/usr/sbin/restorecon -R /var/lib/mysql

echo "Starting db in safe mode"
/usr/bin/mysqld_safe --wsrep-provider=none &
if [ $? -ne 0 ]; then
    echo "Failed to start db in safe mode"
    exit 1
fi

echo "Waiting for db to become up"
while [ 1 ]; do
    /bin/mysqladmin -h localhost -u root --password= ping | grep "mysqld is alive"
    if [ $? -eq 0 ]; then
        echo "DB is now up"
        break
    fi
    echo "DB is not yet up, waiting..."
    sleep 2
done

echo "Fix the passwords/grants"
root_password=$(sudo grep password /root/.my.cnf | cut -d'=' -f2)
echo "grant all on *.* to root@localhost identified by \"$root_password\";" >/tmp/restore.sql
echo "set password for 'root'@'localhost' = password(\"$root_password\");" >>/tmp/restore.sql
rc=0
mysql -h localhost -u root --password= < /tmp/restore.sql
if [ $? -ne 0 ]; then
    echo "Failed to fix grants"
    rc=1
fi

echo "Shutting down the db"
/usr/bin/mysqladmin -h localhost -u root shutdown
if [ $? -ne 0 ]; then
    echo "Failed to shutdown the db"
    rc=1
fi

if [ $rc -eq 0 ]; then
    echo "DB files recovered successfully, starting db"
    /opt/nokia/bin/hascli -u -o /$node/mariadb/mariadb
fi

exit $rc
