## README

This is a fork of [levee] (a status bar for [River]) which is intended to be more [malleable].
Specifically, it is supposed to ease [recombination and reuse][malleable reuse] by providing a simpler interface for adding custom information to the status bar.
The original version of levee only provides builtin support for certain [modules][levee modules], these have to be written in Zig and compiled into levee.
This fork pursues an alternative direction by allowing arbitrary text to be written to standard input of the levee process, this text is then displayed in the status bar.

### Screenshot

![Screenshot of River with a leeve status bar](https://files.8pit.net/img/levee-screenshot-20240128.png)

The screenshot features three active tags: tag 2 is currently focused and has one active window, tag 4 is not focused but is occupied (i.e. has windows), and tag 9 has an urgent window.
In the middle of the status bar, the current title of the selected window on the focused tag is displayed.
On the right-hand side, the current time is shown, this is information is generated using `date(1)` (see usage example below).

### Build

This software is intended to be installed using [Guix]:

    $ git clone --recursive https://git.8pit.net/levee.git
    $ cd levee
    $ guix package -f guix.scm

If you want to hack on levee using Guix:

    $ guix shell -D -f guix.scm

### Configuration

This version of levee can be configured using several environment variable.
Presently, the following variables can be set:

* `LEVEE_FONT`: The font used in the status bar (e.g. `monospace:size=14`)
* `LEVEE_HEIGHT`: The total height of the status bar
* `LEVEE_BORDER`: Size of the border used to denote an active tag
* `LEVEE_NORMAL_BG`: Normal background color
* `LEVEE_NORMAL_FG`: Normal foreground color
* `LEVEE_FOCUS_BG`: Background color for focused tags
* `LEVEE_NORMAL_FG`: Foreground color for focused tags

### Usage Example

In order to display the current time in the top-left corner of the status bar invoke levee as follows:

    $ ( while date; do sleep 1; done ) | levee

Note that for more complex setups, a shell script may [not be the best option](https://flak.tedunangst.com/post/rough-idling).

### Dependencies

* [zig] 0.10.0
* [wayland] 1.21.0
* [pixman] 0.42.0
* [fcft] 3.1.5 (with [utf8proc] support)

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
