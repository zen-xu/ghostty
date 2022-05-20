Performance:

* libuv allocates on every read, we should use a read buffer pool
* update cells should only update the changed cells
* terminal data structure is bad!

Correctness:

* `exit` in the shell should close the window

Visual:

* bell

Major Features:

* History, mouse scrolling
* Line wrap
* Selection, highlighting
* Copy/paste
* Bold
* Underline
* Strikethrough
* Emoji
* Ligatures
