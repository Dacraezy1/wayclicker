# Binary package: the program is built beforehand (cargo + flutter) and
# installed with install.sh. Build with packaging/rpm/build_rpm.sh.
%global debug_package %{nil}
%global __os_install_post %{nil}
%global _build_id_links none

Name:           wayclicker
Version:        %{wc_version}
Release:        1%{?dist}
Summary:        Simple autoclicker for Linux (Wayland and X11)
License:        GPL-3.0-only
URL:            https://github.com/Dacraezy1/wayclicker
ExclusiveArch:  x86_64
AutoReqProv:    no
Requires:       gtk3
Recommends:     polkit

%description
Wayclicker clicks or holds mouse buttons and keys on a hotkey. It uses the
kernel uinput interface, so it works on GNOME, KDE, Hyprland, Sway, X11 and
every other desktop.

%install
rm -rf %{buildroot}
DESTDIR=%{buildroot} PREFIX=/usr %{wc_src}/install.sh

%post
modprobe uinput >/dev/null 2>&1 || :
udevadm control --reload-rules >/dev/null 2>&1 || :
udevadm trigger --subsystem-match=misc --action=add >/dev/null 2>&1 || :
update-desktop-database -q /usr/share/applications >/dev/null 2>&1 || :
gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor >/dev/null 2>&1 || :

%postun
udevadm control --reload-rules >/dev/null 2>&1 || :
update-desktop-database -q /usr/share/applications >/dev/null 2>&1 || :

%files
%license /usr/share/licenses/wayclicker/LICENSE
/usr/bin/wayclicker
/usr/bin/wayclicker-gui
/usr/lib/wayclicker
/usr/lib/udev/rules.d/60-wayclicker.rules
/usr/lib/modules-load.d/wayclicker.conf
/usr/share/applications/wayclicker.desktop
/usr/share/icons/hicolor/scalable/apps/wayclicker.svg

%changelog
* Tue Nov 10 2026 Dacraezy1 <https://github.com/Dacraezy1/wayclicker> - %{wc_version}-1
- See https://github.com/Dacraezy1/wayclicker/releases
