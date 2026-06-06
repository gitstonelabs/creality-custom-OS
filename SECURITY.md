# Security

This is a work in progress and has never been confirmed to boot. The notes below cover the security-relevant defaults that ship in the build.

## Weak default root password

The Buildroot config ships a weak default root password. `rootfs/configs/creality_hi_defconfig` sets:

```
BR2_TARGET_GENERIC_ROOT_PASSWD="root"
```

The password is `root`. Some build variants use `123456`. Either way it is a known, guessable credential. Nothing is forced on first boot, so it stays `root` until you change it. dropbear SSH is enabled, so a device on an untrusted network with the default password is open to anyone. Change it before you put the printer on a network you do not control.

## First login: recommended setup

Log in the first time over SSH with `ssh root@<printer-ip>` (password `root`), or on the serial console, then run these. This image uses BusyBox for user management and ships no `sudo` and no shadow-utils, so the commands below are what is actually present, not the `useradd`/`usermod`/`sudo` set you may expect.

Change the root password first:

```sh
passwd
```

Create your own login account instead of using root day to day. BusyBox `adduser` prompts for the new password and creates the home directory:

```sh
adduser myname
```

Set or change any account's password later. As root you can set anyone's:

```sh
passwd myname
```

Become root from your own account when you need to administer, since there is no `sudo`:

```sh
su -
```

Optional and recommended: set up SSH key login for your account so you can stop sending passwords over the network:

```sh
mkdir -p /home/myname/.ssh
echo 'ssh-ed25519 AAAA...your-public-key... you@host' > /home/myname/.ssh/authorized_keys
chmod 700 /home/myname/.ssh
chmod 600 /home/myname/.ssh/authorized_keys
chown -R myname:myname /home/myname/.ssh
```

## Changing a username

This image has no `usermod` (shadow-utils is not installed), so there is no one-command rename. The clean path is to create the account with the name you want, as above, and delete one you do not need:

```sh
deluser oldname
```

If you must rename an account in place, edit the user database by hand as root and move the home directory. A wrong edit here can lock you out, so back up the three files first:

```sh
cp /etc/passwd /etc/passwd.bak
cp /etc/shadow /etc/shadow.bak
cp /etc/group  /etc/group.bak
sed -i 's/^oldname:/newname:/' /etc/passwd /etc/shadow
sed -i 's/\boldname\b/newname/g' /etc/group
sed -i 's#/home/oldname#/home/newname#' /etc/passwd
mv /home/oldname /home/newname
```

## Optional: stop remote root logins

Once your own account works, you can stop dropbear from accepting root over the network. Add `-w` to dropbear's arguments in its systemd unit (the `-w` flag disallows root logins), then restart it:

```sh
systemctl edit --full dropbear     # add -w to the ExecStart line
systemctl restart dropbear
```

## printer.cfg drives no hardware

The bundled `rootfs/board/creality/hi/rootfs-overlay/etc/klipper/printer.cfg` is a placeholder. It sets `kinematics: none` and comments out the `[mcu]` section, so Klipper starts but commands no motion, heating, or other hardware. There is no risk of unintended physical actuation from the shipped config. Adding a real MCU and motion config is the user's responsibility.

## Reporting

This project does not yet have a published boot, so there is no deployed surface to report against. For issues in the source, open an issue on the repository.
