#! /usr/bin/env nix-shell
#! nix-shell -i bash -p gnupg qrencode zbar rsync

USAGE="$0 [name] [email]"
test -z "$1" && echo $USAGE && exit 1
test -z "$2" && echo $USAGE && exit 1
NAME=$1
EMAIL=$2

# Other variable settings
EXPIRE=${EXPIRE:-1y}
MASTER_KEY_TYPE=${MASTER_KEY_TYPE:-EDDSA}
MASTER_KEY_CURVE=${MASTER_KEY_CURVE:-Ed25519}
SUB_KEY_LENGTH=${SUB_KEY_LENGTH:-4096}

GPG_ARGS="--batch --yes --pinentry-mode loopback"
export GNUPGHOME=$PWD/gnupg-master
rm -rf $GNUPGHOME
mkdir -p $GNUPGHOME
chmod 700 $GNUPGHOME

if [ -z "$PASS" ]; then
  echo -n Please enter a passphrase:
  read -s PASS
  echo
  echo -n Please enter it again:
  read -s PASS_AGAIN
  echo
  test "$PASS" != "$PASS_AGAIN" && echo Passphrase does not match! Abort! && exit 1
fi

echo 1. Create master key
BATCH_INPUT=$GNUPGHOME/master.input
cat >"$BATCH_INPUT" <<EOF
     %echo Generating a master key
     Key-Type: $MASTER_KEY_TYPE
     Key-Curve: $MASTER_KEY_CURVE
     Key-Usage: sign
     Name-Real: $NAME
     Name-Email: $EMAIL
     Expire-Date: $EXPIRE
     Passphrase: $PASS
     %commit
     %echo done
EOF
gpgconf --kill gpg-agent
gpg --batch --generate-key "$BATCH_INPUT"
test "$?" != "0" && echo Error creating master key, please check batch file "$BATCH_INPUT". && exit -1
rm -f "$BATCH_INPUT"

echo 2. Export masterkey
masterkey=`gpg --list-keys --with-colons|grep fpr|cut -d: -f10`
mastergrip=`gpg --list-secret-keys --with-colons|grep grp|cut -d: -f10`
MASTER_GPG=$GNUPGHOME/masterkey.txt
MASTER_TMP=$GNUPGHOME/masterkey.tmp
MASTER_PNG=$GNUPGHOME/masterkey.png
gpg --passphrase "$PASS" $GPG_ARGS -a --export-secret-keys $masterkey > "$MASTER_GPG"
cat "$MASTER_GPG"|qrencode -l L -8 -o "$MASTER_PNG"
zbarimg --nodbus -D --raw "$MASTER_PNG" > "$MASTER_TMP"
diff -B "$MASTER_GPG" "$MASTER_TMP"
test "$?" != "0" && echo Error verifying master key stored in QR Code "$MASTER_PNG" && exit -1
rm -f "$MASTER_GPG" "$MASTER_TMP"
echo Created QR Code "$MASTER_PNG"

echo 3. Create sub keys
gpg --passphrase "$PASS" $GPG_ARGS --quick-add-key $masterkey rsa${SUB_KEY_LENGTH} encr 1y
gpg --passphrase "$PASS" $GPG_ARGS --quick-add-key $masterkey rsa${SUB_KEY_LENGTH} auth 1y
gpg --passphrase "$PASS" $GPG_ARGS --quick-add-key $masterkey rsa${SUB_KEY_LENGTH} sign 1y
# We can also create ECDSA subkeys, but YubiKey has yet to support it for OpenPGP.
# gpg --passphrase "$PASS" $GPG_ARGS --quick-add-key $masterkey nistp384/ecdsa auth 1y
gpg --list-secret-keys

echo 4. Make copy and delete master key
GNUPGCOPY=$PWD/gnupg-sub
rsync --delete --exclude openpgp-revocs.d --exclude '*.png' --exclude $mastergrip.key -C -a $GNUPGHOME/ $GNUPGCOPY/
gpgconf --kill gpg-agent
export GNUPGHOME=$GNUPGCOPY
gpg --list-secret-keys
echo All subkeys are in GNUPGHOME=$GNUPGHOME
