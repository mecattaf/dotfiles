%global debug_package %{nil}

Name:           cliamp
Version:        1.40.0
Release:        1%{?dist}
Summary:        A retro terminal music player inspired by Winamp

License:        MIT
URL:            https://github.com/bjarneo/cliamp

# Architecture-specific prebuilt binaries
Source0:        %{url}/releases/download/v%{version}/%{name}-linux-amd64
Source1:        %{url}/releases/download/v%{version}/%{name}-linux-arm64

ExclusiveArch:  x86_64 aarch64

%global _missing_build_ids_terminate_build 0

%description
cliamp is a retro terminal music player inspired by Winamp. It supports
playing local files, streams, podcasts, and content from YouTube, SoundCloud,
Bilibili, Spotify, and Navidrome. Features include a spectrum visualizer,
parametric EQ, and playlist management.

%prep
%setup -q -c -T
%ifarch x86_64
cp %{SOURCE0} %{name}
%endif
%ifarch aarch64
cp %{SOURCE1} %{name}
%endif
chmod 0755 %{name}

%build
# Prebuilt binary, nothing to build

%install
install -Dpm755 %{name} %{buildroot}%{_bindir}/%{name}

%files
%{_bindir}/%{name}

%changelog
* Mon Mar 17 2026 Mecattaf <thomas@mecattaf.dev> - 1.21.5-1
- Initial package (prebuilt binary from upstream)
