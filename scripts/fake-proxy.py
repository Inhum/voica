#!/usr/bin/env python3
"""Поддельный прокси для проверки §9.5 без корпоративной сети.

Зачем: поведение приложения за прокси иначе не проверить — дома прокси нет, а лезть в
системные настройки сети ради теста нельзя. Заглушка поднимается за секунду и не требует
ничего, кроме python3.

    ./scripts/fake-proxy.py 407          # всегда требует авторизации (порт 18899)
    ./scripts/fake-proxy.py auth 18899   # пускает по voica:secret, туннелирует CONNECT

Приложение направляется на неё переменной окружения, системные настройки не трогаются:

    VOICA_PROXY=127.0.0.1:18899 ./build/Voica.app/Contents/MacOS/Voica

Что проверять: диктовка, кнопка Test у ключа, проверка обновлений и скачивание модели должны
показывать ОДНО сообщение с адресом прокси, а не сырую системную ошибку; на вкладке Network —
строка «Сейчас используется». В окне заглушки при этом видно CONNECT и ответ 407.

⚠️ Живая проверка этой заглушкой поймала три дефекта, которых не было видно в юнит-тестах:
диагностика писала «напрямую» при заданном прокси, детектор ошибки смотрел не в тот домен
(kCFErrorDomainCFNetwork, а не NSURLErrorDomain), и сообщение об ошибке было человеческим
только в диктовке, а в трёх других местах — сырым.
"""

import base64, socket, sys, threading

MODE = sys.argv[1] if len(sys.argv) > 1 else "407"
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8899
OK = "Basic " + base64.b64encode(b"voica:secret").decode()

def pump(a, b):
    try:
        while True:
            data = a.recv(65536)
            if not data: break
            b.sendall(data)
    except OSError: pass
    finally:
        for s in (a, b):
            try: s.close()
            except OSError: pass

def handle(conn, addr):
    try:
        conn.settimeout(10)
        req = b""
        while b"\r\n\r\n" not in req:
            chunk = conn.recv(4096)
            if not chunk: return
            req += chunk
        head = req.split(b"\r\n\r\n")[0].decode("latin-1")
        first = head.split("\r\n")[0]
        auth = next((l.split(":", 1)[1].strip() for l in head.split("\r\n")
                     if l.lower().startswith("proxy-authorization:")), None)
        print(f"[прокси] {first} | Proxy-Authorization: {auth or 'нет'}", flush=True)

        if MODE == "407" or auth != OK:
            conn.sendall(b"HTTP/1.1 407 Proxy Authentication Required\r\n"
                         b'Proxy-Authenticate: Basic realm="voica-test"\r\n'
                         b"Content-Length: 0\r\nConnection: close\r\n\r\n")
            print("[прокси] ответил 407", flush=True)
            return
        if first.startswith("CONNECT"):
            hostport = first.split()[1]
            host, _, port = hostport.partition(":")
            up = socket.create_connection((host, int(port or 443)), timeout=10)
            conn.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            print(f"[прокси] туннель на {hostport} открыт", flush=True)
            threading.Thread(target=pump, args=(conn, up), daemon=True).start()
            pump(up, conn)
            return
        conn.sendall(b"HTTP/1.1 501 Not Implemented\r\n\r\n")
    except Exception as e:
        print(f"[прокси] ошибка: {e}", flush=True)
    finally:
        try: conn.close()
        except OSError: pass

srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", PORT))
srv.listen(16)
print(f"[прокси] режим {MODE}, слушаю 127.0.0.1:{PORT}", flush=True)
while True:
    c, a = srv.accept()
    threading.Thread(target=handle, args=(c, a), daemon=True).start()
