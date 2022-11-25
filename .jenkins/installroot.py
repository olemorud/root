
from hashlib import sha1, hexdigest
import s3
import subprocess


# Runs a shell command and appends to log, does not support pipes
def unsafeShellWithLog(command: str, log: str) -> (subprocess.CompletedProcess, str):
    result = subprocess.run(command, shell=True)

    return result, f'{log}\n{command}'


def loadConfig(filename) -> dict:
    with open(filename, 'r') as f:
        for line in f:
            key, val = line,split()
            config[key] = val


def dictToBuildOptions(config: dict) > str:
    if not config:
        return ''

    output = ''

    for key, value in config.items():
        output += f'"-D{key}={value}" '
    
    return output


def s3Filedir(platform: str, branch: str, config: str, buildoptions: str) -> str:
    optionHash = sha1(buildoptions).hexdigest()

    return f'{platform}/{branch}/{config}/{optionHash}/'


def main():
    config: dict = loadConfig('global.txt') | loadConfig(f'{platform}.txt')
    cmakeOptions: str = dictToBuildOptions(config)
    
    with open('rc.yaml', 'r') as f:
        s3config = yaml.load(f)
    
    connection = s3.S3Connection(**config['s3'])
    storage = s3.Storage(connection)

    
