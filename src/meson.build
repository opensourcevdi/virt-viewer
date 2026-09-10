src_include_dir = [include_directories('.')]

enum_sources = [
  'virt-viewer-app.h',
  'virt-viewer-display.h',
]

common_enum_headers = gnome.mkenums(
  'virt-viewer-enums.h',
  sources: enum_sources,
  symbol_prefix: 'virt_viewer',
  identifier_prefix: 'VirtViewer',
  h_template: 'virt-viewer-enums.h.etemplate',
)

common_enum_sources = gnome.mkenums(
  'virt-viewer-enums.c',
  sources: enum_sources,
  symbol_prefix: 'virt_viewer',
  identifier_prefix: 'VirtViewer',
  c_template: 'virt-viewer-enums.c.etemplate',
)

ui_resources = gnome.compile_resources(
  'virt-viewer-resources',
  'resources/virt-viewer.gresource.xml',
  source_dir: 'resources',
)

util_sources = [
  'virt-viewer-util.c'
]

util_deps = [
  libxml_dep,
  glib_dep, gmodule_dep, gtk_dep,
]


util_lib = static_library(
  'virt-viewer-util',
  util_sources,
  dependencies: util_deps,
  include_directories: top_include_dir,
)


common_sources = [
  common_enum_headers,
  common_enum_sources,
  ui_resources,
  'glib-compat.c',
  'virt-viewer-auth.c',
  'virt-viewer-app.c',
  'virt-viewer-file.c',
  'virt-viewer-session.c',
  'virt-viewer-display.c',
  'virt-viewer-notebook.c',
  'virt-viewer-window.c',
  'virt-viewer-vm-connection.c',
  'virt-viewer-display-vte.c',
  'virt-viewer-timed-revealer.c',
]

if gtk_vnc_dep.found()
  common_sources += [
    'virt-viewer-session-vnc.c',
    'virt-viewer-display-vnc.c',
  ]
endif

if spice_gtk_dep.found()
  common_sources += [
    'virt-viewer-session-spice.c',
    'virt-viewer-display-spice.c',
    'virt-viewer-file-transfer-dialog.c',
  ]
endif

if govirt_dep.found()
  common_sources += [
    'ovirt-foreign-menu.c',
    'remote-viewer-iso-list-dialog.c',
  ]
endif

common_deps = [
  libm_dep,
  libxml_dep,
  glib_dep, gmodule_dep, gtk_dep,
  gtk_vnc_dep,
  spice_glib_dep, spice_gtk_dep, spice_protocol_dep,
  govirt_dep, rest_dep,
  vte_dep,
]


common_lib = static_library(
  'virt-viewer-common',
  common_sources,
  dependencies: common_deps,
  link_with: [util_lib],
  include_directories: top_include_dir,
)

virt_viewer_sources = [
  common_enum_headers,
  'virt-viewer.c',
  'virt-viewer-main.c'
]

virt_viewer_deps = common_deps + [
  libvirt_dep, libvirt_glib_dep,
]

remote_viewer_sources = [
  common_enum_headers,
  'remote-viewer.c',
  'remote-viewer-connect.c',
  'remote-viewer-main.c',
]

remote_viewer_deps = common_deps

# AEInstallEventHandler, for the spice:// Apple Event handler in remote-viewer.c.
remote_viewer_link_args = []
if host_machine.system() == 'darwin'
  remote_viewer_link_args += ['-framework', 'ApplicationServices']
endif

gui_security_link_args = []
cui_security_link_args = []
if host_machine.system() == 'windows'
  # binutils does not take into account entry point when
  # -pie is used so we need to provide it manually
  # The prefix is empty for x86_64, underscore ("_") otherwise
  entry_prefix = ''
  if host_machine.cpu() != 'x86_64'
    entry_prefix = '_'
  endif

  # --dynamicbase to enable ASLR protection
  # --nxcompat is to enable NX protection
  # -pie as --dynamicbase requires relocations
  gui_security_link_args += [
    '-Wl,--dynamicbase,-pie,--nxcompat',
    '-Wl,-e,@0@WinMainCRTStartup'.format(entry_prefix),
    '-mwindows',
  ]
  cui_security_link_args += [
    '-Wl,--dynamicbase,-pie,--nxcompat',
    '-Wl,-e,@0@WinMainCRTStartup'.format(entry_prefix),
    '-mconsole',
  ]
endif

if libvirt_dep.found()
  executable(
    'virt-viewer',
    virt_viewer_sources,
    dependencies: virt_viewer_deps,
    link_with: common_lib,
    link_args: gui_security_link_args,
    include_directories: top_include_dir,
    install: true,
    win_subsystem: 'windows',
  )
endif

executable(
  'remote-viewer',
  remote_viewer_sources,
  dependencies: remote_viewer_deps,
  link_with: common_lib,
  link_args: gui_security_link_args + remote_viewer_link_args,
  include_directories: top_include_dir,
  install: true,
  win_subsystem: 'windows',
)

if host_machine.system() == 'windows'
  windres = find_program('windres')

  rcfile = configure_file(
    input: 'virt-viewer.rc.in',
    output: 'virt-viewer.rc',
    configuration: conf_data
  )

  rcobj = custom_target(
    'virt-viewer-rc.o',
    input: [rcfile, icofile, 'virt-viewer.manifest'],
    output: ['virt-viewer-rc.o'],
    command : [
      python3,
      run_windres_prog.full_path(),
      windres,
      join_paths(meson.build_root(), 'icons'),
      meson.current_source_dir(),
      rcfile,
      '@OUTPUT@'
    ])

  wrapper_sources = [
    'windows-cmdline-wrapper.c',
    rcobj,
  ]

  executable(
    'windows-cmdline-wrapper',
    wrapper_sources,
    link_args: ['-lpsapi'] + cui_security_link_args,
    include_directories: top_include_dir,
    install: true,
  )
endif
