%global tag     1.12.4

Name:           scroll
Version:        1.12.4
Release:        1%{?dist}
Summary:        i3-compatible Wayland compositor with a scrolling layout
License:        MIT
URL:            https://github.com/dawsers/scroll
# Use archive URL instead of release tarball since release tarball doesn't exist
Source0:        %{url}/archive/refs/tags/%{tag}.tar.gz

# Minimal configuration file for headless or buildroot use
Source100:      config.minimal
Source101:      scroll-portals.conf

# Upstream patches

# Fedora patches

# Conditional patches

BuildRequires:  gcc-c++
BuildRequires:  meson >= 0.60.0
BuildRequires:  pkgconfig(cairo)
BuildRequires:  pkgconfig(gdk-pixbuf-2.0)
BuildRequires:  pkgconfig(glesv2)
BuildRequires:  pkgconfig(json-c) >= 0.13
BuildRequires:  pkgconfig(libdrm)
BuildRequires:  pkgconfig(libevdev)
BuildRequires:  pkgconfig(libinput) >= 1.26.0
BuildRequires:  pkgconfig(libpcre2-8)
BuildRequires:  pkgconfig(libsystemd) >= 239
BuildRequires:  pkgconfig(libudev)
BuildRequires:  pkgconfig(lua) >= 5.4
BuildRequires:  pkgconfig(pango)
BuildRequires:  pkgconfig(pangocairo)
BuildRequires:  pkgconfig(pixman-1)
BuildRequires:  pkgconfig(scdoc)
BuildRequires:  pkgconfig(wayland-client)
BuildRequires:  pkgconfig(wayland-cursor)
BuildRequires:  pkgconfig(wayland-server) >= 1.23.1
BuildRequires:  pkgconfig(wayland-protocols) >= 1.41
BuildRequires:  pkgconfig(wlroots-0.19)
BuildRequires:  pkgconfig(xcb)
BuildRequires:  pkgconfig(xcb-icccm)
BuildRequires:  pkgconfig(xkbcommon) >= 1.5.0

# Require any of the available configuration packages;
# Prefer the -upstream one if none are directly specified in the package manager transaction
Requires:       %{name}-config
Suggests:       %{name}-config-upstream

%description
Scroll is a tiling window manager supporting Wayland compositor protocol and
i3/sway-compatible configuration. The main difference is scroll only supports
one layout, a scrolling layout similar to PaperWM, niri or hyprscroller.

Scroll adds features such as:
- Animations with customizable N-order Bezier curves
- Independent content scaling for individual Wayland windows
- Overview and Jump modes for window management
- Workspace scaling
- Trackpad/Mouse scrolling navigation
- Support for both portrait and landscape monitor orientations

# Configuration presets:
#
%package        config-upstream
Summary:        Upstream configuration for Scroll
BuildArch:      noarch
Requires:       %{name} = %{version}-%{release}
Provides:       %{name}-config = %{version}-%{release}
Conflicts:      %{name}-config

# Lack of graphical drivers may hurt the common use case
Requires:       mesa-dri-drivers
# Logind needs polkit to create a graphical session
Requires:       polkit
# swaybg is used in the default config
Requires:       swaybg
# dmenu (as well as rxvt any many others) requires XWayland on Scroll
Requires:       xorg-x11-server-Xwayland

# Scroll binds the terminal shortcut to one specific terminal. In our case foot
Recommends:     foot
# grim is the recommended way to take screenshots on scroll 1.0+
Recommends:     grim
# wmenu is the default launcher in scroll
Recommends:     wmenu
# Install configs and scripts for better integration with systemd user session
Recommends:     sway-systemd
# Both utilities are suggested in the default configuration
Recommends:     swayidle
Recommends:     swaylock

# Minimal installation doesn't include Qt Wayland backend
Recommends:     (qt5-qtwayland if qt5-qtbase-gui)
Recommends:     (qt6-qtwayland if qt6-qtbase-gui)

%description    config-upstream
Upstream configuration for Scroll.
Includes all important dependencies for a typical desktop system
with minimal or no divergence from the upstream.


%package        config-minimal
RemovePathPostfixes:  .minimal
Summary:        Minimal configuration for Scroll
BuildArch:      noarch
Requires:       %{name} = %{version}-%{release}
Provides:       %{name}-config = %{version}-%{release}
Conflicts:      %{name}-config
# List of dependencies for headless or buildroot use

%description    config-minimal
Minimal configuration for Scroll without any extra dependencies.
Suitable for headless or buildroot use.


%prep
%autosetup -n %{name}-%{tag}

%build
%meson \
    -Dsd-bus-provider=libsystemd \
    -Dwerror=false
%meson_build

%install
%meson_install

# Remove wallpaper assets to prevent unpackaged files error
rm -rf %{buildroot}%{_datadir}/backgrounds 2>/dev/null || true

# Install minimal configuration file
install -D -m644 -pv %{SOURCE100} %{buildroot}%{_sysconfdir}/%{name}/config.minimal
# Install portals.conf for xdg-desktop-portal
install -D -m644 -pv %{SOURCE101} %{buildroot}%{_datadir}/xdg-desktop-portal/%{name}-portals.conf
# Create directory for extra config snippets
install -d -m755 -pv %{buildroot}%{_sysconfdir}/%{name}/config.d

%files
%license LICENSE
%dir %{_sysconfdir}/%{name}
%dir %{_sysconfdir}/%{name}/config.d
%{_mandir}/man1/%{name}*
%{_mandir}/man5/*
%{_mandir}/man7/*
%caps(cap_sys_nice=ep) %{_bindir}/%{name}
%{_bindir}/%{name}bar
%{_bindir}/%{name}msg
%{_bindir}/%{name}nag
%dir %{_datadir}/xdg-desktop-portal
%{_datadir}/xdg-desktop-portal/%{name}-portals.conf
%{bash_completions_dir}/%{name}*
%{fish_completions_dir}/%{name}*.fish
%{zsh_completions_dir}/_%{name}*

%files config-upstream
%config(noreplace) %{_sysconfdir}/%{name}/config
%{_datadir}/wayland-sessions/%{name}.desktop

%files config-minimal
%config(noreplace) %{_sysconfdir}/%{name}/config.minimal

%changelog
* Sat Jan 10 2026 Thomas Mecattaf <thomas@mecattaf.dev> - 1.12.4-1
- Update to 1.12.4
* Sat Jan 10 2026 Thomas Mecattaf <thomas@mecattaf.dev> - null-1
- Update to null
* Wed Dec 31 2025 Thomas Mecattaf <thomas@mecattaf.dev> - 1.12.4-1
- Update to 1.12.4
* Thu Dec 11 2025 Thomas Mecattaf <thomas@mecattaf.dev> - 1.12.2-1
- Update to 1.12.2
* Wed Dec 10 2025 Thomas Mecattaf <thomas@mecattaf.dev> - null-1
- Update to null
* Wed Dec 03 2025 Thomas Mecattaf <thomas@mecattaf.dev> - 1.12-1
- Update to 1.12
* Wed Dec 03 2025 Thomas Mecattaf <thomas@mecattaf.dev> - null-1
- Update to null
* Sun Nov 30 2025 Thomas Mecattaf <thomas@mecattaf.dev> - 1.12-1
- Update to 1.12
* Mon Nov 03 2025 Thomas Mecattaf <thomas@mecattaf.dev> - 1.11.8-1
- Update to 1.11.8
* Sun Nov 02 2025 Thomas Mecattaf <thomas@mecattaf.dev> - null-1
- Update to null
* Fri Sep 26 2025 Thomas Mecattaf  <thomas@mecattaf.dev> - 1.11.6-1
- Update to 1.11.7
* Sat Sep 20 2025 Thomas Mecattaf  <thomas@mecattaf.dev> - 1.11.6-1
- Update to 1.11.6
* Fri Sep 12 2025 Thomas Mecattaf  <thomas@mecattaf.dev> - 1.11.5-1
- Update to 1.11.5
* Sun Aug 17 2025 Thomas Mecattaf <thomas@mecattaf.dev> - 1.11.4-1
- Update to 1.11.4
* Sat Aug 16 2025 Thomas Mecattaf <thomas@mecattaf.dev> - null-1
- Update to null
* Wed Aug 13 2025 Thomas Mecattaf <thomas@mecattaf.dev> - 1.11.3-1
- Update to 1.11.3
* Tue Aug 12 2025 Thomas Mecattaf <thomas@mecattaf.dev> - null-1
- Update to null
* Fri Aug 01 2025 Thomas Mecattaf <thomas@mecattaf.dev> - 1.11.3-1
- Update to 1.11.3
* Fri Aug 01 2025 Thomas Mecattaf <thomas@mecattaf.dev> - null-1
- Update to null
* Sat Jul 19 2025 Thomas Mecattaf <thomas@mecattaf.dev> - 1.11.3-1
- Update to 1.11.3
* Thu Jul 10 2025 Thomas Mecattaf <thomas@mecattaf.dev> - 1.11.2-1
- Update to 1.11.2
* Thu Jul 10 2025 Thomas Mecattaf <thomas@mecattaf.dev> - null-1
- Update to null
* Wed Jul 09 2025 Thomas Mecattaf <thomas@mecattaf.dev> - 1.11.1-1
- Update to 1.11.1
* Tue Jul 08 2025 Thomas Mecattaf <thomas@mecattaf.dev> - null-1
- Update to null
* Thu Jul 03 2025 Thomas Mecattaf <thomas@mecattaf.dev> - 1.11.1-1
- Update to 1.11.1
* Wed Jun 11 2025 Thomas Mecattaf <thomas@mecattaf.dev> - 1.11-1
- Update to 1.11
* Wed Jun 11 2025 Thomas Mecattaf <thomas@mecattaf.dev> - null-1
- Update to null
* Sat May 10 2025 Thomas Mecattaf <thomas@mecattaf.dev> - 1.11-1
- Update to stable release 1.11
- First stable release of scroll, forked from sway 1.11
- Split configuration into upstream and minimal packages

* Sat May 10 2025 Thomas Mecattaf <thomas@mecattaf.dev> - 0.1.0~20250510gited43b3-0.1
- Initial package of scroll using git snapshot
