%global debug_package %{nil}

Name:           starship
Version:        1.25.1
Release:        %autorelease
Summary:        The minimal, blazing-fast, and infinitely customizable prompt for any shell

License:        ISC
URL:            https://github.com/starship/starship
Source0:        %{url}/releases/download/v%{version}/%{name}-x86_64-unknown-linux-gnu.tar.gz
Source1:        https://raw.githubusercontent.com/starship/starship/v%{version}/docs/config/README.md

# This is a prebuilt binary package, only available for x86_64
ExclusiveArch:  x86_64

%description
The minimal, blazing-fast, and infinitely customizable prompt for any shell!

- Fast: it's fast – really really fast! 🚀
- Customizable: configure every aspect of your prompt.
- Universal: works on any shell, on any operating system.
- Intelligent: shows relevant information at a glance.
- Feature rich: support for all your favorite tools.
- Easy: quick to install – start using it in minutes.

%prep
%setup -q -c
# Get the configuration README
cp %{SOURCE1} CONFIGURATION.md

%build
# Generate shell completions
./%{name} completions bash > %{name}.bash
./%{name} completions zsh > _%{name}
./%{name} completions fish > %{name}.fish

%install
# Install binary
install -Dpm755 %{name} %{buildroot}%{_bindir}/%{name}

# Install shell completions
install -Dpm644 %{name}.bash %{buildroot}%{_datadir}/bash-completion/completions/%{name}
install -Dpm644 %{name}.fish %{buildroot}%{_datadir}/fish/vendor_completions.d/%{name}.fish
install -Dpm644 _%{name} %{buildroot}%{_datadir}/zsh/site-functions/_%{name}

%files
%doc CONFIGURATION.md
%{_bindir}/%{name}
%{_datadir}/bash-completion/completions/%{name}
%{_datadir}/fish/vendor_completions.d/%{name}.fish
%{_datadir}/zsh/site-functions/_%{name}

%changelog
%autochangelog
