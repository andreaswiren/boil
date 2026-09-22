#!/bin/sh
set -eu
# HSM PIN is read from a protected credential file, never embedded in URI/argv.
osslsigncode sign \
  -provider /usr/lib/x86_64-linux-gnu/ossl-modules/pkcs11prov.so \
  -pkcs11module /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so \
  -pkcs11cert 'pkcs11:token=SignZone;object=CodeSigning-Cert' \
  -key 'pkcs11:token=SignZone;object=CodeSigning-Key' \
  -readpass /run/credentials/signzone-hsm-pin \
  -h sha256 -n 'Example App' -ts 'https://timestamp.example.invalid/' \
  -in unsigned.exe -out signed.exe
