Name:           gws
Version:        0.22.5
Release:        1%{?dist}
Summary:        Google Workspace CLI — dynamic command surface from Discovery Service

License:        Apache-2.0
URL:            https://github.com/googleworkspace/cli
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz
# Vendor tarball created during SRPM build (COPR chroots lack network)
Source1:        %{name}-%{version}-vendor.tar.gz

BuildRequires:  rust-packaging
BuildRequires:  cargo
BuildRequires:  gcc
BuildRequires:  perl-interpreter

%description
A dynamic, schema-driven command-line tool for Google Workspace APIs.
Dynamically parses Google API Discovery Documents to construct CLI commands,
supporting deep schema validation, OAuth and Service Account authentication,
interactive prompts, and integration with Model Armor. Covers Gmail, Drive,
Calendar, Sheets, Docs, Chat, Meet, Tasks, and more.

%prep
%autosetup -n cli-%{version}
tar xf %{SOURCE1}
mkdir -p .cargo
cp cargo-config.toml .cargo/config.toml

%build
cargo build --release --offline

%install
install -Dpm 0755 target/release/%{name} %{buildroot}%{_bindir}/%{name}

%files
%license LICENSE
%doc README.md CHANGELOG.md
%{_bindir}/%{name}

%changelog
* Wed Mar 11 2026 Mecattaf <thomas@mecattaf.dev> - 0.11.1-1
- Initial package
