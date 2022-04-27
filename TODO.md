Performance:

* libuv allocates on every read, we should use a read buffer pool
* update cells for drawing should just happen once per frame
* update cells should only update the changed cells

Correctness:

* `exit` in the shell should close the window

Visual:

* bell
