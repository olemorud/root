#!/usr/bin/env python3

# pylint: disable=broad-except,missing-function-docstring,line-too-long

"""This mainly functions as a shell script, but python is used for its
   superior control flow. An important requirement of the CI is easily
   reproducible builds, therefore a wrapper is made for running shell
   commands so that they are also logged.

   The log is printed when build fails/succeeds and needs to perfectly
   reproduce the build when pasted into a shell. Therefore all file system
   modifying code not executed from shell needs a shell equivalent
   explicitly appended to the shell log.
      e.g. `os.chdir(x)` requires `cd x` to be appended to the shell log  """

import argparse
import datetime
import os
import shutil
import tarfile
from hashlib import sha1

import openstack
from build_utils import (
    cmake_options_from_dict,
    die,
    download_latest,
    load_config,
    output_group,
    print_shell_log,
    subprocess_with_log,
    upload_file,
    warning,
)

S3CONTAINER = 'ROOT-build-artifacts'  # Used for uploads
S3URL = 'https://s3.cern.ch/swift/v1/' + S3CONTAINER  # Used for downloads
WORKDIR = '/tmp/workspace' if os.name != 'nt' else 'C:/ROOT-CI'
CONNECTION = openstack.connect(cloud='envvars') if os.getenv('OS_REGION_NAME') else None
COMPRESSIONLEVEL = 6 if os.name != 'nt' else 1

def main():
    # openstack.enable_logging(debug=True)
    shell_log = ''
    yyyy_mm_dd = datetime.datetime.today().strftime('%Y-%m-%d')
    this_script_dir = os.path.dirname(os.path.abspath(__file__))

    parser = argparse.ArgumentParser()
    parser.add_argument("--platform",    default="centos8", help="Platform to build on")
    parser.add_argument("--incremental", default=False,     help="Do incremental build")
    parser.add_argument("--buildtype",   default="Release", help="Release, Debug or RelWithDebInfo")
    parser.add_argument("--base_ref",    default=None,      help="Ref to target branch")
    parser.add_argument("--head_ref",    default=None,      help="Ref to feature branch")
    parser.add_argument("--repository",  default="https://github.com/root-project/root.git",
                        help="url to repository")

    args = parser.parse_args()

    platform    = args.platform
    incremental = args.incremental.lower() in ('yes', 'true', '1', 'on')
    buildtype   = args.buildtype
    base_ref    = args.base_ref
    head_ref    = args.head_ref
    repository  = args.repository

    if not base_ref:
        die(os.EX_USAGE, "base_ref not specified")

    if not head_ref or (head_ref == base_ref):
        warning("head_ref same as base_ref, assuming non-PR build")
        pull_request = False
    else:
        pull_request = True

    if os.name == 'nt':
        # windows
        os.environ['COMSPEC'] = 'powershell.exe'
        result, shell_log = subprocess_with_log(f"""
            Remove-Item -Recurse -Force -Path {WORKDIR}
            New-Item -Force -Type directory -Path {WORKDIR}
            Set-Location -LiteralPath {WORKDIR}
        """, shell_log)
    else:
        # mac/linux/POSIX
        result, shell_log = subprocess_with_log(f"""
            mkdir -p {WORKDIR}
            rm -rf {WORKDIR}/*
            cd {WORKDIR}
        """, shell_log)

    if result != 0:
        die(result, "Failed to clean up previous artifacts", shell_log)

    os.chdir(WORKDIR)

    # Load CMake options from file
    options_dict = {
        **load_config(f'{this_script_dir}/buildconfig/global.txt'),
        # below has precedence
        **load_config(f'{this_script_dir}/buildconfig/{platform}.txt')
    }
    options = cmake_options_from_dict(options_dict)

    option_hash = sha1(options.encode('utf-8')).hexdigest()
    obj_prefix = f'{platform}/{base_ref}/{buildtype}/{option_hash}'

    # Make testing of CI in forks not impact artifacts
    if 'root-project/root' not in repository:
        obj_prefix = f"ci-testing/{repository.split('/')[-2]}/" + obj_prefix

    if incremental:
        print("Attempting to download")
        try:
            shell_log += download_and_extract(obj_prefix, shell_log)
        except Exception as err:
            warning(f'Failed to download: {err}')
            incremental = False

    shell_log = pull(repository, base_ref, incremental, shell_log)

    extra_ctest_flags = ""

    if os.name == "nt":
        extra_ctest_flags += "-C " + buildtype

    testing: bool = options_dict['testing'].lower() == "on" and options_dict['roottest'].lower() == "on"

    if pull_request:
        shell_log = rebase(base_ref, head_ref, WORKDIR, shell_log)

    shell_log = build(options, buildtype, shell_log)

    if testing:
        shell_log = test(shell_log, extra_ctest_flags)

    archive_and_upload(yyyy_mm_dd, obj_prefix)

    print_shell_log(shell_log)


@output_group("Pull/clone branch")
def pull(repository:str, branch: str, incremental: bool, shell_log: str):
    attempts = 5
    returncode = 1

    while attempts > 0 and returncode != 0:
        attempts -= 1

        if not incremental:
            returncode, shell_log = subprocess_with_log(f"""
                git clone --branch {branch} --single-branch {repository} "{WORKDIR}/src"
            """, shell_log)
        else:
            returncode, shell_log = subprocess_with_log(f"""
                cd '{WORKDIR}/src'      || exit 1
                git checkout {branch}   || exit 2
                git fetch               || exit 3
                git reset --hard @{{u}} || exit 4
            """, shell_log)

    if returncode != 0:
        die(returncode, f"Failed to pull {branch}", shell_log)
    
    return shell_log


@output_group("Download previous build artifacts")
def download_and_extract(obj_prefix: str, shell_log: str):
    print("Attempting incremental build")

    try:
        tar_path, shell_log = download_latest(S3URL, obj_prefix, WORKDIR, shell_log)

        print(f"\nExtracting archive {tar_path}")

        with tarfile.open(tar_path) as tar:
            tar.extractall()

        shell_log += f'\ntar -xf {tar_path}\n'

    except Exception as err:
        warning("failed to download/extract:", err)
        shutil.rmtree(f'{WORKDIR}/src', ignore_errors=True)
        shutil.rmtree(f'{WORKDIR}/build', ignore_errors=True)
        raise err
    
    return shell_log


@output_group("Run tests")
def test(shell_log: str, extra_ctest_flags: str) -> str:
    result, shell_log = subprocess_with_log(f"""
        cd '{workdir}/build'
        ctest -j{os.cpu_count()} --output-junit TestResults.xml {extra_ctest_flags}
    """, shell_log)
    
    if result != 0:
        warning("Some tests failed")
    
    return shell_log


@output_group("Archive and upload")
def archive_and_upload(archive_name, prefix):
    new_archive = f"{archive_name}.tar.gz"

    with tarfile.open(f"{WORKDIR}/{new_archive}", "x:gz", compresslevel=COMPRESSIONLEVEL) as targz:
        targz.add("src")
        targz.add("build")

    upload_file(
        connection=CONNECTION,
        container=S3CONTAINER,
        dest_object=f"{prefix}/{new_archive}",
        src_file=f"{WORKDIR}/{new_archive}"
    )


@output_group("Build")
def build(options, buildtype, shell_log):
    if not os.path.exists(f'{WORKDIR}/build/CMakeCache.txt'):
        result, shell_log = subprocess_with_log(f"""
            mkdir -p '{WORKDIR}/build'
            cmake -S '{WORKDIR}/src' -B '{WORKDIR}/build' {options} \\
                -DCMAKE_BUILD_TYPE={buildtype}
        """, shell_log)

        if result != 0:
            die(result, "Failed cmake generation step", shell_log)

    result, shell_log = subprocess_with_log(f"""
        mkdir '{WORKDIR}/build'
        cmake --build '{WORKDIR}/build' --config '{buildtype}' --parallel '{os.cpu_count()}'
    """, shell_log)

    if result != 0:
        die(result, "Failed to build", shell_log)
    
    return shell_log


@output_group("Rebase")
def rebase(base_ref, head_ref, shell_log) -> str:
    """rebases head_ref on base_ref, returns shell log"""

    # This mental gymnastics is neccessary because the cmake build fetches 
    # roottest based on the current branch of ROOT
    result, shell_log = subprocess_with_log(f"""
        cd '{WORKDIR}/src' || exit 1
        
        git config user.email "rootci@root.cern"
        git config user.name 'ROOT Continous Integration'
        
        git fetch origin {head_ref}:__tmp || exit 2
        git checkout __tmp || exit 3
        
        git rebase {base_ref} || exit 5
        git checkout {base_ref} || exit 6
        git reset --hard __tmp || exit 7
    """, shell_log)

    if result != 0:
        die(result, "Rebase failed", shell_log)

    return shell_log


if __name__ == "__main__":
    main()
