#! /usr/bin/env nix-shell
#! nix-shell -i bash -p gnupg qrencode "(zbar.override { enableVideo = false; })" rsync

USAGE="$0 [name]"
test -z "$1" && echo $USAGE && exit 1
NAME=$1

# Other variable settings
EXPIRE=${EXPIRE:-1y}

GPG_ARGS="--batch --yes --pinentry-mode loopback"
export GNUPGHOME=$PWD/gnupg-master

if [ -z "$PASS" ]; then
  echo -n Please enter a passphrase:
  read -s PASS
  echo
  echo -n Please enter it again:
  read -s PASS_AGAIN
  echo
  test "$PASS" != "$PASS_AGAIN" && echo Passphrase does not match! Abort! && exit 1
fi

gpgconf --kill gpg-agent

BACKUP=`mktemp -d -u ${GNUPGHOME}.XXXXXXXX`
echo 1. Backup $GNUPGHOME to $BACKUP
cp -r $GNUPGHOME $BACKUP


echo 2. Extend expiry to $EXPIRE
keys=`gpg --list-keys --with-colons|grep fpr|cut -d: -f10`
masterkey=
for key in $keys; do
  echo Set expiry for key $key
  if [ -z $masterkey ]; then
    gpg --passphrase "$PASS" $GPG_ARGS --quick-set-expire "$key" "$EXPIRE"
    masterkey="$key"
  else
    gpg --passphrase "$PASS" $GPG_ARGS --quick-set-expire "$masterkey" "$EXPIRE" "$key"
  fi
done

echo 3. Export masterkey
masterkey=`gpg --list-keys --with-colons|grep fpr|cut -d: -f10|head -n1`
mastergrip=`gpg --list-secret-keys --with-colons|grep grp|cut -d: -f10|head -n1`
MASTER_GPG=$GNUPGHOME/masterkey.txt
MASTER_TMP=$GNUPGHOME/masterkey.tmp
MASTER_PNG=$GNUPGHOME/masterkey.png
gpg --passphrase "$PASS" $GPG_ARGS -a --export-secret-keys ${masterkey}! > "$MASTER_GPG"
cat "$MASTER_GPG"|qrencode -l L -8 -o "$MASTER_PNG"
zbarimg --nodbus -D --raw "$MASTER_PNG" > "$MASTER_TMP"
diff -B "$MASTER_GPG" "$MASTER_TMP"
test "$?" != "0" && echo Error verifying master key stored in QR Code "$MASTER_PNG" && exit -1
rm -f "$MASTER_GPG" "$MASTER_TMP"
echo Created QR Code "$MASTER_PNG"

echo 4. Make copy and delete master key
GNUPGCOPY=$PWD/gnupg-sub
rsync --delete --exclude openpgp-revocs.d --exclude '*.png' --exclude $mastergrip.key -C -a $GNUPGHOME/ $GNUPGCOPY/
gpgconf --kill gpg-agent
export GNUPGHOME=$GNUPGCOPY
gpg --list-secret-keys
echo All subkeys are in GNUPGHOME=$GNUPGHOME

echo 5. Export public key to /mnt/data
test ! -d /mnt/data && echo /mnt/data does not exist. Abort! && exit 1
IMPORT_SCRIPT=/mnt/data/gpg-import.sh
echo "gpg --import <<END" > $IMPORT_SCRIPT
gpg -a --export $masterkey >> $IMPORT_SCRIPT
echo END >> $IMPORT_SCRIPT
echo "gpg --import-ownertrust <<END" >> $IMPORT_SCRIPT
gpg --export-ownertrust >> $IMPORT_SCRIPT
echo END >> $IMPORT_SCRIPT
gpg -a --export "$masterkey" > /mnt/data/"${NAME} Keys.gpg"
echo Created import script at "$IMPORT_SCRIPT"
auth_subkey=`gpg --list-keys --with-colons "$NAME"|sed -z -e 's/\nfpr/fpr/g'|grep sub|grep -v nistp|cut -d: -f12,28|grep ^a|cut -d: -f2|tail -n1`
gpg --export-ssh-key "$auth_subkey" > /mnt/data/gpg-auth-key.pub
echo Exported auth public subkey for OpenSSH at /mnt/data/gpg-auth-key.pub
