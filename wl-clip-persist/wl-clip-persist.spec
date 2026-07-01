Name:           wl-clip-persist
Version:        0.5.0
Release:        %autorelease
Summary:        Keep Wayland clipboard content alive after the source app closes

License:        MIT
URL:            https://github.com/Linus789/wl-clip-persist
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz
# Vendor tarball created during SRPM build (COPR chroots lack network)
Source1:        %{name}-%{version}-vendor.tar.gz

BuildRequires:  gcc
BuildRequires:  rust
BuildRequires:  cargo
BuildRequires:  rust-packaging

%description
A small daemon that watches Wayland clipboard offers and re-publishes them
under its own ownership so the content survives when the source application
exits. Uses pure-Rust Wayland bindings (wayrs-client) — no libwayland C
dependency needed at build time.

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
%license LICENSE
%{_bindir}/%{name}

%changelog
%autochangelog
