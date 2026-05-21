Name:           fgp-browser
Version:        0.1.0
Release:        2%{?dist}
Summary:        FGP daemon for browser automation via Chrome DevTools Protocol

License:        MIT
URL:            https://github.com/fast-gateway-protocol/browser
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz
# Bundled fgp-daemon (no tagged releases upstream)
Source1:        https://github.com/fast-gateway-protocol/daemon/archive/a16b0df43f235f0c7102ce931ece92c9ded45ef5/fgp-daemon-a16b0df.tar.gz
# Vendor tarball created during SRPM build (COPR chroots lack network)
Source2:        %{name}-%{version}-vendor.tar.gz
Patch0:         0001-support-CDP_URL-env-var.patch

Provides:       bundled(crate(fgp-daemon)) = 0.1.0

BuildRequires:  rust-packaging
BuildRequires:  cargo
BuildRequires:  gcc
BuildRequires:  openssl-devel
BuildRequires:  pkg-config

Recommends:     chromium

%description
A fast browser automation daemon using the Chrome DevTools Protocol (CDP)
directly to control Chrome/Chromium. Provides the browser-gateway CLI and
UNIX socket daemon accepting NDJSON requests via the Fast Gateway Protocol.
Supports multi-session parallel browser automation, ARIA accessibility tree
extraction, screenshots, form filling, clicking, and navigation.

Supports connecting to external CDP endpoints via the CDP_URL
environment variable or --connect flag, enabling use with browser
extensions like Playwriter on systems where Chrome is installed
via Flatpak.

%prep
%autosetup -n browser-%{version}
# Extract bundled fgp-daemon
tar xf %{SOURCE1} -C ..
# Patch Cargo.toml: replace git dependency with local path
sed -i 's|fgp-daemon = { git = "https://github.com/fast-gateway-protocol/daemon" }|fgp-daemon = { path = "../daemon-a16b0df43f235f0c7102ce931ece92c9ded45ef5" }|' Cargo.toml
# Extract vendor tarball (includes vendor/, cargo-config.toml, and Cargo.lock)
tar xf %{SOURCE2}
mkdir -p .cargo
cp cargo-config.toml .cargo/config.toml

%build
cargo build --release --offline

%install
install -Dpm 0755 target/release/browser-gateway %{buildroot}%{_bindir}/browser-gateway

%files
%license LICENSE
%doc README.md
%{_bindir}/browser-gateway

%changelog
* Wed Mar 11 2026 Mecattaf <thomas@mecattaf.dev> - 0.1.0-2
- Add CDP_URL env var support for external CDP relay connections
- Soften chromium dependency to Recommends

* Wed Mar 11 2026 Mecattaf <thomas@mecattaf.dev> - 0.1.0-1
- Initial package
