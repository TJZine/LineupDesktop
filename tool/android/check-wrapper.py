#!/usr/bin/env python3
"""Verify the committed Gradle 9.5.0 wrapper against upstream release bytes."""
import hashlib
from pathlib import Path
import sys

# gradlew scripts from gradle/gradle v9.5.0. JAR digest is published at
# https://services.gradle.org/distributions/gradle-9.5.0-wrapper.jar.sha256
HASHES = {
    'gradlew': '45bda8deaef01b732f07bd317f962a736e349c6faa6662829bc0f41293b51212',
    'gradlew.bat': '9e62ee9a1c6eb7cecc90e55acc3ff09a1631ccfe3edddf180538a1e42b1532dc',
    # Project distribution URL/checksum pin, including all properties bytes.
    'gradle/wrapper/gradle-wrapper.properties': '923c1393c10ac8563be1cac6f24633c0b8f0e50d8da9d89efac1504923f7e0f3',
    'gradle/wrapper/gradle-wrapper.jar': '497c8c2a7e5031f6aa847f88104aa80a93532ec32ee17bdb8d1d2f67a194a9c7',
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
    print('Official Gradle 9.5.0 wrapper bytes and distribution pin verified.')
