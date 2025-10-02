Rough example of hijacking `rsyslog`'s usage of `libc` `open()` and `write()` to cause writes containing certain strings to `/var/log/auth.log` to be a no-op.

Red teams may use this script to assess a defense's coverage of MITRE Attack techniques, such as detection of dynamic link hijacking.

For educational purposes only. Do not use on systems unless you have permission to modify that system.
