# sicas
Simple Image Captcha Server (WIP)

### Dependencies
* [deimos](https://github.com/D-Programming-Deimos)
 * [libevent](https://github.com/D-Programming-Deimos/libevent)
 * [openssl](https://github.com/D-Programming-Deimos/openssl)
* [vibe.d](https://github.com/rejectedsoftware/vibe.d)

### Compiling

Using **DMD**:
```
dmd src/sicas/*.d -w -ofsicas -O -release -L-lssl -L-lcrypto -L-levent
```
