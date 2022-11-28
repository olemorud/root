#!/usr/bin/env python

"""Script to download and build ROOT"""

from datetime import datetime
from hashlib import sha1
from typing import Dict, Tuple
import os
import shutil
import subprocess
import sys
import tarfile
import textwrap
import time
import openstack


WORKDIR = "/tmp/workspace"
CONTAINER = "ROOT-build-artifacts"


def print_bold(*values) -> None:
    """prints message in bold"""
    print("\033[1m")
    print(*values)
    print("\033[22m")


def subprocess_with_log(command: str, log="", debug=True) -> Tuple[int, str]:
    """Runs <command> in shell and appends <command> to log"""

    if debug:
        print_bold(textwrap.dedent(command))
        start = time.time()

    result = subprocess.run(command, shell=True, check=False)

    if debug:
        elapsed = time.time() - start
        print_bold(f"\nFinished expression in {elapsed}\n")

    return (result.returncode,
            log + '\n' + textwrap.dedent(command))


def fail(code: int, msg: str, log: str = "") -> None:
    """prints error code, message and exits"""
    print(f"Fatal error ({code}): {msg}")

    if log != "":
        print("To replicate build locally:\n", log)

    sys.exit(code)


def load_config(filename) -> dict:
    """Loads cmake options from a file to a dictionary"""

    options = {}

    try:
        file = open(filename, 'r', encoding='utf-8')
    except OSError as err:
        print(f"Couldn't read {filename}: {err.strerror}")
    else:
        with file:
            for line in file:
                if line == "" or "=" not in line:
                    continue

                key, val = line.rstrip().split('=')
                options[key] = val

    return options


def options_from_dict(config: Dict[str, str]) -> str:
    """Converts a dictionary of build options to string.
       The output is sorted alphanumerically.

       example: {"builtin_xrootd"="on", "alien"="on"}
                 -> '"-Dalien=on" -Dbuiltin_xrootd=on"'
    """

    if not config:
        return ''

    output = []

    for key, value in config.items():
        output.append(f'"-D{key}={value}" ')

    output.sort()

    return " ".join(output)


def upload_to_s3(connection, container: str, name: str, path: str) -> None:
    """Uploads file to s3 object storage."""

    print(f"Attempting to upload {path} to {name}")

    if not os.path.exists(path):
        raise Exception(f"No such file: {path}")

    try:
        connection.create_object(container, name, path)
    except Exception as err:
        raise err
    
    print(f"Successfully uploaded to {name}")


def download_file(connection, container: str, name: str, destination: str) -> None:
    """Downloads a file from s3 object storage"""

    print(f"Attempting to download {name} to {destination}")

    try:
        if not os.path.exists(os.path.dirname(destination)):
            os.makedirs(os.path.dirname(destination))

        with open(destination, 'wb') as file:
            connection.get_object(container, name, outfile=file)
    except Exception as err:
        raise err


def download_latest(connection, container: str, prefix: str) -> str:
    """Downloads latest build artifact tar starting with <prefix>
       and returns its path.

       Outputs a link to the file to stdout"""

    try:
        objects = connection.list_objects(container, prefix=prefix)
    except openstack.exceptions.OpenStackCloudException as err:
        raise err

    if not objects:
        raise Exception(f"No object found with prefix: {prefix}")

    artifacts = [obj.name for obj in objects]
    artifacts.sort()
    latest = artifacts[-1]

    destination = f"{WORKDIR}/{latest}.tar.gz"

    try:
        download_file(connection, container, latest, destination)
    except Exception as err:
        raise Exception(f"Failed to download {latest}: {err}") from err

    return destination


def main():
    # openstack.enable_logging(debug=True)
    this = os.path.dirname(os.path.abspath(__file__))
    yyyymmdd = datetime.today().strftime('%Y-%m-%d')

    if os.path.exists(WORKDIR):
        shutil.rmtree(WORKDIR)

    os.makedirs(WORKDIR)
    os.chdir(WORKDIR)

    log = ""

    platform = os.environ['PLATFORM']
    branch = os.environ['BRANCH']
    config = os.environ['CONFIG']
    incremental = os.environ['INCREMENTAL'].lower() in ['true', 'yes', 'on']

    options = options_from_dict({
        **load_config(f'{this}/buildconfig/global.txt'),
        **load_config(f'{this}/buildconfig/{platform}.txt')  # has precedence
    })

    option_hash = sha1(options.encode('utf-8')).hexdigest()
    prefix = f'{platform}/{branch}/{config}/{option_hash}'

    try:
        connection = openstack.connect(cloud='envvars')
        tar_path = download_latest(connection, CONTAINER, prefix)
        with tarfile.open(tar_path) as tar:
            tar.extractAll()
    except openstack.exceptions.OpenStackCloudException as err:
        print(
            f"Could not download previous artifacts, doing non-incremental build: {err}")
        incremental = False
    except tarfile.TarError:
        print("Failed to untar")
    except Exception as err:
        print(
            f"Could not download previous artifacts, doing non-incremental build: {err}")
        incremental = False

    if incremental:
        # Pull changes from git
        result, log = subprocess_with_log(f"""
            cd {WORKDIR}/src \
                || return 3

            git fetch \
                || return 1

            test "$(git rev-parse HEAD)" = "$(git rev-parse '@{{u}}')" \
                && return 2

            git merge FETCH_HEAD \
                || return 1
        """, log)

        if result == 1:
            print("Failed to git pull, doing non-incremental build")
            incremental = False
        elif result == 2:
            print("Files are unchanged since last build, exiting")
            exit(0)
        elif result == 3:
            print(f"could not cd {WORKDIR}/src")

    if not incremental:
        # Clone from git
        result, log = subprocess_with_log(f"""
            mkdir -p {WORKDIR}/build
            mkdir -p {WORKDIR}/install

            git clone -b {branch} \
                      --single-branch \
                      --depth 1 \
                      https://github.com/root-project/root.git \
                      {WORKDIR}/src
        """, log)

        if result != 0:
            fail(result, "Could not clone from git", log)

        # Generate with cmake
        result, log = subprocess_with_log(f"""
            cmake -S {WORKDIR}/src \
                  -B {WORKDIR}/build \
                  -DCMAKE_INSTALL_PREFIX={WORKDIR}/install \
                    {options}
        """, log)

        if result != 0:
            fail(result, "Failed cmake generation step", log)

    # Build with cmake
    result, log = subprocess_with_log(f"""
        cmake --build {WORKDIR}/build \
              --target install \
              -- -j"$(getconf _NPROCESSORS_ONLN)"
    """, log)

    if result != 0:
        fail(result, "Build failed", log)

    try:
        print("Archiving build artifacts...")
        new_archive = f"{yyyymmdd}.tar.gz"

        with tarfile.open(f"{WORKDIR}/{new_archive}", "x:gz") as targz:
            targz.add(f"{WORKDIR}/src")
            targz.add(f"{WORKDIR}/install")
            targz.add(f"{WORKDIR}/build")
    except tarfile.TarError as err:
        print(f"Could not tar artifacts: {err}")

    try:
        upload_to_s3(connection, CONTAINER,
                     f"{prefix}/{new_archive}", f"{WORKDIR}/{new_archive}")
    except Exception as err:
        print("Uploading build artifacts failed", err)

    print_bold("Script to replicate log:\n")
    print(log)


if __name__ == "__main__":
    main()
