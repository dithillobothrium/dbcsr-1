#!/usr/bin/env python
# -*- coding: utf-8 -*-

# author: Ole Schuett

import sys, os
import subprocess
from os import path
from glob import glob
from sets import Set

KNOWN_EXTENSIONS = ("F", "c", "cu", "cpp", "cxx", "cc", )

#=============================================================================
def main():
    if(len(sys.argv) != 4):
        print("Usage: check_archives.py <ar-executable> <src-dir> <lib-dir>")
        sys.exit(1)

    ar_exe  = sys.argv[1]
    src_dir = sys.argv[2]
    lib_dir = sys.argv[3]

    # Search all files belonging to a given archive
    archives_files={}
    for root, dirs, files in os.walk(src_dir):
        if "PACKAGE" in files:
            content = open(path.join(root,"PACKAGE")).read()
            package = eval(content)

            archive = "libdbcsr" + path.basename(root)
            if "archive" in package.keys():
                archive = package["archive"]

            file_parts = [fn.rsplit(".", 1) for fn in files]
            src_basenames = [parts[0] for parts in file_parts if parts[-1] in KNOWN_EXTENSIONS]

            if archive in archives_files:
                archives_files[archive] |= Set(src_basenames)
            else:
                archives_files[archive] = Set(src_basenames)

    # Check if the symbols in each archive have a corresponding source file
    for archive in archives_files:
        archive_fn = path.join(lib_dir, archive+".a")
        if(not path.exists(archive_fn)):
            continue

        output = check_output([ar_exe, "t", archive_fn])
        for line in output.strip().split("\n"):
            if(line == "__.SYMDEF SORTED"): continue  # needed for MacOS
            assert(line.endswith(".o"))
            if(line[:-2] not in archives_files[archive]):
                print("Could not find source for object %s in archive %s , removing archive."%(line, archive_fn))
                os.remove(archive_fn)
                break


#=============================================================================
def check_output(*popenargs, **kwargs):
    """ backport for Python 2.4 """
    p = subprocess.Popen(stdout=subprocess.PIPE, *popenargs, **kwargs)
    output = p.communicate()[0]
    assert(p.wait() == 0)
    return output.decode()

#=============================================================================
if(len(sys.argv)==2 and sys.argv[-1]=="--selftest"):
    pass #TODO implement selftest
else:
    main()

#EOF
