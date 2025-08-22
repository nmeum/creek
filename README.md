## README

Creek is a [dwm]-inspired [malleable] and minimalist status bar for the [River] Wayland compositor.
The implementation is a hard fork of version 0.1.3 of the [levee] status bar.
Compared to levee, the main objective is to ease [recombination and reuse][malleable reuse] by providing a simpler interface for adding custom information to the status bar.
The original version of levee only provides builtin support for certain [modules][levee modules], these have to be written in Zig and compiled into levee.
This fork pursues an alternative direction by allowing arbitrary text to be written to standard input of the status bar process, this text is then displayed in the status bar.

Additionally, the following new features have been added:

* Support for tracking the current window title in the status bar
* Highlighting of tags containing urgent windows (see [xdg-activation])
* Basic run-time configuration support via command-line flags

### Screenshot

![Screenshot of River with a creek status bar](https://files.8pit.net/img/creek-screenshot-20240302.png)

The screenshot features three active tags: tag 2 is currently focused and has one active window, tag 4 is not focused but is occupied (i.e. has windows), and tag 9 has an urgent window.
In the middle of the status bar, the current title of the selected window on the focused tag is displayed.
On the right-hand side, the current time is shown, this is information is generated using `date(1)` (see usage example below).

### Build

The following dependencies need to be installed:

* [zig] 0.15.0
* [wayland] 1.21.0
* [pixman] 0.42.0
* [fcft] 3.1.5 (with [utf8proc] support)

Afterwards, creek can be build as follows

    $ git clone https://git.8pit.net/creek.git
    $ cd creek
    $ zig build

### Configuration

This version of creek can be configured using several command-line options:

* `-fn`: The font used in the status bar
* `-hg`: The total height of the status bar
* `-nf`: Normal foreground color
* `-nb`: Normal background color
* `-ff`: Foreground color for focused tags
* `-fb`: Background color for focused tags

Example:

    $ creek -fn Terminus:size=12 -hg 18 -nf 0xffffff -nb 0x000000

### Usage Example

In order to display the current time in the top-right corner, invoke creek as follows:

    $ ( while date; do sleep 1; done ) | creek

Note that for more complex setups, a shell script may [not be the best option](https://flak.tedunangst.com/post/rough-idling).

[dwm]: https://dwm.suckless.org/
[River]: https://github.com/riverwm/river/
[malleable]: https://malleable.systems/
[malleable reuse]: https://malleable.systems/mission/#2-arbitrary-recombination-and-reuse
[levee]: https://sr.ht/~andreafeletto/levee
[levee modules]: https://git.sr.ht/~andreafeletto/levee/tree/v0.1.3/item/src/modules
[xdg-activation]: https://wayland.app/protocols/xdg-activation-v1
[zig]: https://ziglang.org/
[wayland]: https://wayland.freedesktop.org/
[pixman]: http://pixman.org/
[fcft]: https://codeberg.org/dnkl/fcft/
[utf8proc]: https://juliastrings.github.io/utf8proc/
