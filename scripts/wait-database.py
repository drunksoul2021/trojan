#!/usr/bin/env python3
"""Wait for a MySQL protocol greeting, rather than just Docker's proxy port."""
import json
import socket
import sys
import time


def wait_database(mysql, timeout=120, retry_delay=1):
    if not mysql.get('enabled', False):
        return
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            remaining = deadline - time.monotonic()
            with socket.create_connection((mysql['server_addr'], int(mysql['server_port'])), timeout=min(2, max(0.01, remaining))) as connection:
                greeting = b''
                while len(greeting) < 5:
                    chunk = connection.recv(5 - len(greeting))
                    if not chunk:
                        break
                    greeting += chunk
                if len(greeting) == 5 and greeting[4] == 10:
                    return
        except OSError:
            pass
        time.sleep(min(retry_delay, max(0, deadline - time.monotonic())))
    raise RuntimeError('数据库启动超时，请检查 Docker 和 trojan-mariadb 容器日志。')


if __name__ == '__main__':
    try:
        with open('/usr/local/etc/trojan/config.json') as source:
            wait_database(json.load(source)['mysql'])
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
