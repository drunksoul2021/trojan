import importlib.util
import pathlib
import socket
import threading
import time
import unittest

spec = importlib.util.spec_from_file_location('wait_database', pathlib.Path(__file__).parents[1] / 'scripts/wait-database.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class DatabaseReadinessTests(unittest.TestCase):
    def test_docker_proxy_without_backend_is_not_ready(self):
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            listener.listen()
            config = dict(enabled=True, server_addr='127.0.0.1', server_port=listener.getsockname()[1])
            attempts = []
            def backend():
                connection, _ = listener.accept()
                with connection:
                    attempts.append('proxy_closed')
                connection, _ = listener.accept()
                with connection:
                    attempts.append('mysql_greeting')
                    connection.sendall(b'\x20\x00')
                    time.sleep(0.01)
                    connection.sendall(b'\x00\x00\x0a')
            worker = threading.Thread(target=backend, daemon=True)
            worker.start()
            module.wait_database(config, timeout=2, retry_delay=0.01)
            worker.join(timeout=2)
            self.assertEqual(attempts, ['proxy_closed', 'mysql_greeting'])

    def test_unavailable_database_times_out(self):
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            port = listener.getsockname()[1]
        with self.assertRaisesRegex(RuntimeError, '数据库启动超时'):
            module.wait_database(dict(enabled=True, server_addr='127.0.0.1', server_port=port), timeout=0.05, retry_delay=0.01)

    def test_disabled_mysql_does_not_wait(self):
        module.wait_database(dict(enabled=False))
