#! /usr/bin/env nix-shell
#! nix-shell -i bash -p gnupg rsync yubikey-manager expect
USAGE="$0 [name] [email]"
test -z "$1" && echo $USAGE && exit 1
test -z "$2" && echo $USAGE && exit 1
NAME=$1
EMAIL=$2
FULLNAME="$NAME <$EMAIL>"
export GNUPGHOME=$PWD/gnupg-sub
echo GNUPGHOME=$GNUPGHOME
gpgconf --kill gpg-agent
gpg --list-secret-keys --with-keygrip $FULLNAME

if [ -z "$PASS" ]; then
  echo -n Please enter your GnuPG passphrase:
  read -s PASS
  echo
else
  test -z "$PIN" -o -z "$ADMIN_PIN"
  BATCH=$?
fi

GPG_ARGS="--batch --yes --pinentry-mode loopback"
test12345=`echo 12345|gpg --passphrase $PASS $GPG_ARGS -q -r "$FULLNAME" -e|gpg --passphrase $PASS $GPG_ARGS -q -d`
test "$test12345" != "12345" && echo "Cannot encrypt/decrypt (wrong PASS?). Abort!" && exit 1

# Check if subkeys exist
encr_subkey=`gpg --list-secret-keys --with-colons|sed -z -e 's/\nfpr/fpr/g' -e 's/\ngrp/grp/g'|grep ssb|grep -v nistp|cut -d: -f12,38|grep ^e|cut -d: -f2|tail -n1`
auth_subkey=`gpg --list-secret-keys --with-colons|sed -z -e 's/\nfpr/fpr/g' -e 's/\ngrp/grp/g'|grep ssb|grep -v nistp|cut -d: -f12,38|grep ^a|cut -d: -f2|tail -n1`
sign_subkey=`gpg --list-secret-keys --with-colons|sed -z -e 's/\nfpr/fpr/g' -e 's/\ngrp/grp/g'|grep ssb|grep -v nistp|cut -d: -f12,38|grep ^s|cut -d: -f2|tail -n1`
test -z "$encr_subkey" && echo Encr Subkey not found. Abort! && exit 1
test -z "$auth_subkey" && echo Auth Subkey not found. Abort! && exit 1
test -z "$sign_subkey" && echo Sign Subkey not found. Abort! && exit 1

echo 1. Make a copy of $GNUPGHOME
GNUPGCOPY=$PWD/gnupg-yubi
rsync --delete -C -a $GNUPGHOME/ $GNUPGCOPY/
export GNUPGHOME=$GNUPGCOPY
gpgconf --kill gpg-agent
gpg --list-secret-keys

while true; do

if [ -z "$BATCH" ]; then
  echo -n 2. Please insert your YubiKey, and press ENTER to continue...
  read
  ykman list
fi

serials=`ykman list|grep Serial|sed -e 's/^.*Serial: //'`
test -z "$serials" && echo No YubiKey detected. Abort! && exit 1
serial=`echo $serials|cut -d\  -f1`
test "$serials" != "$serial" && echo More than one YubiKey detected. Abort! && exit 1

if [ -z "$BATCH" ]; then
  echo -n "3. Do you want to reset YubiKey and change PIN (y/N)?"
  read RESET_PIN
else
  # always reset PIN in BATCH mode
  RESET_PIN=y
fi

if [ "$RESET_PIN" = "y" ]; then
  if [ -z "$PIN" ]; then
    echo -n Please enter a new PIN:
    read -s PIN
    echo
    echo -n Please enter a new PIN again:
    read -s PIN_AGAIN
    echo
    test "$PIN" != "$PIN_AGAIN" && echo PIN does not match. Abort! && exit 1
  fi
  if [ -z "$ADMIN_PIN" ]; then
    echo -n Please enter a new admin PIN:
    read -s ADMIN_PIN
    echo
    echo -n Please enter a new admin PIN again:
    read -s ADMIN_PIN_AGAIN
    echo
    test "$ADMIN_PIN" != "$ADMIN_PIN_AGAIN" && echo Admin PIN does not match. Abort! && exit 1
  fi

  # force reset PIN
  ykman -d $serial openpgp reset -f
  # change PIN
  gpg --command-fd 0 --change-pin --pinentry-mode loopback <<-END
	1
	123456
	$PIN
	$PIN
	q
	END
  gpg --command-fd 0 --change-pin --pinentry-mode loopback <<-END
	3
	12345678
	$ADMIN_PIN
	$ADMIN_PIN
	q
	END
else
  if [ -z "$ADMIN_PIN" ]; then
    echo -n Please enter YubiKey OpenPGP Admin PIN:
    read -s ADMIN_PIN
    echo
  fi
fi 

# set touch policy to ON
sleep 2
ykman -d $serial openpgp touch --admin-pin $ADMIN_PIN -f aut on
ykman -d $serial openpgp touch --admin-pin $ADMIN_PIN -f enc on
ykman -d $serial openpgp touch --admin-pin $ADMIN_PIN -f sig on

# Transfer keys
echo 4. Transfer subkeys to YubiKey
sleep 3 
encr_index=`gpg --list-secret-keys "$FULLNAME" |grep ssb|grep -n '\[E\]'|grep rsa|cut -d: -f1|tail -n1`
auth_index=`gpg --list-secret-keys "$FULLNAME" |grep ssb|grep -n '\[A\]'|grep rsa|cut -d: -f1|tail -n1`
sign_index=`gpg --list-secret-keys "$FULLNAME" |grep ssb|grep -n '\[S\]'|grep rsa|cut -d: -f1|tail -n1`

expect <<END
set timeout -1
spawn gpg --yes --pinentry-mode loopback --edit-key "${FULLNAME}"
expect "gpg> "
send -- "key ${encr_index}\r"
expect "gpg> "
send -- "keytocard\r"
expect "Your selection? "
send -- "2\r"
expect "Enter passphrase: "
send -- "${PASS}\r"
expect "Enter passphrase: "
send -- "${ADMIN_PIN}\r"
expect "Enter passphrase: "
send -- "${ADMIN_PIN}\r"
expect "gpg> "
send -- "key ${encr_index}\r"
expect "gpg> "
send -- "key ${auth_index}\r"
expect "gpg> "
send -- "keytocard\r"
expect "Your selection? "
send -- "3\r"
expect "Enter passphrase: "
send -- "${PASS}\r"
expect "Enter passphrase: "
send -- "${ADMIN_PIN}\r"
expect "gpg> "
send -- "key ${auth_index}\r"
expect "gpg> "
send -- "key ${sign_index}\r"
expect "gpg> "
send -- "keytocard\r"
expect "Your selection? "
send -- "1\r"
expect "Enter passphrase: "
send -- "${PASS}\r"
expect "Enter passphrase: "
send -- "${ADMIN_PIN}\r"
expect "gpg> "
send -- "save\r"
expect eof
END

if [ -n "$BATCH" ]; then
  break
else
  echo "5. Do you want to setup another YubiKey (y/N)?"
  read REPEAT
  test "$REPEAT" != "y" && break
  reset PIN
  reset ADMIN_PIN
fi

done
