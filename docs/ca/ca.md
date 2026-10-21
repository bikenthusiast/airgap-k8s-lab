Step 1: Directory layout on infra
bash
ssh airgap-lab-infra
sudo mkdir -p /srv/ca/private /srv/ca/certs
sudo chmod 700 /srv/ca/private      # only root may even list the key folder

Step 2: Generate the private key
bash
sudo sh -c 'umask 077; openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out /srv/ca/private/ca.key'
sudo ls -l /srv/ca/private/ca.key   # expect -rw------- root root

Step 3: Config file with the CA extensions
bash
sudo tee /srv/ca/ca.cnf >/dev/null <<'EOF'
[req]
prompt             = no
distinguished_name = dn
x509_extensions    = v3_ca

[dn]
CN = airgap-lab Root CA
O  = airgap-lab

[v3_ca]
basicConstraints       = critical, CA:TRUE, pathlen:0
keyUsage               = critical, keyCertSign, cRLSign
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always
EOF

Step 4: Create the self-signed CA certificate
bash
sudo openssl req -x509 -new -key /srv/ca/private/ca.key -sha256 -days 3650 \
  -config /srv/ca/ca.cnf -out /srv/ca/certs/ca.crt
sudo chmod 644 /srv/ca/certs/ca.crt   # public, everyone may read it

Step 5: Check it, then note the expiry date
bash
openssl x509 -in /srv/ca/certs/ca.crt -noout -subject -issuer -dates -serial
openssl x509 -in /srv/ca/certs/ca.crt -noout -fingerprint -sha256
openssl x509 -in /srv/ca/certs/ca.crt -noout -text | grep -A1 -E 'Basic Constraints|Key Usage'
openssl x509 -in /srv/ca/certs/ca.crt -noout -checkend 0 && echo "valid"
----
output

openssl x509 -in /srv/ca/certs/ca.crt -noout -subject -issuer -dates -serial

subject=CN=airgap-lab Root CA, O=airgap-lab
issuer=CN=airgap-lab Root CA, O=airgap-lab
notBefore=Oct 21 13:38:59 2026 GMT
notAfter=Oct 18 13:38:59 2036 GMT
serial=0489072A489CF6F1AB9A4761D8D4A946830FE20A

openssl x509 -in /srv/ca/certs/ca.crt -noout -fingerprint -sha256
sha256 Fingerprint=9B:E8:AF:AA:FA:68:9F:DC:32:81:C6:AB:96:BB:4D:0B:AF:BB:57:45:66:C2:58:3C:31:45:10:0E:5A:1A:88:30

openssl x509 -in /srv/ca/certs/ca.crt -noout -text | grep -A1 -E 'Basic Constraints|Key Usage'
            X509v3 Basic Constraints: critical
                CA:TRUE, pathlen:0
            X509v3 Key Usage: critical
                Certificate Sign, CRL Sign

openssl x509 -in /srv/ca/certs/ca.crt -noout -checkend 0 && echo "valid"
Certificate will not expire
valid
