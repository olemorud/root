#!/usr/bin/env python3

"""This mainly functions as a shell script, but python is used for its
   superior control flow. An important requirement of the CI is easily
   reproducible builds, therefore a wrapper is made for running shell
   commands so that they are also logged.

   The log is printed when build fails/succeeds and needs to perfectly
   reproduce the build when pasted into a shell. Therefore all file system
   modifying code not executed from shell needs a shell equivalent
   explicitly appended to the shell log.
      e.g. `os.chdir(x)` requires `cd x` to be appended to the shell log

   Writing a similar wrapper in bash is difficult because variables are
   expanded before being sent to the log wrapper in hard to predict ways. """

import datetime
import getopt
from hashlib import sha1
import os
import re
import shutil
import sys
import tarfile
import openstack

from build_utils import (
    cmake_options_from_dict,
    die,
    download_latest,
    load_config,
    print_warning,
    shortspaced,
    subprocess_with_log,
    upload_file,
)


CONTAINER = 'ROOT-build-artifacts'
DEFAULT_BUILDTYPE = 'Release'


def main():
    shell_log = ''
    yyyy_mm_dd = datetime.datetime.today().strftime('%Y-%m-%d')
    num_cores = os.cpu_count()

    # CLI arguments with defaults
    repository       = 'https://github.com/root-project/root'
    force_generation = False
    platform         = "centos8"
    incremental      = False
    buildtype        = "Release"
    head_ref         = None
    base_ref         = None

    options, _ = getopt.getopt(
        args = sys.argv[1:],
        shortopts = '',
        longopts = ["alwaysgenerate=", "platform=", "incremental=", "buildtype=",
                    "head_ref=", "base_ref=", "repository="]
    )

    for opt, val in options:
        if opt == "--alwaysgenerate":
            force_generation = val in ('true', '1', 'yes', 'on')
        elif opt == "--platform":
            platform = val
        elif opt == "--incremental":
            incremental = val in ('true', '1', 'yes', 'on')
        elif opt == "--buildtype":
            buildtype = val
        elif opt == "--head_ref":
            head_ref = val
        elif opt == "--base_ref":
            base_ref = val
        elif opt == "--repository":
            repository = val

    if not base_ref:
        die(1, "base_ref not specified")

    if (head_ref == base_ref) or not head_ref:
        print_warning("head_ref not specified or same as base_ref, building base_ref only")
        head_ref = base_ref

    print("Rebasing and building ROOT using:")
    print("head_ref: ", head_ref)
    print("base_ref: ", base_ref)

    windows = 'windows' in platform

    if windows:
        archive_compress_level = 1
        workdir = 'C:/ROOT-CI'
        os.environ['COMSPEC'] = 'powershell.exe'
    else:
        archive_compress_level = 6
        workdir = '/tmp/workspace'


    # Load CMake options from file
    python_script_dir = os.path.dirname(os.path.abspath(__file__))

    options_dict = {
        **load_config(f'{python_script_dir}/buildconfig/global.txt'),
        # below has precedence
        **load_config(f'{python_script_dir}/buildconfig/{platform}.txt')
    }
    options = cmake_options_from_dict(options_dict)


    # Clean up previous builds
    if os.path.exists(workdir):
        shutil.rmtree(workdir)

    os.makedirs(workdir)
    os.chdir(workdir)

    if windows:
        shell_log += shortspaced(f"""
            Remove-Item -Recurse -Force -Path {workdir}
            New-Item -Force -Type directory -Path {workdir}
            Set-Location -LiteralPath {workdir}
        """)
    else:
        shell_log += shortspaced(f"""
            rm -rf {workdir}/*
            cd {workdir}
        """)


    print("\nEstablishing s3 connection")
    # openstack.enable_logging(debug=True)
    connection = openstack.connect('envvars')
    # without openstack we can't run test workflow, might as well give up here ¯\_(ツ)_/¯
    if not connection:
        die(msg="Could not connect to OpenStack")


    # Download and extract previous build artifacts
    if incremental:
        print("Attempting incremental build")

        # Download and extract previous build artifacts
        try:
            print("\nDownloading")
            option_hash = sha1(options.encode('utf-8')).hexdigest()
            prefix = f'{platform}/{base_ref}/{buildtype}/{option_hash}'
            tar_path = download_latest(connection, CONTAINER, prefix, workdir)

            print("\nExtracting archive")
            with tarfile.open(tar_path) as tar:
                tar.extractall()

            if windows:
                shell_log += f"(new-object System.Net.WebClient).DownloadFile('https://s3.cern.ch/swift/v1/{CONTAINER}/{prefix}.tar.gz','{workdir}')"
            else:
                shell_log += f"wget https://s3.cern.ch/swift/v1/{CONTAINER}/{prefix}.tar.gz -x -nH --cut-dirs 3"
        except Exception as err:
            print_warning(f"failed: {err}")
            incremental = False


    # Add remote on non incremental builds
    if not incremental:
        print("Doing non-incremental build")

        if windows:
            result, shell_log = subprocess_with_log(f"""
                Remove-Item -Force -Recurse {workdir}
                New-Item -Force -Type directory -Path {workdir}
            """, shell_log)
        else:
            result, shell_log = subprocess_with_log(f"""
                rm -rf "{workdir}/*"
            """, shell_log)

        result, shell_log = subprocess_with_log(f"""
            git init '{workdir}/src' || exit 1
            cd '{workdir}/src' || exit 2
            git remote add origin '{repository}' || exit 3
        """, shell_log)

        if result != 0:
            die(result, "Failed to pull", shell_log)


    # First: fetch, build and upload base branch. Skipped if existing artifacts
    #   are up to date
    #
    # Makes some builds marginally slower but populates the artifact storage
    # which makes most builds much much faster
    result, shell_log = subprocess_with_log(f"""
        cd '{workdir}/src' || exit 1
        
        git checkout temp 2>/dev/null || git checkout -b temp
        
        git fetch origin {base_ref}:{base_ref} || exit 2
        git checkout -B {base_ref} origin/{base_ref} || exit 3
        
        if [ "$(git rev-parse HEAD)" = "$(git rev-parse '@{{u}}')" ]; then
            exit 123
        fi
    """, shell_log)

    skipbuild = False
    
    if result == 123:
        print("Existing build artifacts already up to date, skipping this build step")
        skipbuild = True
    elif result != 0:
        die(result, f"Failed to pull {base_ref}", shell_log)

    if not skipbuild:
        if not incremental:
            result, shell_log = subprocess_with_log(
                f"cmake -S '{workdir}/src' -B '{workdir}/build' {options}",
                shell_log
            )

            if result != 0:
                die(result, "Failed cmake generation step", shell_log)

        result, shell_log = subprocess_with_log(
            f"cmake --build '{workdir}/build' --config '{buildtype}' --parallel '{num_cores}'",
            shell_log
        )

        if result != 0:
            die(result, f"Failed to build {base_ref}", shell_log)

        release_branches = r'master|latest-stable|v.*?-.*?-.*?-patches'

        if not re.match(release_branches, base_ref):
            print_warning("{base_ref} is not a release branch, skipping artifact upload")
        elif not connection:
            print_warning("Could not connect to OpenStack, skipping artifact upload")
        else:
            print(f"Archiving build artifacts of {base_ref}")
            new_archive = f"{yyyy_mm_dd}.tar.gz"
            try:
                with tarfile.open(name = f"{workdir}/{new_archive}",
                                  mode = "x:gz",
                                  compresslevel = archive_compress_level) as targz:
                    targz.add("src")
                    targz.add("build")

                upload_file(
                    connection=connection,
                    container=CONTAINER,
                    name=f"{prefix}/{new_archive}",
                    path=f"{workdir}/{new_archive}"
                )
            except tarfile.TarError as err:
                print_warning("could not tar artifacts: ", {err})
            except Exception as err:
                print_warning("failed to archive/upload artifacts: ", {err})

    if head_ref != base_ref:
        # Rebase PR branch
        print(f"Rebasing {head_ref} onto {base_ref}...")

        result, shell_log = subprocess_with_log(f"""
            cd '{workdir}/src' || exit 1
                
            git config user.email "$GITHUB_ACTOR-{yyyy_mm_dd}@root.cern"
            git config user.name 'ROOT Continous Integration'
            
            git fetch origin {head_ref}:{head_ref} || exit 2
            git checkout -B {head_ref}  origin/{base_ref}|| exit 3
            
            git rebase {base_ref} || exit 5
        """, shell_log)

        if result != 0:
            die(result, "Rebase failed", shell_log)

        # Rebuild after rebase
        result, shell_log = subprocess_with_log(
            f"cmake --build '{workdir}/build' --config '{buildtype}' --parallel '{num_cores}'",
            shell_log
        )

        if result != 0:
            die(result, "Build step after rebase failed", shell_log)



    print(f"\nRebase and build of {head_ref} onto {base_ref} successful!")
    print("Archiving build artifacts to run tests in a new workflow")
    try:
        test_archive = "test" + yyyy_mm_dd + ".tar.gz"
        with tarfile.open(name = f"{workdir}/test-{test_archive}",
                          mode = "x:gz",
                          compresslevel = archive_compress_level) as targz:
            targz.add("src")
            targz.add("build")

        upload_file(
            connection=connection,
            container=CONTAINER,
            name=f"to-test/{head_ref}-on-{base_ref}/{prefix}/{test_archive}",
            path=f"{workdir}/{new_archive}"
        )
    except tarfile.TarError as err:
        print_warning("could not tar artifacts: ", {err})
    except Exception as err:
        print_warning("failed to archive/upload artifacts: ", {err})


if __name__ == "__main__":
    main()
