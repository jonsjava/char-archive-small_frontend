#!/usr/bin/env python3
"""Poll the import/ folder for new character cards and import them."""

import os
import time

from card_import import IMPORT_DIR, scan_import_dir

INTERVAL = max(int(os.environ.get('IMPORT_SCAN_INTERVAL', '60')), 5)


def main():
    print(f'Import watcher started — scanning {IMPORT_DIR} every {INTERVAL}s', flush=True)
    while True:
        try:
            results = scan_import_dir()
            if results:
                print(f'Processed {len(results)} file(s)', flush=True)
        except Exception as exc:
            print(f'Scan error: {exc}', flush=True)
        time.sleep(INTERVAL)


if __name__ == '__main__':
    main()
