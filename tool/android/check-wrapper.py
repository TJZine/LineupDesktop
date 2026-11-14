#!/usr/bin/env python3
"""Verify the committed Gradle 9.3.1 wrapper against upstream release bytes."""
import hashlib
from pathlib import Path
import sys

# gradlew scripts from gradle/gradle v9.3.1. JAR digest is published at
# https://services.gradle.org/distributions/gradle-9.3.1-wrapper.jar.sha256
HASHES = {
    'gradlew': 'b2fe376b143a459ba5d0bd290dc89beed5399fc6d159cd1214bd642ea94bcf07',
    'gradlew.bat': '9386e790d58b9368ca8e034536a5baa688643d51cb37bfa462503d36fd0291a6',
    # Project distribution URL/checksum pin, including all properties bytes.
    'gradle/wrapper/gradle-wrapper.properties': '67ce033cdd43a5af2686f7ecae3b527d70041824260d6f15a7c2c3a100a8d1c2',
    'gradle/wrapper/gradle-wrapper.jar': 'b3a875ddc1f044746e1b1a55f645584505f4a10438c1afea9f15e92a7c42ec13',
}

def check(root):
    for name, expected in HASHES.items():
        if hashlib.sha256((root / name).read_bytes()).hexdigest() != expected:
            raise ValueError(f'Official Gradle wrapper mismatch: {name}')

if __name__ == '__main__':
    try:
        check(Path(__file__).resolve().parents[2] / 'android')
    except (ValueError, OSError) as error:
        sys.exit(str(error))
    print('Official Gradle 9.3.1 wrapper bytes and distribution pin verified.')
