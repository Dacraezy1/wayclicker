Name:           wayclicker
Version:        0.2.0
Release:        1%{?dist}
Summary:        A powerful, universal autoclicker for Linux (Wayland & X11)

License:        GPLv3
URL:            https://github.com/Dacraezy1/wayclicker
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  cargo
BuildRequires:  rust
BuildRequires:  gtk3-devel
Requires:       gtk3
Recommends:     polkit

%description
Wayclicker uses Linux kernel uinput to create a virtual input device, allowing universal mouse and keyboard automation across all Wayland and X11 compositors.

%prep
%autosetup

%build
cargo build --release --locked

%install
rm -rf $RPM_BUILD_ROOT
install -Dpm 0755 target/release/wayclicker %{buildroot}%{_bindir}/wayclicker
install -Dpm 0644 wayclicker.desktop %{buildroot}%{_datadir}/applications/wayclicker.desktop
install -Dpm 0644 assets/wayclicker.svg %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/wayclicker.svg
install -Dpm 0644 packaging/udev/99-wayclicker.rules %{buildroot}%{_udevrulesdir}/99-wayclicker.rules

%files
%license LICENSE
%{_bindir}/wayclicker
%{_datadir}/applications/wayclicker.desktop
%{_datadir}/icons/hicolor/scalable/apps/wayclicker.svg
%{_udevrulesdir}/99-wayclicker.rules

%changelog
* Sat Oct 03 2026 Dacraezy1 <https://github.com/Dacraezy1/wayclicker> - 0.1.2-1
- Initial RPM packaging
