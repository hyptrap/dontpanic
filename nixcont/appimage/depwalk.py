#!/usr/bin/env python3

from elftools.elf.dynamic import DynamicSection
from elftools.elf.segments import InterpSegment
from elftools.elf.elffile import ELFFile
import os
import sys


def find_deps(lib_path, sysroot=""):
    LIB_INSERTED = 0
    LIB_FOUNDED = 1

    if not os.path.exists(lib_path):
        # try with sysroot
        that_lib_path = f"{sysroot}{lib_path}"
        if not os.path.exists(that_lib_path):
            print(f"missing: {lib_path}", file=sys.stderr)
            return []
        lib_path = that_lib_path

    with open(lib_path, "rb") as fd:
        elffile = ELFFile(fd)
        libs = {}
        lib_pathes = []

        # find: interprter
        for segment in elffile.iter_segments():
            if isinstance(segment, InterpSegment):
                interp = segment.get_interp_name()
                if interp[0] == '/':
                    lib_pathes.append(f"{sysroot}{interp}")
                else:
                    libs[interp] = LIB_INSERTED

        # find: dependencies with RPATH and RUN_PATH
        run_pathes = []
        for section in elffile.iter_sections():
            if isinstance(section, DynamicSection):
                for tag in section.iter_tags():
                    d_tag = tag.entry.d_tag
                    if d_tag == "DT_NEEDED":
                        libs[tag.needed] = LIB_INSERTED
                    # RPATH: cannot override by LD_LIBRARY_PATH
                    # RUNPATH: can be override
                    # https://stackoverflow.com/a/8027971
                    # https://amir.rachum.com/shared-libraries/
                    elif d_tag == "DT_RPATH":
                        for path in tag.rpath.split(':'):
                            run_pathes.append(path)
                    elif d_tag == "DT_RUNPATH":
                        for path in tag.runpath.split(':'):
                            run_pathes.append(path)

        # locate the real file in run_pathes, todo: consider system's lib?
        for path in run_pathes:
            for lib in libs:
                # maybe duplicate here, we take them all, todo: priority like ldd?
                that_lib_path = f"{sysroot}{path}/{lib}"
                if os.path.isfile(that_lib_path):
                    lib_pathes.append(that_lib_path)
                    libs[lib] = LIB_FOUNDED

        # check missing
        for lib, state in libs.items():
            if state != LIB_FOUNDED:
                # skip some system deps... fixme
                if lib == "ld-linux-aarch64.so.1" or lib == "libc.so.6":
                    continue
                print(f"{lib_path}: missing {lib}", file=sys.stderr)

        return lib_pathes


def main(args):
    lib_path = ""
    sysroot = ""

    if len(args) >= 2:
        lib_path = args[1]
    if len(args) >= 3:
        sysroot = args[2]

    if not os.path.isfile(lib_path):
        print(f"usage: {args[0]} [lib_path] [sysroot]")
        return -1
    if len(sysroot) != 0 and not os.path.isdir(sysroot):
        print("sysroot doesn't exsist")
        return -1

    work_queue = [lib_path]
    lib_pathes = set()

    while len(work_queue) != 0:
        this_lib_path = work_queue.pop()
        lib_pathes.add(this_lib_path)

        for that_lib_path in find_deps(this_lib_path, sysroot):
            work_queue.append(that_lib_path)

    for this_lib_path in lib_pathes:
        print(this_lib_path)

    return 0


if __name__ == "__main__":
    exit(main(sys.argv))
