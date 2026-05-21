Name:           wl-gammarelay-rs
Version:        1.0.1
Release:        %autorelease
Summary:        Wayland display temperature and brightness control via DBus

License:        GPL-3.0-only
URL:            https://github.com/MaxVerevkin/wl-gammarelay-rs
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz
# Vendor tarball created during SRPM build (COPR chroots lack network)
Source1:        %{name}-%{version}-vendor.tar.gz

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
tar xf %{SOURCE1}
mkdir -p .cargo
cp cargo-config.toml .cargo/config.toml

%build
cargo build --release --offline

%install
mkdir -p %{buildroot}%{_bindir}
install -Dpm755 target/release/%{name} %{buildroot}%{_bindir}/%{name}

%files
%{_bindir}/%{name}

%changelog
%autochangelog
