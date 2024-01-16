## README

This is a fork of [levee] (a status bar for [River]) which is intended to be more [malleable].
Specifically, it is supposed to easy [recombination and reuse][malleable reuse] by providing a simpler interface for adding custom information to the status bar.
The original version of leeve only provides builtin support for certain [modules][levee modules], these have to be written in Zig and compiled into leeve.
This fork attempts to ease this process by allowing arbitrary text to be written to standard input of the levee process, this text is then displayed in the status bar.

### Build

This software is intended to be installed using [Guix]

    $ git clone --recursive https://git.8pit.net/levee.git
    $ cd levee
    $ guix package -f guix.scm

### Usage Example

In order to display the current time in the top-left corner of the status bar invoke leeve as follows:

    $ ( while date; do sleep 1; done ) | levee

For more complex, a shell script may [not be the best option](https://flak.tedunangst.com/post/rough-idling).

### Dependencies

* [zig] 0.10.0
* [wayland] 1.21.0
* [pixman] 0.42.0
* [fcft] 3.1.5 (with [utf8proc])

[levee]: https://sr.ht/~andreafeletto/levee
[River]: https://github.com/riverwm/river/
[levee modules]: https://git.sr.ht/~andreafeletto/levee/tree/main/item/src/modules
[malleable]: https://malleable.systems/
[malleable reuse]: https://malleable.systems/mission/#2-arbitrary-recombination-and-reuse
[Guix]: https://guix.gnu.org/
[zig]: https://ziglang.org/
[wayland]: https://wayland.freedesktop.org/
[pixman]: http://pixman.org/
[fcft]: https://codeberg.org/dnkl/fcft/
[utf8proc]: https://juliastrings.github.io/utf8proc/
[#andreafeletto]: ircs://irc.libera.chat/#andreafeletto
[mailing list]: https://lists.sr.ht/~andreafeletto/public-inbox
[tutorial]: https://git-send-email.io
[IPC]: https://en.wikipedia.org/wiki/Inter-process_communication
