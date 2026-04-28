%global debug_package %{nil}
%global __strip /bin/true

Name:           pi
Version:        0.70.5
Release:        1%{?dist}
Summary:        Terminal-based coding agent with multi-model support

License:        MIT
URL:            https://github.com/badlogic/pi-mono

# Architecture-specific prebuilt binaries (both included in SRPM, %ifarch selects in %prep)
Source0:        %{url}/releases/download/v%{version}/pi-linux-x64.tar.gz
Source1:        %{url}/releases/download/v%{version}/pi-linux-arm64.tar.gz

ExclusiveArch:  x86_64 aarch64

%global _missing_build_ids_terminate_build 0

%description
pi is a terminal-based coding agent with multi-model support, mid-session
model switching, and a simple CLI for headless coding tasks.

%prep
%setup -q -c -T
%ifarch x86_64
tar xf %{SOURCE0}
%endif
%ifarch aarch64
tar xf %{SOURCE1}
%endif

%install
install -d %{buildroot}%{_prefix}/lib/%{name}
cp -r pi/* %{buildroot}%{_prefix}/lib/%{name}/
chmod 0755 %{buildroot}%{_prefix}/lib/%{name}/pi

install -d %{buildroot}%{_bindir}
ln -sf ../lib/%{name}/pi %{buildroot}%{_bindir}/pi

# Install docs if present
install -d %{buildroot}%{_docdir}/%{name}
[ -f pi/README.md ] && install -Dpm 0644 pi/README.md %{buildroot}%{_docdir}/%{name}/README.md || :
[ -f pi/CHANGELOG.md ] && install -Dpm 0644 pi/CHANGELOG.md %{buildroot}%{_docdir}/%{name}/CHANGELOG.md || :

%files
%{_prefix}/lib/%{name}/
%{_bindir}/pi
%{_docdir}/%{name}/

%changelog
* Tue Mar 10 2026 Mecattaf <thomas@mecattaf.dev> - 0.57.1-1
- Initial package (prebuilt binary from upstream)
