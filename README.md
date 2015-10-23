# sicas
Simple Image Captcha Server.

### Dependencies
* [vibe.d](https://github.com/rejectedsoftware/vibe.d)
  * [deimos](https://github.com/D-Programming-Deimos)
    * [libevent](https://github.com/D-Programming-Deimos/libevent)
    * [openssl](https://github.com/D-Programming-Deimos/openssl)

### Compiling

Using **[DUB](https://github.com/D-Programming-Language/dub)**:
```
dub build --build=release
```

### Program arguments
Flag          |    | Description                                        | Default value
--------------|----|----------------------------------------------------|--------------
**--height**  | -h | Minimum (default) captcha image height in *pixels* | 32
**--length**  | -l | Minimum (default) captcha string length            | 6
**--port**    | -p | Server port number for listening                   | 20938
**--width**   | -w | Minimum (default) captcha image width in *pixels*  | 64
**--timeout** | -t | Captcha expiration time in *seconds*               | 120
**--cors**    |    | Enable cross-origin resource sharing (CORS)        | false

> Use **--help** for a complete list of options, or **--version** for current version output.

### Usage examples
To run *sicas* with default settings, listening on the default port number (on Linux):
```
./bin/sicas
```
