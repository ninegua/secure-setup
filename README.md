# Secure Setup for Key Management

***WARNING: this is a work-in-progress. Follow it at your own risk!***

This project aims to provide a secure setup for key management with the following practice:

- Create an encrypted and bootable USB drive.
- Boot an offline machine with the USB drive to create both master and sub keys.
- Copy secret keys to (more than one) YubiKeys.
- Keep the USB drive or backup in cold storage.
- Use YubiKeys for all online activities such as signing/encryption/logging into remote services, etc.

Instead of explaining the elaborate steps like many other tutorials or blog posts, it aims to automate as much as possible.

This setup uses [GnuPG] as the software to manage keys, which works on major operating systems as well mobile phones. 
It uses the OpenPGP support of [YubiKey] instead of PIV, which also works on major operating systems as well android phones.
The iOS support for YubiKey is very new at the moment, and OpenPGP wasn't mentioned.

## 1. Create an encrypted and bootable USB drive

The `mkusb.sh` script is used to create an encrypted USB drive.
***At the moment it only works on an existing [NixOS].***

For example, if your USB drive is at `/dev/sdc`, run this:
```
sudo ./mkusb.sh /dev/sdc
```

It'll ask you to enter a passphrase that will be used to encrypt and boot the USB drive with (which is not to be confused with the passphrase used in Step 2).
Just follow through the steps, and it will format the USB drive and install a customized NixOS on it, with encrypted UEFI partitions.
The USB drive can then be plugged into a separate machine to boot.
The recommendation is to only boot this USB drive on an offline machine ([known caveat](https://github.com/ninegua/secure-setup/issues/2)).

There is also a plan to [switch from using `nixos-install` to building disk image directly](https://github.com/ninegua/secure-setup/issues/1)).
Ideas and suggestions are welcome!

## 2. Create GnuPG master and sub keys

Once USB drive is fully booted, you may login in as `root` user with the root password you gave during step 1.
Then run the following command to create one master key (default is Ed25519) and a set of sub keys (default is RSA4096):

```
/usr/bin/keygen.sh "Full Name" "Email Address"
```

It will prompt you to input a passphrase that protects the use of secret keys.
If you prefer not to go through this interactively, you may do this instead:

```
PASS="Your Passphrase" /usr/bin/keygen.sh "Full Name" "Email Address"
```

The newly created keys are located in a `gnupg-master` directory, and you should never copy this directory to other machines.
If you want to backup, it is recommended to make a whole-disk copy of the USB drive instead.
You'll want to double check if the backup USB drive boots OK before you put it off to storage.

A QR code image of the passphrase-encrypted master key is also produce under `gnupg-master/masterkey.png`.
You may print the image for offline cold storage after printing it using directly connected printer.
The master key will only be used for key management purpose, e.g. to create and sign new keys, extend expiration date, and so on.
So expect only sparing usage of the USB drive from time to time, but it is still very important not to give it away, or accidentally lose it.

Another directory `gnupg-sub` is created to hold sub keys with master key removed, which will be used in step 3.

You normally should not care about these directories, unless you want to create keys for more than one user.
In which case, you'll want to rename or move both directories to another place on the same USB drive,
because re-running the `keygen.sh` script will delete and override existing directories.

Lastly, a few public files are created under a non-encrypted FAT32 parition mounted under `/mnt/data`.
They are public information to help with related setups on (and can be copied to) other machines.

- `/mnt/data/gpg-auth-key.pub` contains the public auth sub key in case you want to use it with OpenSSH.
- `/mnt/data/public-keys.gpg` contains all public keys, both master and sub keys.
- `/mnt/data/gpg-import.sh` is an importing script for GnuPG that not only imports public keys, but also setup proper trust level automatically.

## 3. Copy secret sub keys to YubiKey

***WARNING: This step will wipeout existing OpenGPG keys and PINs on your YubiKey.
Please make sure that it is fully acceptable before you proceed the steps below.***

With sub keys already created in the `gnupg-sub` directory, you can now copy them to YubiKeys by:

```
/usr/bin/yubicopy.sh "Full Name" "Email Address"
```

It'll ask for the passphrase that you entered when creating the keys in step 2, as well as new PIN and Admin PIN to manage OpenPGP keys on YubiKey.
It'll also prompt you when to remove and insert another YubiKey, if you have more than one to setup.

Again, if you prefer non-interactive setup, you may run:

```
PASS="Your Passphrase" PIN="6 digit" ADMIN_PIN="more than 8 digit" /usr/bin/yubicopy.sh "Full Name" "Email Address"
```

This will fully setup one YubiKey at a time with no fuss.

## 4. Multi-device considerations

It is recommended to setup more than one YubiKey with the same set of sub keys.
In case one is damaged or lost, at least there will be some redundancy.

For all practical purposes, YubiKeys are the only devices that hold and enable you to use the secret (sub) keys.
Both the master and sub secret keys also are kept on the USB drive as a backup, which should only be used for key management purpose but not copied to other machines for daily use.

Some people prefer setting up each YubiKey with different keys so that the lost ones can be invidually revoked.
It is definitely a more tendious setup and at the moment it is not supported by the above scripts.

To use the YubiKey on your daily machines or mobile phones, you'll have to first import the public keys and make sure they are connected to the particular YubiKey you want to use.

To import public keys automatically, just copy the above mentioned `/mnt/data/gpg-import.sh` script to a target machine and run it, assuming `gpg` command is in `PATH`.

To import public keys manually, you may copy the above mentioned `/mnt/data/public-keys.gpg` to a target machine, for use with a GPG compatible software such as [Gpg4Win], or [OpenKeyChain] on Android phones.

To switch yubikeys, after inserting the new yubikey, use `gpg-connect-agent "scd serialno" "learn --force" /bye` to update the keyid with gpg so the keypairs are now associated with the new yubikey.

## 5. Reset expiry setting

The above setting will use a default expiry time of `1y` (1 year) when creating both master and sub keys.
When a key expires, you may continue to use it for authentication and decryption if your local GnuPG setup trusts the keys "ultimately", but not for encryption.
So it is a good idea to set a new expiry time for all keys.
To do this, you must boot with the USB stick again, login, and then type type following command:

```
PASS="Your Passphrase" /usr/bin/extend-expiry.sh "Full Name"
```

As a result of the renewal, a new set of data files will be created in `/mnt/data` (any old files in there will be overwritten).
They should be loaded onto all devices/machines to refresh their copies of the set of keys (e.g., copy `gpg-import.sh` over and run it).

You may also run `yubicopy.sh` again to refresh the keys on your yubikey.
But I've found this step unnecessary, since GPG seems to load expiry from local setting, instead of yubikeys.

Again, the default is `1y` (1 year) from the current time on the machine you use.
This can be overridden with the environment variable `EXPIRE`, e.g., `EXPIRE=2y` will set all keys to expire in 2 years.
(This variable can also be used with `keygen.sh` above).

## 6. Related setups

### 5.1 GnuPG Agent and SSH

### 5.2 Pass and Browserpass

### 5.3 XBrowserSync

### 5.4 Yubikey Manager (`ykman`)

To enable/disable touch protection, use the following command:

```
> ykman openpgp set-touch aut -h
Usage: ykman openpgp set-touch [OPTIONS] KEY POLICY

  Set touch policy for OpenPGP keys.

  KEY     Key slot to set (sig, enc, aut or att).
  POLICY  Touch policy to set (on, off, fixed, cached or cached-fixed).
```

[GnuPG]: https://gnupg.org
[YubiKey]: https://www.yubico.com
[NixOS]: https://nixos.org
[Gpg4win]: https://www.gpg4win.org
[OpenKeyChain]: https://www.openkeychain.org

