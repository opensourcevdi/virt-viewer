
scripts = [
    'buildenv.py',
    'dist.py',
    'gen-authors.py',
    'license-to-rtf.py',
    'make-icns.py',
    'msitool.py',
    'post_install.py',
    'run-windres.py',
]

foreach name : scripts
  sname = name.split('.')[0].underscorify()
  set_variable('@0@_prog'.format(sname), find_program(name))
endforeach
