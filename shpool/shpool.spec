Name:           shpool
Version:        0.10.1
Release:        1%{?dist}
Summary:        Terminal session multiplexer for persistent shell sessions

License:        Apache-2.0
URL:            https://github.com/shell-pool/shpool
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz
# Vendor tarball created during SRPM build (COPR chroots lack network)
Source1:        %{name}-%{version}-vendor.tar.gz

BuildRequires:  rust-packaging
BuildRequires:  cargo
BuildRequires:  git-core
BuildRequires:  systemd-rpm-macros

%description
shpool is a shell session pool that lets you create named shell sessions and
reattach to them later, similar to tmux or screen but designed specifically
for persistent shell session management. Sessions persist across SSH
disconnects and terminal closures.

%prep
%autosetup -n %{name}-%{version}
tar xf %{SOURCE1}
mkdir -p .cargo
cp cargo-config.toml .cargo/config.toml

%build
cargo build --release --offline

%install
install -Dpm 0755 target/release/%{name} %{buildroot}%{_bindir}/%{name}
install -Dpm 0644 systemd/%{name}.service %{buildroot}%{_userunitdir}/%{name}.service
install -Dpm 0644 systemd/%{name}.socket %{buildroot}%{_userunitdir}/%{name}.socket

%files
%license LICENSE
%doc README.md
%{_bindir}/%{name}
%{_userunitdir}/%{name}.service
%{_userunitdir}/%{name}.socket

%post
%systemd_user_post %{name}.service %{name}.socket

%preun
%systemd_user_preun %{name}.service %{name}.socket

%postun
%systemd_user_postun_with_restart %{name}.service %{name}.socket

%changelog
* Tue Mar 10 2026 Mecattaf <thomas@mecattaf.dev> - 0.9.3-1
- Initial package
