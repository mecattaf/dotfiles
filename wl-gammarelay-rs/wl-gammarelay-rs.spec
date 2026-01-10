Name:           wl-gammarelay-rs
Version:        null
Release:        %autorelease
Summary:        Wayland display temperature and brightness control via DBus

License:        GPL-3.0-only
URL:            https://github.com/MaxVerevkin/wl-gammarelay-rs
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz

BuildRequires:  gcc
BuildRequires:  rust
BuildRequires:  cargo
BuildRequires:  rust-packaging
BuildRequires:  pkg-config
BuildRequires:  pkgconfig(wayland-client)
BuildRequires:  pkgconfig(wayland-protocols)

Requires:       dbus

%description
A simple program that provides DBus interface to control display temperature 
and brightness under wayland without flickering. Can be used as an alternative 
to redshift/gammastep.

%prep
%autosetup
%{__cargo} vendor
mkdir -p .cargo
cat > .cargo/config << EOF
[source.crates-io]
replace-with = "vendored-sources"

[source.vendored-sources]
directory = "vendor"
EOF

%build
%{__cargo} build --release

%install
mkdir -p %{buildroot}%{_bindir}
install -Dpm755 target/release/%{name} %{buildroot}%{_bindir}/%{name}

%files
%{_bindir}/%{name}

%changelog
%autochangelog
