* Improve font rendering
	* fcft's font rendering is a bit meh
	* Especially compared to bemenu which uses pango/cairo
* Fix some bugs with resizing
	* E.g. if river is running in a window
	* Resize will sometimes cause issues with status text
* Find a better way to create the Seat in `src/Wayland.zig`
* Improve tag handling
	* Currently 9 tags are hardcoded
	* Using more/less tags is currently not easily possible
	* Unfortunately, not possible to determine the maximum amount of tags with the current River protocol
	* Probably requires an additional command-line flag or something (meh)
* Consider displaying floating/tiling status next to the tags
	* IIRC this is what vanilla dwm does
* Report that Guix's Zig will link against systemc libc when not run in container
* Upgrade to latest and greatest Zig version (requires work on the Guix side)
