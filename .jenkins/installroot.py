#!/usr/bin/env python3

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


def main():
    # openstack.enable_logging(debug=True)
    this = os.path.dirname(os.path.abspath(__file__))
    yyyymmdd = datetime.today().strftime('%Y-%m-%d')

    script_log = ""

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

    if os.path.exists(WORKDIR):
        shutil.rmtree(WORKDIR)
    os.makedirs(WORKDIR)
    os.chdir(WORKDIR)

    try:
        print("\nEstablishing s3 connection")
        connection = openstack.connect('envvars')

        print("\nDownloading")
        tar_path = download_latest(connection, CONTAINER, prefix)

        print("\nExtracting archive")
        with tarfile.open(tar_path) as tar:
            tar.extractall()
    except tarfile.TarError as err:
        print(f"Failed to untar, doing non-incremental build: {err}", sgr=33)
        incremental = False
    except Exception as err:
        print_fancy(f"Failed to download, doing non-incremental build: {err}", sgr=33)
        incremental = False

    if incremental:
        # Pull changes from git
        result, script_log = subprocess_with_log(f"""
            cd {WORKDIR}/src \
                || return 3

            git fetch \
                || return 1

            test "$(git rev-parse HEAD)" = "$(git rev-parse '@{{u}}')" \
                && return 2

            git merge FETCH_HEAD \
                || return 1
        """, script_log)

        if result == 1:
            print("Failed to git pull, doing non-incremental build")
            incremental = False
        elif result == 2:
            print("Files are unchanged since last build, exiting")
            exit(0)
        elif result == 3:
            print(f"could not cd {WORKDIR}/src, doing non-incremental build")
            incremental = False

    # Clone and run generation step on non-incrementals
    if not incremental:
        result, script_log = subprocess_with_log(f"""
            mkdir -p {WORKDIR}/build
            mkdir -p {WORKDIR}/install

            git clone -b {branch} \
                      --single-branch \
                      --depth 1 \
                      https://github.com/root-project/root.git \
                      {WORKDIR}/src
        """, script_log)

        if result != 0:
            die(result, "Could not clone from git", script_log)

        result, script_log = subprocess_with_log(f"""
            cmake -S {WORKDIR}/src \
                  -B {WORKDIR}/build \
                  -DCMAKE_INSTALL_PREFIX={WORKDIR}/install \
                    {options}
        """, script_log)

        if result != 0:
            die(result, "Failed cmake generation step", script_log)

    # Build ROOT
    result, script_log = subprocess_with_log(f"""
        cmake --build {WORKDIR}/build \
              --target install \
              -- -j"$(getconf _NPROCESSORS_ONLN)"
    """, script_log)

    if result != 0:
        die(result, "Build step failed", script_log)

    print("Archiving build artifacts")
    new_archive = f"{yyyymmdd}.tar.gz"
    try:
        with tarfile.open(f"{WORKDIR}/{new_archive}", "x:gz") as targz:
            targz.add(f"{WORKDIR}/src")
            targz.add(f"{WORKDIR}/install")
            targz.add(f"{WORKDIR}/build")
    except tarfile.TarError as err:
        print_fancy(f"Could not tar artifacts: {err}", sgr=33)
    else:
        try:
            upload_file(
                connection=connection,
                container=CONTAINER,
                name=f"{prefix}/{new_archive}",
                path=f"{WORKDIR}/{new_archive}"
            )
        except Exception as err:
            print_fancy(f"Uploading build artifacts failed: {err}", sgr=33)

    print_fancy("Script to replicate log:\n")
    print(script_log)


def print_fancy(*values, sgr=1) -> None:
    """prints message using select graphic rendition, defaults to bold text
       https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_(Select_Graphic_Rendition)_parameters"""

    print(f"\033[{sgr}m", end='')
    print(*values, end='')
    print("\033[0m")


def subprocess_with_log(command: str, log="", debug=True) -> Tuple[int, str]:
    """Runs <command> in shell and appends <command> to log"""

    if debug:
        print_fancy(textwrap.dedent(command))
        start = time.time()

    print("\033[0m", end='')
    result = subprocess.run(command, shell=True, check=False)

    if debug:
        elapsed = time.time() - start
        print_fancy(f"\nFinished expression in {elapsed}\n", sgr=3)

    return (result.returncode,
            log + '\n' + textwrap.dedent(command))


def die(code: int, msg: str, log: str = "") -> None:
    """prints error code, message and exits"""
    print(f"Fatal error ({code}): {msg}")

    if log != "":
        print_fancy("To replicate build locally:\n", log, sgr=31)

    sys.exit(code)


def load_config(filename) -> dict:
    """Loads cmake options from a file to a dictionary"""

    options = {}

    try:
        file = open(filename, 'r', encoding='utf-8')
    except OSError as err:
        print(f"Warning: couldn't load {filename}: {err.strerror}")
    else:
        with file:
            for line in file:
                if line == '' or '=' not in line:
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

    return ' '.join(output)


def upload_file(connection, container: str, name: str, path: str) -> None:
    """Uploads file to s3 object storage."""

    print(f"Attempting to upload {path} to {name}")

    if not os.path.exists(path):
        raise Exception(f"No such file: {path}")

    connection.create_object(container, name, path)

    print(f"Successfully uploaded to {name}")


def download_file(connection, container: str, name: str, destination: str) -> None:
    """Downloads a file from s3 object storage"""

    print(f"\nAttempting to download {name} to {destination}")

    if not os.path.exists(os.path.dirname(destination)):
        os.makedirs(os.path.dirname(destination))

    with open(destination, 'wb') as file:
        connection.get_object(container, name, outfile=file)


def download_latest(connection, container: str, prefix: str) -> str:
    """Downloads latest build artifact tar starting with <prefix>
       and returns its path.

       Outputs a link to the file to stdout"""

    objects = connection.list_objects(container, prefix=prefix)

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


if __name__ == "__main__":
    main()
