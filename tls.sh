#!/bin/bash
# TLS lab se-201-11: runs tasks 1-5 per the handout inside the student container, logs to tlslog/
cd "$(dirname "$0")"
SID=se-201-11; Z=$SID.lab; R=origin.$Z; AL=portal.$Z
C="docker compose -f stand/compose.yaml"
L=tlslog; mkdir -p $L
st(){ local cmd="$1" lbl="${2:-$1}"; echo "root@$SID:/lab/work# $lbl"; $C exec -T $SID bash -lc "cd /lab/work; $cmd" 2>&1; echo; }
note(){ echo "### $*"; }
RELOAD='nginx -c /lab/nginx.conf -t && nginx -c /lab/nginx.conf -s reload'
ROOT='curl -s --cacert "$STAND_CA" https://ca.lab:15000/roots/0 > /lab/tls/acme-root.crt && echo "збережено /lab/tls/acme-root.crt"'

t0(){
st "openssl version"
st "date -u; tc qdisc show dev eth0"
}

t1(){
note "1.1"
st "timeout 8 tcpdump -ni eth0 -A -s0 -l 'host 10.53.0.80 and tcp port 80' > t1-http.txt 2>t1-http.err & sleep 1; curl -s http://$R/; wait; cat t1-http.err; grep -a -E 'GET /|Host:|server: web' t1-http.txt" \
"timeout 8 tcpdump -ni eth0 -A -s0 -l 'host 10.53.0.80 and tcp port 80' > t1-http.txt &
sleep 1; curl -s http://$R/; wait
grep -a -E 'GET /|Host:|server: web' t1-http.txt"
note "1.2"
st "timeout 8 tcpdump -ni eth0 -A -s0 -l 'host 10.53.0.80 and tcp port 443' > t1-https.txt 2>t1-https.err & sleep 1; curl -s --cacert \$STAND_CA https://$R/; wait; cat t1-https.err; grep -a -c -E 'GET /|server: web' t1-https.txt; grep -a -o '$R' t1-https.txt | wc -l" \
"timeout 8 tcpdump -ni eth0 -A -s0 -l 'host 10.53.0.80 and tcp port 443' > t1-https.txt &
sleep 1; curl -s --cacert \$STAND_CA https://$R/; wait
grep -a -c -E 'GET /|server: web' t1-https.txt
grep -a -o '$R' t1-https.txt | wc -l"
note "додатково: Host і ім'я сервера в дампі HTTP (кількість входжень)"
st "grep -a -c 'Host:' t1-http.txt; grep -a -o '$R' t1-http.txt | wc -l; grep -a -c 'Host:' t1-https.txt"
}

t2(){
note "2.1"
st "openssl s_client -connect $R:443 -servername $R -alpn h2,http/1.1 -CAfile \$STAND_CA -trace </dev/null > t2-13.txt 2>&1; grep -a -E '^(Sent|Received) Record|Content Type|^    [A-Z][A-Za-z]+, Length' t2-13.txt; grep -a -E '^(ALPN|New,)|Verify return' t2-13.txt" \
"openssl s_client -connect $R:443 -servername $R -alpn h2,http/1.1 \\
  -CAfile \$STAND_CA -trace </dev/null > t2-13.txt 2>&1
grep -a -E '^(Sent|Received) Record|Content Type|^    [A-Z][A-Za-z]+, Length' t2-13.txt
grep -a -E '^(ALPN|New,)|Verify return' t2-13.txt"
note "2.2"
st "openssl s_client -connect $R:443 -servername $R -alpn h2,http/1.1 -CAfile \$STAND_CA -trace -tls1_2 </dev/null > t2-12.txt 2>&1; grep -a -E '^(Sent|Received) Record|Content Type|^    [A-Z][A-Za-z]+, Length' t2-12.txt; grep -a -E '^(ALPN|New,)|Verify return' t2-12.txt" \
"openssl s_client -connect $R:443 -servername $R -alpn h2,http/1.1 \\
  -CAfile \$STAND_CA -trace -tls1_2 </dev/null > t2-12.txt 2>&1
grep -a -E '^(Sent|Received) Record|Content Type|^    [A-Z][A-Za-z]+, Length' t2-12.txt
grep -a -E '^(ALPN|New,)|Verify return' t2-12.txt"
note "2.3"
st "grep -a -A3 'extension_type=server_name' t2-13.txt | head -4"
note "2.4"
st "for v in 1.3 1.2; do timeout 6 tcpdump -ni eth0 -A -s0 -l 'host 10.53.0.80 and tcp port 443' > t2-dump-\$v.txt 2>/dev/null & sleep 1; curl -s -o /dev/null --tlsv1.2 --tls-max \$v --cacert \$STAND_CA https://$R/; wait; echo \"TLS \$v: \$(grep -a -c 'OPISM Stand Intermediate' t2-dump-\$v.txt)\"; done" \
"for v in 1.3 1.2; do
  timeout 6 tcpdump -ni eth0 -A -s0 -l 'host 10.53.0.80 and tcp port 443' > t2-dump-\$v.txt &
  sleep 1; curl -s -o /dev/null --tlsv1.2 --tls-max \$v --cacert \$STAND_CA https://$R/; wait
  echo \"TLS \$v: \$(grep -a -c 'OPISM Stand Intermediate' t2-dump-\$v.txt)\"
done"
}

t3(){
note "3.1"
st "$ROOT; openssl x509 -in /lab/tls/acme-root.crt -noout -subject -dates" "acme-root
openssl x509 -in /lab/tls/acme-root.crt -noout -subject -dates"
note "3.2"
st "curl -sS --cacert /lab/tls/acme-root.crt https://www.$Z/"
note "3.3"
st "lego --server \$ACME_DIR --email admin@$Z --accept-tos --path /lab/work/lego --http --http.webroot /var/www/acme --domains www.$Z --domains $AL run --no-bundle; grep acme-challenge /var/log/nginx/access.log" \
"lego --server \$ACME_DIR --email admin@$Z --accept-tos --path /lab/work/lego \\
  --http --http.webroot /var/www/acme \\
  --domains www.$Z --domains $AL run --no-bundle
grep acme-challenge /var/log/nginx/access.log"
note "3.4"
st "cd /lab/work/lego/certificates; openssl x509 -in www.$Z.crt -noout -subject -issuer -dates -serial -ext subjectAltName; openssl x509 -in www.$Z.issuer.crt -noout -subject -issuer" \
"cd /lab/work/lego/certificates
openssl x509 -in www.$Z.crt -noout -subject -issuer -dates -serial -ext subjectAltName
openssl x509 -in www.$Z.issuer.crt -noout -subject -issuer"
note "додатково: тип ключа і алгоритм підпису"
st "cd /lab/work/lego/certificates; openssl x509 -in www.$Z.crt -noout -text | grep -E 'Public Key Algorithm|Signature Algorithm|ASN1 OID|NIST CURVE' | sort -u; openssl x509 -in www.$Z.issuer.crt -noout -text | grep -E 'Public Key Algorithm' | sort -u"
note "3.5"
st "cd /lab/work/lego/certificates; cp www.$Z.crt /lab/tls/server.crt; cp www.$Z.key /lab/tls/server.key; $RELOAD; curl -sS --cacert /lab/tls/acme-root.crt https://www.$Z/; openssl s_client -connect www.$Z:443 -servername www.$Z -CAfile /lab/tls/acme-root.crt </dev/null 2>/dev/null | sed -n '/^Certificate chain/,/^---/p;/^Verify return code/p'" \
"cp www.$Z.crt /lab/tls/server.crt
cp www.$Z.key /lab/tls/server.key
web-reload
curl -sS --cacert /lab/tls/acme-root.crt https://www.$Z/
openssl s_client -connect www.$Z:443 -servername www.$Z -CAfile /lab/tls/acme-root.crt \\
  </dev/null 2>/dev/null | sed -n '/^Certificate chain/,/^---/p;/^Verify return code/p'"
note "3.6"
st "cd /lab/work/lego/certificates; cat www.$Z.crt www.$Z.issuer.crt > /lab/tls/server.crt; $RELOAD; curl -sS --cacert /lab/tls/acme-root.crt https://www.$Z/; openssl s_client -connect www.$Z:443 -servername www.$Z -CAfile /lab/tls/acme-root.crt </dev/null 2>/dev/null | sed -n '/^Certificate chain/,/^---/p;/^Verify return code/p'; curl -sS --cacert /lab/tls/acme-root.crt https://$AL/" \
"cat www.$Z.crt www.$Z.issuer.crt > /lab/tls/server.crt
web-reload
curl -sS --cacert /lab/tls/acme-root.crt https://www.$Z/
openssl s_client -connect www.$Z:443 -servername www.$Z -CAfile /lab/tls/acme-root.crt \\
  </dev/null 2>/dev/null | sed -n '/^Certificate chain/,/^---/p;/^Verify return code/p'
curl -sS --cacert /lab/tls/acme-root.crt https://$AL/"
}

t4(){
note "4.1"
st "for i in 1 2 3 4 5; do n=f\$i.$Z; echo \"=== \$n\"; curl -sS --cacert \$STAND_CA https://\$n/ 2>&1 | head -1; openssl s_client -connect \$n:443 -servername \$n -CAfile \$STAND_CA </dev/null 2>/dev/null | sed -n '/^Certificate chain/,/^---/p;/^Verify return code/p' | grep -v PKEY; done" \
"for i in 1 2 3 4 5; do
  n=f\$i.$Z; echo \"=== \$n\"
  curl -sS --cacert \$STAND_CA https://\$n/ 2>&1 | head -1
  openssl s_client -connect \$n:443 -servername \$n -CAfile \$STAND_CA </dev/null 2>/dev/null \\
    | sed -n '/^Certificate chain/,/^---/p;/^Verify return code/p' | grep -v PKEY
done"
note "додатково: curl -k (питання 3) і SAN/дати кожного сертифіката"
st "for i in 1 2 3 4 5; do n=f\$i.$Z; echo \"=== \$n: \$(curl -sk https://\$n/ 2>&1 | head -1)\"; openssl s_client -connect \$n:443 -servername \$n </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates -ext subjectAltName 2>&1 | grep -v '^X509v3'; done"
}

t5(){
note "5.2"
st "F='%{time_namelookup} %{time_connect} %{time_appconnect} %{time_starttransfer} %{time_total} %{http_version} %{num_connects}\n'; U=https://$R/; for i in 1 2 3; do curl -s -o /dev/null --cacert \$STAND_CA -w \"\$F\" \$U; done; for i in 1 2 3; do curl -s -o /dev/null --tls-max 1.2 --cacert \$STAND_CA -w \"\$F\" \$U; done" \
"F='%{time_namelookup} %{time_connect} %{time_appconnect} %{time_starttransfer} %{time_total} %{http_version} %{num_connects}\n'
U=https://$R/
for i in 1 2 3; do curl -s -o /dev/null --cacert \$STAND_CA -w \"\$F\" \$U; done
for i in 1 2 3; do curl -s -o /dev/null --tls-max 1.2 --cacert \$STAND_CA -w \"\$F\" \$U; done"
note "5.3"
st "F='%{time_namelookup} %{time_connect} %{time_appconnect} %{time_starttransfer} %{time_total} %{http_version} %{num_connects}\n'; U=https://$R/; curl -s --cacert \$STAND_CA -w \"\$F\" -o /dev/null \$U -o /dev/null \$U -o /dev/null \$U" \
"curl -s --cacert \$STAND_CA -w \"\$F\" -o /dev/null \$U -o /dev/null \$U -o /dev/null \$U"
note "додатково: ping до web (RTT)"
st "ping -c 5 10.53.0.80 2>&1 | tail -3 || true"
}

t0 2>&1 | tee $L/00-env.txt
t1 2>&1 | tee $L/01-dump.txt
t2 2>&1 | tee $L/02-handshake.txt
t3 2>&1 | tee $L/03-acme.txt
t4 2>&1 | tee $L/04-faults.txt
t5 2>&1 | tee $L/05-timing.txt
mkdir -p $L/work; cp -r stand/students/$SID/work/t*.txt $L/work/ 2>/dev/null
echo ALL_DONE
