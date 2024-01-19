# New Features

The following features should still be implemented at some point:

* Display title of selected window in the center of the status bar
    * This is where upstream levee displays the clock
    * Similar to dwm's default status bar
* Highlight tags with windows that have an urgent flag set
    * Again, this is similar to what dwm does

# Upstream

The following changes should/could be send upstream:

* Environment variable based configuration support
    * Sadly, there is no getopt(3) alternative in the Zig stdlib
    * See 965b6ddb9bedcd29082dcdc05b2189de3054f56a
* Fixed background color of the status bar
    * Should cleanup the color conversion code a bit
    * Would also be cool to support configuration of the alpha channel
    * See 6416dfd9f96464046c3eee9559edb4a34b6e49ac
* Improved error-handling
    * Noticed this when using levee w/o fcft utf8proc support
    * See …
