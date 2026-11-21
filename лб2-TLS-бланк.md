<!--
Бланк звіту до лабораторної роботи «TLS та сертифікати».
Скопіювати цей файл у власний публічний репозиторій звіту як README.md і заповнити.
Вивід команд вставляти текстом у блоки коду, а не знімками екрана.
Порожні поля не допускаються: якщо щось не вдалося, записати, що саме і чому.
-->

# Лабораторна робота 2. TLS та сертифікати

| Поле | Значення |
|---|---|
| ПІБ | Тіщенко Микола Сергійович |
| Група | ЗКБЗІ 21 |
| Ідентифікатор | `se-201-11` |
| Дата виконання | 20.11.2026 |
| Середовище | GitHub Codespaces (форк `Nekretos/opism-lab-TLS`) |
| Версія OpenSSL | `OpenSSL 3.0.13 30 Jan 2024 (Library: OpenSSL 3.0.13 30 Jan 2024)` |

> Час у виводах — UTC (годинник стенда), за Києвом +2 год. Команди завдань 1–5 виконано скриптом `tls.sh` (лежить у форку стенда). Скрипт запускає кожну команду методички в контейнері `se-201-11` через `docker compose exec` з робочим каталогом `/lab/work` і пише вивід у `tlslog/`. Псевдоніми `acme-root` і `web-reload` у скрипті розгорнуто у відповідні команди з `/etc/profile.d/lab.sh`. Файли `t1-*.txt` і `t2-*.txt` збережено в `/lab/work` і скопійовано в `tlslog/work/` форку.

## Параметри варіанта

| Параметр | Значення |
|---|---|
| Віддалений сервер | `origin.se-201-11.lab` |
| Імена для сертифіката | `www.se-201-11.lab`, `portal.se-201-11.lab` |
| Ваш сервер (IP) | `10.53.1.1` |

Стенд під час роботи не перезапускався. Під час першого запуску `./up.sh` перевірка показала `FAIL ACME server https://ca.lab:14000/dir`, бо Pebble ще стартував. Повторна перевірка через 10 с: `OK ACME server https://ca.lab:14000/dir` і `OK se-201-11 dns=yes remote=yes nginx=yes netem=yes`.

## Завдання 1. HTTP і HTTPS у дампі трафіку

Вивід кроку 1.1:

```text
root@se-201-11:/lab/work# timeout 8 tcpdump -ni eth0 -A -s0 -l 'host 10.53.0.80 and tcp port 80' > t1-http.txt &
sleep 1; curl -s http://origin.se-201-11.lab/; wait
grep -a -E 'GET /|Host:|server: web' t1-http.txt
server: web
Host: origin.se-201-11.lab
SNI: 
protocol: HTTP/1.1 
client: 10.53.1.1
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on eth0, link-type EN10MB (Ethernet), snapshot length 262144 bytes
10 packets captured
10 packets received by filter
0 packets dropped by kernel
14:36:31.252543 IP 10.53.1.1.53484 > 10.53.0.80.80: Flags [P.], seq 1:84, ack 1, win 502, options [nop,nop,TS val 3355283745 ecr 2564790072], length 83: HTTP: GET / HTTP/1.1
...!...8GET / HTTP/1.1
Host: origin.se-201-11.lab
server: web
Host: origin.se-201-11.lab
```

Вивід кроку 1.2:

```text
root@se-201-11:/lab/work# timeout 8 tcpdump -ni eth0 -A -s0 -l 'host 10.53.0.80 and tcp port 443' > t1-https.txt &
sleep 1; curl -s --cacert $STAND_CA https://origin.se-201-11.lab/; wait
grep -a -c -E 'GET /|server: web' t1-https.txt
grep -a -o 'origin.se-201-11.lab' t1-https.txt | wc -l
server: web
Host: origin.se-201-11.lab
SNI: origin.se-201-11.lab
protocol: HTTP/2.0 TLSv1.3
client: 10.53.1.1
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on eth0, link-type EN10MB (Ethernet), snapshot length 262144 bytes
22 packets captured
22 packets received by filter
0 packets dropped by kernel
0
1
```

Додатково підраховано заголовок `Host` та ім'я сервера в обох дампах:

```text
root@se-201-11:/lab/work# grep -a -c 'Host:' t1-http.txt; grep -a -o 'origin.se-201-11.lab' t1-http.txt | wc -l; grep -a -c 'Host:' t1-https.txt
2
2
0
```

Тіла відповідей сервера відрізняються трьома рядками: для HTTP `SNI:` порожній і `protocol: HTTP/1.1`, для HTTPS `SNI: origin.se-201-11.lab` і `protocol: HTTP/2.0 TLSv1.3`. Рядки `server:`, `Host:` і `client:` однакові.

| Що шукали в дампі | HTTP | HTTPS |
|---|---|---|
| рядок запиту `GET /` | видно (`GET / HTTP/1.1`) | не видно |
| заголовок `Host` | видно (2 рядки: запит і тіло відповіді) | не видно (0) |
| тіло відповіді (`server: web`) | видно | не видно (`grep -c` = 0) |
| ім'я віддаленого сервера (кількість входжень) | 2 | 1 |

1. У якому повідомленні і в якому полі передається ім'я сервера, яке видно в дампі HTTPS?

   У першому повідомленні рукостискання ClientHello, у розширенні `server_name` (SNI, тип 0). ClientHello завжди передається відкрито, ще до домовленості про ключі, тому ім'я видно в дампі. Це єдине входження: заголовок `Host` і тіло відповіді йдуть уже зашифрованими.

2. Чому рядок `SNI:` у відповіді сервера порожній для HTTP і заповнений для HTTPS?

   SNI — розширення TLS, а не HTTP. У звичайному HTTP рукостискання TLS немає, тож клієнт нікуди не передає SNI, і змінна nginx `$ssl_server_name` порожня. Ім'я сервера тоді відоме лише із заголовка `Host`. У HTTPS клієнт передає ім'я в ClientHello, щоб сервер ще до шифрування міг вибрати потрібний сертифікат, і nginx показує його в рядку `SNI:`.

3. Рядок `protocol:` показує HTTP/1.1 для запиту по HTTP і HTTP/2.0 для запиту по HTTPS, хоча обидва запити виконано однією командою `curl` без додаткових ключів. Що визначило версію HTTP у другому випадку?

   Розширення ALPN у рукостисканні TLS. `curl` у ClientHello пропонує `h2` і `http/1.1`, сервер (nginx з `http2`) вибирає `h2` і повідомляє про це у своїй відповіді. Підтвердження — рядок `ALPN protocol: h2` у кроці 2.1. Для відкритого HTTP такого механізму немає, і `curl` без ключа `--http2` не пробує HTTP/2 (h2c), тому лишається HTTP/1.1.

## Завдання 2. Рукостискання по записах

Вивід кроку 2.1 (TLS 1.3):

```text
root@se-201-11:/lab/work# openssl s_client -connect origin.se-201-11.lab:443 -servername origin.se-201-11.lab -alpn h2,http/1.1 \
  -CAfile $STAND_CA -trace </dev/null > t2-13.txt 2>&1
grep -a -E '^(Sent|Received) Record|Content Type|^    [A-Z][A-Za-z]+, Length' t2-13.txt
grep -a -E '^(ALPN|New,)|Verify return' t2-13.txt
Sent Record
  Content Type = Handshake (22)
    ClientHello, Length=331
Received Record
  Content Type = Handshake (22)
    ServerHello, Length=118
Received Record
  Content Type = ChangeCipherSpec (20)
Received Record
  Content Type = ApplicationData (23)
  Inner Content Type = Handshake (22)
    EncryptedExtensions, Length=15
Received Record
  Content Type = ApplicationData (23)
  Inner Content Type = Handshake (22)
    Certificate, Length=991
Received Record
  Content Type = ApplicationData (23)
  Inner Content Type = Handshake (22)
    CertificateVerify, Length=75
Received Record
  Content Type = ApplicationData (23)
  Inner Content Type = Handshake (22)
    Finished, Length=48
Sent Record
  Content Type = ChangeCipherSpec (20)
Sent Record
  Content Type = ApplicationData (23)
  Inner Content Type = Handshake (22)
    Finished, Length=48
Sent Record
  Content Type = ApplicationData (23)
  Inner Content Type = Alert (21)
New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384
ALPN protocol: h2
Verify return code: 0 (ok)
```

Вивід кроку 2.2 (TLS 1.2):

```text
root@se-201-11:/lab/work# openssl s_client -connect origin.se-201-11.lab:443 -servername origin.se-201-11.lab -alpn h2,http/1.1 \
  -CAfile $STAND_CA -trace -tls1_2 </dev/null > t2-12.txt 2>&1
grep -a -E '^(Sent|Received) Record|Content Type|^    [A-Z][A-Za-z]+, Length' t2-12.txt
grep -a -E '^(ALPN|New,)|Verify return' t2-12.txt
Sent Record
  Content Type = Handshake (22)
    ClientHello, Length=226
Received Record
  Content Type = Handshake (22)
    ServerHello, Length=74
Received Record
  Content Type = Handshake (22)
    Certificate, Length=986
Received Record
  Content Type = Handshake (22)
    ServerKeyExchange, Length=111
Received Record
  Content Type = Handshake (22)
    ServerHelloDone, Length=0
Sent Record
  Content Type = Handshake (22)
    ClientKeyExchange, Length=33
Sent Record
  Content Type = ChangeCipherSpec (20)
Sent Record
  Content Type = Handshake (22)
    Finished, Length=12
Received Record
  Content Type = Handshake (22)
    NewSessionTicket, Length=230
Received Record
  Content Type = ChangeCipherSpec (20)
Received Record
  Content Type = Handshake (22)
    Finished, Length=12
Received Record
  Content Type = ApplicationData (23)
Sent Record
  Content Type = Alert (21)
New, TLSv1.2, Cipher is ECDHE-ECDSA-AES256-GCM-SHA384
ALPN protocol: h2
    Verify return code: 0 (ok)
```

<!-- Один рядок на кожен запис з виводу 2.1, у тому самому порядку. Напрям: К→С або С→К. -->

| № | Напрям | `Content Type` | `Inner Content Type` | Повідомлення | `Length` |
|---|---|---|---|---|---|
| 1 | К→С | Handshake (22) | — | ClientHello | 331 |
| 2 | С→К | Handshake (22) | — | ServerHello | 118 |
| 3 | С→К | ChangeCipherSpec (20) | — | ChangeCipherSpec (сумісність) | — |
| 4 | С→К | ApplicationData (23) | Handshake (22) | EncryptedExtensions | 15 |
| 5 | С→К | ApplicationData (23) | Handshake (22) | Certificate | 991 |
| 6 | С→К | ApplicationData (23) | Handshake (22) | CertificateVerify | 75 |
| 7 | С→К | ApplicationData (23) | Handshake (22) | Finished | 48 |
| 8 | К→С | ChangeCipherSpec (20) | — | ChangeCipherSpec (сумісність) | — |
| 9 | К→С | ApplicationData (23) | Handshake (22) | Finished | 48 |
| 10 | К→С | ApplicationData (23) | Alert (21) | Alert (close_notify під час закриття `s_client`) | — |

Вивід кроків 2.3 і 2.4:

```text
root@se-201-11:/lab/work# grep -a -A3 'extension_type=server_name' t2-13.txt | head -4
        extension_type=server_name(0), length=25
          0000 - 00 17 00 00 14 6f 72 69-67 69 6e 2e 73 65 2d   .....origin.se-
          000f - 32 30 31 2d 31 31 2e 6c-61 62                  201-11.lab
        extension_type=ec_point_formats(11), length=4

root@se-201-11:/lab/work# for v in 1.3 1.2; do
  timeout 6 tcpdump -ni eth0 -A -s0 -l 'host 10.53.0.80 and tcp port 443' > t2-dump-$v.txt &
  sleep 1; curl -s -o /dev/null --tlsv1.2 --tls-max $v --cacert $STAND_CA https://origin.se-201-11.lab/; wait
  echo "TLS $v: $(grep -a -c 'OPISM Stand Intermediate' t2-dump-$v.txt)"
done
TLS 1.3: 0
TLS 1.2: 2
```

| Показник | TLS 1.3 | TLS 1.2 |
|---|---|---|
| Довжина ClientHello, байт | 331 | 226 |
| Номер першого запису, тип якого спостерігач не бачить | 4 (EncryptedExtensions, зовні `ApplicationData`) | немає: у TLS 1.2 тип кожного запису відкритий. Першим зашифровано вміст запису 8 (Finished клієнта), але його тип `Handshake (22)` видно |
| Кількість RTT від ClientHello до першого HTTP-запиту | 1 | 2 |
| Чи видно сертифікат у дампі (результат 2.4) | ні (0 входжень) | так (2 входження) |
| Обраний протокол ALPN | `h2` | `h2` |

1. За якими рядками виводу 2.1 визначено, з якого запису починається шифрування? Що бачить спостерігач замість типу кожного наступного запису?

   Шифрування починається із запису 4: у нього вперше з'являється рядок `Inner Content Type = Handshake (22)`, а зовнішній тип `Content Type = ApplicationData (23)`. `-trace` показує внутрішній тип, бо `openssl` сам розшифровує запис. Записи 1–3 мають лише зовнішній тип (`Handshake`, `ChangeCipherSpec`), тобто передаються відкрито. Спостерігач замість справжнього типу кожного наступного запису (EncryptedExtensions, Certificate, CertificateVerify, Finished, Alert) бачить лише `ApplicationData (23)` і довжину. Справжній тип лежить усередині зашифрованої частини (RFC 8446, п. 5.2).

2. Чому ClientHello у TLS 1.3 довший, ніж у TLS 1.2? Назвіть розширення, яке за рахунок цього скорочує рукостискання на один RTT.

   У TLS 1.3 клієнт одразу додає розширення, яких у TLS 1.2 немає: `supported_versions` (length=5), `psk_key_exchange_modes` (length=2) і насамперед `key_share` (length=38) — свою частину ключа ECDHE для обраної групи. Крім того, список шифрів включає набори TLS 1.3. Розширення **`key_share`** дозволяє серверу обчислити спільний секрет уже з ClientHello і відповісти зашифрованим рукостисканням одразу. Окремий обмін ключами (ServerKeyExchange / ClientKeyExchange у TLS 1.2) не потрібен, і рукостискання займає 1 RTT замість 2.

3. Довжина розширення `server_name` у виводі 2.3 становить 17 байт для імені з 12 символів. З яких частин складається це значення і яким воно буде для вашого імені?

   Значення складається з 2 байт довжини списку імен, 1 байта типу імені (`00` = host_name), 2 байт довжини імені й самого імені: `2 + 1 + 2 + n`. Для 12 символів: `5 + 12 = 17`. Моє ім'я `origin.se-201-11.lab` має 20 символів: `5 + 20 = 25`. Це збігається з виводом `length=25`, а в байтах видно `00 17` (список = 23), `00` (тип), `00 14` (ім'я = 20).

4. Навіщо в TLS 1.3 передається запис ChangeCipherSpec, якщо в рукостисканні він нічого не змінює?

   Це режим сумісності з проміжними пристроями (middlebox compatibility mode, RFC 8446, додаток D.4). Частина мережевих пристроїв (фаєрволи, DPI) знає лише TLS 1.2 і обриває з'єднання, якщо після ServerHello не бачить ChangeCipherSpec. Фіктивний CCS (записи 3 і 8) робить рукостискання TLS 1.3 схожим на відновлення сесії TLS 1.2, і такі пристрої пропускають його. Учасники з'єднання цей запис просто ігнорують.

## Завдання 3. Сертифікат для власного сервера

Вивід кроків 3.1 і 3.2:

```text
root@se-201-11:/lab/work# acme-root
openssl x509 -in /lab/tls/acme-root.crt -noout -subject -dates
збережено /lab/tls/acme-root.crt
subject=CN = Pebble Root CA 0932b3
notBefore=Nov 20 14:33:46 2026 GMT
notAfter=Nov 20 14:33:46 2056 GMT

root@se-201-11:/lab/work# curl -sS --cacert /lab/tls/acme-root.crt https://www.se-201-11.lab/
curl: (60) SSL certificate problem: self-signed certificate
More details here: https://curl.se/docs/sslcerts.html

curl failed to verify the legitimacy of the server and therefore could not
establish a secure connection to it. To learn more about this situation and
how to fix it, please visit the web page mentioned above.
```

Вивід кроку 3.3 (останні рядки `lego` і рядки журналу nginx):

```text
2026/11/20 14:36:59 [INFO] [www.se-201-11.lab, portal.se-201-11.lab] acme: Obtaining SAN certificate
2026/11/20 14:37:00 [INFO] [www.se-201-11.lab] AuthURL: https://ca.lab:14000/authZ/HPctKJIdI4e8vD2EA3SmHNztklw2R1xjKNYGxd8We68
2026/11/20 14:37:00 [INFO] [portal.se-201-11.lab] AuthURL: https://ca.lab:14000/authZ/Ij7U8xLAwDJbSa7eYVp-41Pmk6tdsBXOBmNyToMiB64
2026/11/20 14:37:00 [INFO] [portal.se-201-11.lab] acme: Could not find solver for: tls-alpn-01
2026/11/20 14:37:00 [INFO] [portal.se-201-11.lab] acme: use http-01 solver
2026/11/20 14:37:00 [INFO] [www.se-201-11.lab] acme: Could not find solver for: tls-alpn-01
2026/11/20 14:37:00 [INFO] [www.se-201-11.lab] acme: use http-01 solver
2026/11/20 14:37:00 [INFO] [portal.se-201-11.lab] acme: Trying to solve HTTP-01
2026/11/20 14:37:04 [INFO] [portal.se-201-11.lab] The server validated our request
2026/11/20 14:37:04 [INFO] [www.se-201-11.lab] acme: Trying to solve HTTP-01
2026/11/20 14:37:08 [INFO] [www.se-201-11.lab] The server validated our request
2026/11/20 14:37:08 [INFO] [www.se-201-11.lab, portal.se-201-11.lab] acme: Validations succeeded; requesting certificates
2026/11/20 14:37:08 [INFO] Wait for certificate [timeout: 30s, interval: 500ms]
2026/11/20 14:37:08 [INFO] [www.se-201-11.lab] Server responded with a certificate.
10.53.0.10 - - [20/Nov/2026:14:37:00 +0000] "GET /.well-known/acme-challenge/TelKpfKOeRRi1bAU1r_7SGjEtsR7PCEVqcCvHy8sL-g HTTP/1.1" 200 87 "-" "LetsEncrypt-Pebble-VA (linux; amd64)"
10.53.0.10 - - [20/Nov/2026:14:37:00 +0000] "GET /.well-known/acme-challenge/TelKpfKOeRRi1bAU1r_7SGjEtsR7PCEVqcCvHy8sL-g HTTP/1.1" 200 87 "-" "LetsEncrypt-Pebble-VA (linux; amd64)"
10.53.0.10 - - [20/Nov/2026:14:37:00 +0000] "GET /.well-known/acme-challenge/TelKpfKOeRRi1bAU1r_7SGjEtsR7PCEVqcCvHy8sL-g HTTP/1.1" 200 87 "-" "LetsEncrypt-Pebble-VA (linux; amd64)"
10.53.0.10 - - [20/Nov/2026:14:37:04 +0000] "GET /.well-known/acme-challenge/UwKvPKsxhBYMiccm9dwxdjQkUOXkekStI8MJ2SvPyUk HTTP/1.1" 200 87 "-" "LetsEncrypt-Pebble-VA (linux; amd64)"
10.53.0.10 - - [20/Nov/2026:14:37:04 +0000] "GET /.well-known/acme-challenge/UwKvPKsxhBYMiccm9dwxdjQkUOXkekStI8MJ2SvPyUk HTTP/1.1" 200 87 "-" "LetsEncrypt-Pebble-VA (linux; amd64)"
10.53.0.10 - - [20/Nov/2026:14:37:04 +0000] "GET /.well-known/acme-challenge/UwKvPKsxhBYMiccm9dwxdjQkUOXkekStI8MJ2SvPyUk HTTP/1.1" 200 87 "-" "LetsEncrypt-Pebble-VA (linux; amd64)"
```

Вивід кроку 3.4:

```text
root@se-201-11:/lab/work# cd /lab/work/lego/certificates
openssl x509 -in www.se-201-11.lab.crt -noout -subject -issuer -dates -serial -ext subjectAltName
openssl x509 -in www.se-201-11.lab.issuer.crt -noout -subject -issuer
subject=CN = www.se-201-11.lab
issuer=CN = Pebble Intermediate CA 61d16c
notBefore=Nov 20 14:37:08 2026 GMT
notAfter=Nov 20 14:37:07 2031 GMT
serial=0643D57C10F786A5
X509v3 Subject Alternative Name: 
    DNS:www.se-201-11.lab, DNS:portal.se-201-11.lab
subject=CN = Pebble Intermediate CA 61d16c
issuer=CN = Pebble Root CA 0932b3
```

Вивід кроку 3.5:

```text
root@se-201-11:/lab/work# cp www.se-201-11.lab.crt /lab/tls/server.crt
cp www.se-201-11.lab.key /lab/tls/server.key
web-reload
curl -sS --cacert /lab/tls/acme-root.crt https://www.se-201-11.lab/
openssl s_client -connect www.se-201-11.lab:443 -servername www.se-201-11.lab -CAfile /lab/tls/acme-root.crt \
  </dev/null 2>/dev/null | sed -n '/^Certificate chain/,/^---/p;/^Verify return code/p'
nginx: the configuration file /lab/nginx.conf syntax is ok
nginx: configuration file /lab/nginx.conf test is successful
2026/11/20 14:37:08 [notice] 206#206: signal process started
curl: (60) SSL certificate problem: unable to get local issuer certificate
More details here: https://curl.se/docs/sslcerts.html

curl failed to verify the legitimacy of the server and therefore could not
establish a secure connection to it. To learn more about this situation and
how to fix it, please visit the web page mentioned above.
Certificate chain
 0 s:CN = www.se-201-11.lab
   i:CN = Pebble Intermediate CA 61d16c
   a:PKEY: id-ecPublicKey, 256 (bit); sigalg: RSA-SHA256
   v:NotBefore: Nov 20 14:37:08 2026 GMT; NotAfter: Nov 20 14:37:07 2031 GMT
---
Verify return code: 21 (unable to verify the first certificate)
```

Вивід кроку 3.6:

```text
root@se-201-11:/lab/work# cat www.se-201-11.lab.crt www.se-201-11.lab.issuer.crt > /lab/tls/server.crt
web-reload
curl -sS --cacert /lab/tls/acme-root.crt https://www.se-201-11.lab/
openssl s_client -connect www.se-201-11.lab:443 -servername www.se-201-11.lab -CAfile /lab/tls/acme-root.crt \
  </dev/null 2>/dev/null | sed -n '/^Certificate chain/,/^---/p;/^Verify return code/p'
curl -sS --cacert /lab/tls/acme-root.crt https://portal.se-201-11.lab/
nginx: the configuration file /lab/nginx.conf syntax is ok
nginx: configuration file /lab/nginx.conf test is successful
2026/11/20 14:37:08 [notice] 222#222: signal process started
server: se-201-11 (https)
Host: www.se-201-11.lab
SNI: www.se-201-11.lab
protocol: TLSv1.3
Certificate chain
 0 s:CN = www.se-201-11.lab
   i:CN = Pebble Intermediate CA 61d16c
   a:PKEY: id-ecPublicKey, 256 (bit); sigalg: RSA-SHA256
   v:NotBefore: Nov 20 14:37:08 2026 GMT; NotAfter: Nov 20 14:37:07 2031 GMT
---
Verify return code: 21 (unable to verify the first certificate)
server: se-201-11 (https)
Host: portal.se-201-11.lab
SNI: portal.se-201-11.lab
protocol: TLSv1.3
```

Усі три команди в цьому прогоні виконано в ту саму секунду, що й `web-reload`. `curl` уже пройшов перевірку з повним ланцюжком, а `openssl s_client` ще отримав один сертифікат і код 21. Тому обидві перевірки кроку 3.5 повторено через 2 хв (14:38:57):

```text
+ date -u +%T
14:38:57
+ grep -c 'BEGIN CERTIFICATE' /lab/tls/server.crt
2
+ curl -sS --cacert /lab/tls/acme-root.crt https://www.se-201-11.lab/
server: se-201-11 (https)
Host: www.se-201-11.lab
SNI: www.se-201-11.lab
protocol: TLSv1.3
+ openssl s_client -connect www.se-201-11.lab:443 -servername www.se-201-11.lab -CAfile /lab/tls/acme-root.crt
+ sed -n '/^Certificate chain/,/^---/p;/^Verify return code/p'
Certificate chain
 0 s:CN = www.se-201-11.lab
   i:CN = Pebble Intermediate CA 61d16c
   a:PKEY: id-ecPublicKey, 256 (bit); sigalg: RSA-SHA256
   v:NotBefore: Nov 20 14:37:08 2026 GMT; NotAfter: Nov 20 14:37:07 2031 GMT
 1 s:CN = Pebble Intermediate CA 61d16c
   i:CN = Pebble Root CA 0932b3
   a:PKEY: rsaEncryption, 2048 (bit); sigalg: RSA-SHA256
   v:NotBefore: Nov 20 14:33:46 2026 GMT; NotAfter: Nov 20 14:33:46 2056 GMT
---
Verify return code: 0 (ok)
+ curl -sS --cacert /lab/tls/acme-root.crt https://portal.se-201-11.lab/
server: se-201-11 (https)
Host: portal.se-201-11.lab
SNI: portal.se-201-11.lab
protocol: TLSv1.3
```

| Параметр | Значення |
|---|---|
| Видавець сертифіката сервера | `CN = Pebble Intermediate CA 61d16c` |
| Видавець сертифіката видавця | `CN = Pebble Root CA 0932b3` |
| Імена в SAN | `DNS:www.se-201-11.lab`, `DNS:portal.se-201-11.lab` |
| Строк дії (від – до) | 20.11.2026 14:37:08 GMT – 20.11.2031 14:37:07 GMT |
| Тип ключа сервера і алгоритм підпису | EC P-256 (`id-ecPublicKey`, `prime256v1`); підпис `sha256WithRSAEncryption` (RSA-SHA256) |
| Кількість сертифікатів, які надсилає сервер, у кроці 3.5 і в кроці 3.6 | 1 і 2 |

1. Хто і як перевірив, що ви контролюєте обидва імена? Вкажіть рядки виводу, які це підтверджують.

   Перевірку виконав центр сертифікації Pebble, його модуль перевірки (VA) з адреси 10.53.0.10, методом HTTP-01. Для кожного імені центр видав окремий виклик (`AuthURL: .../authZ/...`), `lego` розмістив файл з токеном у `/var/www/acme`, а VA завантажив його по HTTP з порту 80 саме за цим іменем. Відповідь `200` з правильним вмістом доводить, що я керую сервером, на який вказує ім'я в DNS. Підтвердження:
   - у журналі nginx два різні токени `GET /.well-known/acme-challenge/TelKpf…` (14:37:00) і `…/UwKvPK…` (14:37:04) з `200` від `10.53.0.10` з агентом `LetsEncrypt-Pebble-VA`; кожен токен запитано тричі (імітація перевірки з кількох точок);
   - у `lego` рядки `[portal.se-201-11.lab] The server validated our request`, `[www.se-201-11.lab] The server validated our request` і `Validations succeeded; requesting certificates`.

2. Чому в кроці 3.5 перевірка не пройшла, хоча корінь центру сертифікації вказано в `--cacert`, а сертифікат виданий правильно?

   Сервер надіслав лише власний сертифікат (у ланцюжку один елемент `0`), без проміжного `Pebble Intermediate CA 61d16c`. Клієнт довіряє тільки кореню `Pebble Root CA`, а сертифікат сервера підписаний проміжним центром. Без проміжного сертифіката клієнт не може побудувати шлях від сертифіката сервера до кореня, звідси `Verify return code: 21 (unable to verify the first certificate)` і `curl: (60) ... unable to get local issuer certificate`. Сервер зобов'язаний сам надсилати весь ланцюжок, окрім кореня.

3. У виводі ланцюжка для сертифіката сервера вказано `id-ecPublicKey` і `RSA-SHA256`. Що означає кожне з цих значень і чому вони не суперечать одне одному?

   `id-ecPublicKey, 256 (bit)` — тип **відкритого ключа самого сервера**: еліптична крива P-256, створена `lego` для мого сервера. Цим ключем сервер підписує рукостискання (CertificateVerify). `sigalg: RSA-SHA256` — **алгоритм підпису, яким видавець підписав сертифікат**: Pebble Intermediate має ключ RSA 2048 (`rsaEncryption, 2048 (bit)` у рядку `1`). Це ключі двох різних суб'єктів, тож вони не мусять бути одного типу: тип підпису сертифіката визначає ключ видавця, а не ключ власника.

4. Що станеться з перевіркою вашого сервера після перезапуску стенда і чому? Що в реальній інфраструктурі відповідає цій ситуації?

   Після перезапуску Pebble створить нові кореневий і проміжний ключі (у назві зміниться суфікс, наприклад `Pebble Root CA 0932b3` → інший). Мій сертифікат і проміжний сертифікат у `server.crt` підписані старими ключами, тож відносно нового кореня ланцюжок не перевіриться: помилка на кшталт `unable to get local issuer certificate`. Те саме станеться, якщо перевіряти зі старим `acme-root.crt` сертифікат, виданий новим центром. Треба знову виконати кроки 3.1, 3.3 і 3.6. У реальній інфраструктурі це відповідає заміні або відкликанню кореня чи проміжного центру сертифікації: компрометація CA, вилучення кореня зі сховищ довіри браузерів (як-от DigiNotar), планова ротація ключів CA. Усі сертифікати під старим ланцюжком доводиться перевипускати.

## Завдання 4. Діагностика несправностей

Вивід кроку 4.1:

```text
root@se-201-11:/lab/work# for i in 1 2 3 4 5; do
  n=f$i.se-201-11.lab; echo "=== $n"
  curl -sS --cacert $STAND_CA https://$n/ 2>&1 | head -1
  openssl s_client -connect $n:443 -servername $n -CAfile $STAND_CA </dev/null 2>/dev/null \
    | sed -n '/^Certificate chain/,/^---/p;/^Verify return code/p' | grep -v PKEY
done
=== f1.se-201-11.lab
server: web, f1
Certificate chain
 0 s:CN = f1.se-201-11.lab
   i:O = OPISM Lab, CN = OPISM Stand Intermediate CA
   v:NotBefore: Nov 20 14:33:44 2026 GMT; NotAfter: Feb 18 14:33:44 2027 GMT
 1 s:O = OPISM Lab, CN = OPISM Stand Intermediate CA
   i:O = OPISM Lab, CN = OPISM Stand Root CA
   v:NotBefore: Nov 20 14:33:43 2026 GMT; NotAfter: Nov 19 14:33:43 2031 GMT
---
Verify return code: 0 (ok)
=== f2.se-201-11.lab
curl: (60) SSL: no alternative certificate subject name matches target host name 'f2.se-201-11.lab'
Certificate chain
 0 s:CN = old.se-201-11.lab
   i:O = OPISM Lab, CN = OPISM Stand Intermediate CA
   v:NotBefore: Nov 20 14:33:44 2026 GMT; NotAfter: Feb 18 14:33:44 2027 GMT
 1 s:O = OPISM Lab, CN = OPISM Stand Intermediate CA
   i:O = OPISM Lab, CN = OPISM Stand Root CA
   v:NotBefore: Nov 20 14:33:43 2026 GMT; NotAfter: Nov 19 14:33:43 2031 GMT
---
Verify return code: 0 (ok)
=== f3.se-201-11.lab
curl: (60) SSL certificate problem: unable to get local issuer certificate
Certificate chain
 0 s:CN = f3.se-201-11.lab
   i:O = Foreign Org, CN = Foreign Intermediate CA
   v:NotBefore: Nov 20 14:33:44 2026 GMT; NotAfter: Feb 18 14:33:44 2027 GMT
 1 s:O = Foreign Org, CN = Foreign Intermediate CA
   i:O = Foreign Org, CN = Foreign Root CA
   v:NotBefore: Nov 20 14:33:43 2026 GMT; NotAfter: Nov 19 14:33:43 2031 GMT
---
Verify return code: 20 (unable to get local issuer certificate)
=== f4.se-201-11.lab
curl: (60) SSL certificate problem: self-signed certificate
Certificate chain
 0 s:CN = f4.se-201-11.lab
   i:CN = f4.se-201-11.lab
   v:NotBefore: Nov 20 14:33:44 2026 GMT; NotAfter: Feb 18 14:33:44 2027 GMT
---
Verify return code: 18 (self-signed certificate)
=== f5.se-201-11.lab
curl: (60) SSL certificate problem: unable to get local issuer certificate
Certificate chain
 0 s:CN = f5.se-201-11.lab
   i:O = OPISM Lab, CN = OPISM Stand Intermediate CA
   v:NotBefore: Nov 20 14:33:44 2026 GMT; NotAfter: Feb 18 14:33:44 2027 GMT
---
Verify return code: 21 (unable to verify the first certificate)
```

Додатково для питань 2–3: запит `curl -k` і SAN кожного сертифіката:

```text
=== f1.se-201-11.lab: server: web, f1
    DNS:f1.se-201-11.lab
=== f2.se-201-11.lab: server: web, f2
    DNS:old.se-201-11.lab
=== f3.se-201-11.lab: server: web, f3
    DNS:f3.se-201-11.lab
=== f4.se-201-11.lab: server: web, f4
    DNS:f4.se-201-11.lab
=== f5.se-201-11.lab: server: web, f5
    DNS:f5.se-201-11.lab
```

| Сервер | Помилка `curl` | `Verify return code` | Яка перевірка не пройшла | Рядок виводу, що це доводить | Що має змінити власник сервера |
|---|---|---|---|---|---|
| f1 | немає (`server: web, f1`) | 0 (ok) | усі перевірки пройдено: справний | ланцюжок `0 s:CN = f1…` → `1 s:… OPISM Stand Intermediate CA`, `Verify return code: 0 (ok)` | нічого |
| f2 | `(60) SSL: no alternative certificate subject name matches target host name 'f2.se-201-11.lab'` | 0 (ok) | відповідність імені: `f2` немає в SAN | `0 s:CN = old.se-201-11.lab`, SAN `DNS:old.se-201-11.lab` | перевипустити сертифікат з `f2.se-201-11.lab` у SAN (або налаштувати для цього імені правильний сертифікат) |
| f3 | `(60) SSL certificate problem: unable to get local issuer certificate` | 20 (unable to get local issuer certificate) | довіра до кореня: ланцюжок веде до центру, якому клієнт не довіряє | `1 s:O = Foreign Org, CN = Foreign Intermediate CA` / `i:O = Foreign Org, CN = Foreign Root CA` | отримати сертифікат від центру, якому довіряють клієнти (тут — корінь стенда `OPISM Stand Root CA` або публічний CA) |
| f4 | `(60) SSL certificate problem: self-signed certificate` | 18 (self-signed certificate) | довіра: сертифікат підписаний сам собою | `0 s:CN = f4.se-201-11.lab` / `i:CN = f4.se-201-11.lab` (subject = issuer, один сертифікат) | замінити на сертифікат, виданий довіреним центром (наприклад, через ACME, як у завданні 3) |
| f5 | `(60) SSL certificate problem: unable to get local issuer certificate` | 21 (unable to verify the first certificate) | побудова ланцюжка: сервер не надсилає проміжний сертифікат | у ланцюжку лише `0 s:CN = f5…`, `i:… OPISM Stand Intermediate CA`, рядка `1` немає | додати проміжний сертифікат у файл сертифіката сервера (fullchain: сервер + проміжний), як у кроці 3.6 |

Простроченого сертифіката серед моїх серверів немає: у всіх п'яти `NotAfter: Feb 18 14:33:44 2027 GMT` або пізніше.

1. Для сервера з помилкою `unable to get local issuer certificate` визначте, яка це несправність: сервер не надсилає проміжний сертифікат чи сертифікат виданий центром, якому клієнт не довіряє. Чим ці дві несправності відрізняються у виводі `openssl s_client`?

   У мене таких серверів два, і `curl` повідомляє для них однаково. Розрізняє їх вивід `openssl s_client`:
   - **f3 — центр, якому клієнт не довіряє.** Сервер надсилає повний ланцюжок з двох сертифікатів (`0` і `1`), але останній видав `Foreign Root CA`, якого немає в `$STAND_CA`. Код `20 (unable to get local issuer certificate)`.
   - **f5 — немає проміжного.** У ланцюжку лише один сертифікат `0`, виданий `OPISM Stand Intermediate CA`, а самого проміжного сервер не надіслав. Код `21 (unable to verify the first certificate)`: клієнт не може перевірити навіть перший сертифікат.

   Отже, ознаки — кількість сертифікатів у `Certificate chain`, назва кінцевого видавця (довірений корінь чи чужий) і код 20 проти 21.

2. Якщо серед ваших серверів є сервер з невідповідним ім'ям, чому `openssl s_client` повертає для нього `Verify return code: 0 (ok)`, а `curl` повідомляє про помилку? Якщо такого сервера немає, дайте відповідь для загального випадку.

   Такий сервер — f2: сертифікат видано на `old.se-201-11.lab`. `openssl s_client` за замовчуванням перевіряє лише ланцюжок підписів до довіреного кореня та строки дії, а відповідність імені не перевіряє (для цього потрібен ключ `-verify_hostname <ім'я>`). Ланцюжок f2 справний, тому `0 (ok)`. `curl`, як і браузер, додатково звіряє запитане ім'я з SAN сертифіката (RFC 6125) і відмовляє: `no alternative certificate subject name matches target host name`.

3. Які з п'яти серверів відповіли б на запит `curl -k`? Що при цьому втрачається порівняно з `--cacert`?

   Усі п'ять: додатковий вивід показав `server: web, f1` … `server: web, f5`. Ключ `-k` (`--insecure`) вимикає перевірку сертифіката: ланцюжка, довіри до кореня й імені. З'єднання лишається зашифрованим, але втрачається **автентифікація сервера**: клієнт не знає, з ким саме встановив шифрований канал. Атакувальник посередині (MITM) може підставити будь-який сертифікат, і `curl -k` його прийме. З `--cacert` клієнт приймає лише сервер, сертифікат якого має правильне ім'я, чинний строк і веде до вказаного кореня.

## Завдання 5. Ціна нового з'єднання

**Прогноз** (записати до вимірювання). Скільки RTT мине до завершення кожного етапу:

Прогноз зроблено без урахування пошуку імені: ім'я вже є в кеші резолвера, тож `time_namelookup` ≈ 0. RTT рахуються від початку запиту.

| Етап | TLS 1.3, нове з'єднання | TLS 1.2, нове з'єднання | Повторне використання з'єднання |
|---|---|---|---|
| `time_connect` | 1 RTT (SYN → SYN/ACK) | 1 RTT | 0 (з'єднання вже є) |
| `time_appconnect` | 2 RTT (+1 RTT: ClientHello → ServerHello…Finished) | 3 RTT (+2 RTT: два обміни рукостискання) | 0 (рукостискання вже виконано) |
| `time_starttransfer` | 3 RTT (+1 RTT: запит → перший байт) | 4 RTT | 1 RTT (лише запит → відповідь) |

Вивід кроків 5.2 і 5.3:

```text
root@se-201-11:/lab/work# F='%{time_namelookup} %{time_connect} %{time_appconnect} %{time_starttransfer} %{time_total} %{http_version} %{num_connects}\n'
U=https://origin.se-201-11.lab/
for i in 1 2 3; do curl -s -o /dev/null --cacert $STAND_CA -w "$F" $U; done
for i in 1 2 3; do curl -s -o /dev/null --tls-max 1.2 --cacert $STAND_CA -w "$F" $U; done
0.022765 0.042904 0.066131 0.086496 0.086550 2 1
0.020424 0.040545 0.063839 0.084125 0.084180 2 1
0.020542 0.040719 0.066483 0.086730 0.086776 2 1
0.020407 0.040528 0.083913 0.104358 0.104421 2 1
0.020431 0.040536 0.083835 0.104099 0.104161 2 1
0.020431 0.040537 0.083849 0.104150 0.104211 2 1

root@se-201-11:/lab/work# curl -s --cacert $STAND_CA -w "$F" -o /dev/null $U -o /dev/null $U -o /dev/null $U
0.020489 0.040612 0.063831 0.084133 0.084196 2 1
0.000017 0.000000 0.000000 0.020205 0.020273 2 0
0.000011 0.000000 0.000000 0.020243 0.020283 2 0
```

Затримка на інтерфейсі контейнера (вивід на початку роботи):

```text
root@se-201-11:/lab/work# date -u; tc qdisc show dev eth0
Fri Nov 20 14:36:30 UTC 2026
qdisc netem 8001: root refcnt 3 limit 1000 delay 20ms
```

<!-- Значення в мілісекундах. Для нових з'єднань — медіана трьох вимірювань. -->

| Запит | `namelookup` | `connect` | `appconnect` | `starttransfer` | `total` | `num_connects` |
|---|---|---|---|---|---|---|
| TLS 1.3, нове | 20,5 | 40,7 | 66,1 | 86,5 | 86,6 | 1 |
| TLS 1.2, нове | 20,4 | 40,5 | 83,8 | 104,2 | 104,2 | 1 |
| 5.3, перший запит | 20,5 | 40,6 | 63,8 | 84,1 | 84,2 | 1 |
| 5.3, другий запит | 0,017 | 0 | 0 | 20,2 | 20,3 | 0 |
| 5.3, третій запит | 0,011 | 0 | 0 | 20,2 | 20,3 | 0 |

RTT, визначений вимірюванням, і з якого значення його визначено: **RTT ≈ 20 мс**. Його визначено як `time_connect − time_namelookup` = 40,5 − 20,4 = 20,1 мс: рукостискання TCP займає рівно 1 RTT. Те саме значення дає `time_starttransfer` повторних запитів у 5.3 (20,2 мс — лише запит і відповідь на готовому з'єднанні). Затримка стенда `tc qdisc … delay 20ms` на вихідному інтерфейсі моєї машини підтверджує результат: кожен пакет туди-назад затримується один раз, на 20 мс.

1. Виразіть кожне виміряне значення через RTT. Де вимірювання відрізняється від цілого числа RTT і чим це пояснюється?

   | Запит | namelookup | connect | appconnect | starttransfer |
   |---|---|---|---|---|
   | TLS 1.3, нове | 1,0 RTT | 2,0 RTT | 3,3 RTT (3 RTT + 6 мс) | 4,3 RTT |
   | TLS 1.2, нове | 1,0 RTT | 2,0 RTT | 4,2 RTT (4 RTT + 3,8 мс) | 5,2 RTT |
   | повторне (5.3) | ≈ 0 | 0 | 0 | 1,0 RTT |

   Прогноз за структурою підтвердився: TCP додає 1 RTT, рукостискання TLS 1.3 — 1 RTT, TLS 1.2 — 2 RTT, запит HTTP — 1 RTT, повторне використання з'єднання — лише 1 RTT. Відхилень два:
   - **Усе зсунуто на +1 RTT** через пошук імені (питання 2), якого прогноз не врахував.
   - **`appconnect` на 3–6 мс більший за ціле число RTT.** Це обчислення, а не мережа: генерація ключа ECDHE, підпис CertificateVerify на сервері, перевірка підписів ланцюжка сертифікатів клієнтом. Різниця `starttransfer − appconnect` рівно 20,4 мс, тобто далі знову ціле число RTT. Розкид першого вимірювання TLS 1.3 (22,8 мс на пошук імені) — випадкова затримка першого запиту.

2. Чому `time_namelookup` не близький до нуля, хоча резолвер уже має ім'я в кеші? За яких умов він був би приблизно вдвічі більшим?

   Кеш резолвера прибирає звернення до root/TLD/авторитативного сервера, але сам запит від `curl` до резолвера 10.53.0.53 — це мережевий обмін, і його пакет виходить через мій інтерфейс із затримкою netem 20 мс. Тому навіть влучання в кеш коштує 1 RTT. Нуля він досяг би лише за наявності локального кешу на самій машині. Приблизно вдвічі більшим (≈ 2 RTT) він був би, якби запити A та AAAA надсилалися послідовно, а не паралельно (опція `single-request` у `resolv.conf`), або якби першим ішов запит із доменом пошуку (`search`), що повертає NXDOMAIN, і лише другим — справжнє ім'я.

3. Сервіс виконує 200 послідовних запитів до цього сервера. Розрахуйте, скільки часу займе лише очікування мережі, якщо кожен запит встановлює нове з'єднання TLS 1.3, нове з'єднання TLS 1.2 і якщо всі запити йдуть через одне з'єднання.

   RTT = 20 мс; пошук імені — 1 RTT на кожне нове з'єднання.
   - **TLS 1.3, нове з'єднання щоразу:** (1 DNS + 1 TCP + 1 TLS + 1 HTTP) = 4 RTT = 80 мс; 200 × 80 мс = **16 с**. За виміряним `total` 86,6 мс — 17,3 с.
   - **TLS 1.2, нове з'єднання щоразу:** 5 RTT = 100 мс; 200 × 100 мс = **20 с**. За виміряним 104,2 мс — 20,8 с.
   - **Одне з'єднання:** перший запит 4 RTT, кожен наступний 1 RTT: (4 + 199) × 20 мс = 203 × 20 мс = **4,06 с**. За виміряним 84,2 + 199 × 20,3 ≈ 4,12 с.

   Повторне використання з'єднання скорочує очікування мережі приблизно вчетверо порівняно з TLS 1.3 і впʼятеро порівняно з TLS 1.2.

## Висновки

**Що виявилося несподіваним.** Результат, який не збігся з очікуванням, і рядок виводу, де це видно:

Я очікував, що для імені в кеші резолвера `time_namelookup` буде близьким до нуля, як у прогнозі. Насправді кожен новий запит витрачав на пошук імені ≈ 20 мс, тобто цілий RTT: рядки `0.020424 0.040545 …`, `0.020407 0.040528 …`. Через це всі етапи зсунулися на 1 RTT відносно прогнозу. Причина в тому, що затримка стенда стоїть на моєму інтерфейсі й діє на будь-який пакет, зокрема на запит до резолвера. Отже, «ім'я в кеші» означає лише відсутність рекурсії, а не відсутність мережевого обміну. Друге несподіване — повна прозорість TLS 1.2: сертифікат стенда видно в дампі (`TLS 1.2: 2`), а в TLS 1.3 — ні (`TLS 1.3: 0`). Тобто в TLS 1.2 спостерігач бачить не лише ім'я з SNI, а й увесь ланцюжок сертифікатів сервера.

**Яке питання залишилося без відповіді.** Що саме не вдалося пояснити; до якого рядка виводу це стосується; що вже перевірено і що з'ясувати не вдалося:

Крок 3.6, перший прогін. Команди `web-reload`, `curl` і `openssl s_client` виконано одна за одною в одну секунду (`2026/11/20 14:37:08 [notice] 222#222: signal process started`). `curl` пройшов перевірку, а для цього потрібен повний ланцюжок (вивід `server: se-201-11 (https)` … `protocol: TLSv1.3`). Однак `openssl s_client`, запущений одразу після нього, отримав лише один сертифікат: `Certificate chain` з одним рядком `0` і `Verify return code: 21 (unable to verify the first certificate)`. Повторна перевірка через 2 хв дала 2 сертифікати і `0 (ok)`.

Перевірено: файл `server.crt` на момент повтору містив 2 сертифікати (`grep -c 'BEGIN CERTIFICATE'` → 2), конфігурація пройшла `nginx -t`. Гіпотеза: під час «м'якого» перезавантаження nginx старі робочі процеси ще кілька мілісекунд приймають нові з'єднання на спільних сокетах. `curl` потрапив до нового процесу, а `s_client` — до старого, з конфігурацією кроку 3.5. Не з'ясовано, чому порядок саме такий: новий процес обслужив з'єднання раніше, ніж старий. Це можна перевірити: виконати `s_client` у циклі одразу після `web-reload` і записати PID робочого процесу з журналу nginx для кожного з'єднання.

## Декларація використання ШІ

Використовувалися інструменти ШІ: так

<!-- Якщо так, заповнити таблицю: один рядок на кожне звернення, що вплинуло на звіт. Промпт наводити дослівно. -->

| № | Інструмент | Промпт (дослівно) | Що використано у звіті і що змінено самостійно |
|---|---|---|---|
| 1 | Claude (Anthropic), модель Claude Opus 5.5 | «я частково зробив лабораторну (надаю тобі файл методичку). Зроби мені інші завдання, і окремо розпиши детальний опис так щоб я зрозумів тему і для чого воно робиться, і чому саме так. Все роби суто по темі. Також перевір те що вже зроблено і якщо є помилки випправ і зазнач де саме. Також поясни порядок дій роботи в ГітХабі, і також поясни чому. Виконані завдання (без пояснень для мене) виклади в бланк для перевірки мною» | Написані завдання викладено в бланк (без пояснень), а також окремо написані пояснення до кожного завдання для розуміння всієї теми, заповнив таблиці, прогнози на основі виводу в GitHub, дав відповіді на питання, які залишились без відповіді та написано исновки.   |
