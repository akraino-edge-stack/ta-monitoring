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

Name:       monitoring
Version:    %{_version}
Release:    1%{?dist}
Summary:    keepalived based node monitor and vip management
License:    %{_platform_licence}
Source0:    %{name}-%{version}.tar.gz
Vendor:     %{_platform_vendor}
BuildArch:  noarch
Requires: keepalived
BuildRequires: python
BuildRequires: python-setuptools

%description
This RPM contains code for the keepalived based monitoring

%prep
%autosetup

%build

%install
mkdir -p %{buildroot}/opt/monitoring/
cp src/*.sh %{buildroot}/opt/monitoring/
cp src/*.py %{buildroot}/opt/monitoring/

mkdir -p %{buildroot}/etc/monitoring/quorum-state-changed-actions
mkdir -p %{buildroot}/etc/monitoring/node-state-changed-actions

mkdir -p %{buildroot}/etc/monitoring/active-standby-services
cp active-standby-services/*.service %{buildroot}/etc/monitoring/active-standby-services/

cp active-standby-services/active-standby-controller.sh %{buildroot}/etc/monitoring/node-state-changed-actions/
cp active-standby-services/active-standby-monitor.sh %{buildroot}/opt/monitoring/

%files
/opt/monitoring/*
/etc/monitoring/quorum-state-changed-actions
/etc/monitoring/node-state-changed-actions
/etc/monitoring/node-state-changed-actions/*
/etc/monitoring/active-standby-services/*

%pre

%post
echo "monitoring succesfully installed"


%preun

%postun

%clean
rm -rf %{buildroot}
