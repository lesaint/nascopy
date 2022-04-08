# NAS copy

Rsync based script intended to create a read-only copy of a NAS folder accessed through SSH on the local machine.

# Installation

	git clone https://github.com/lesaint/nascopy

# Usage

	rsync_nascopy.sh <source> <destination> [excluded-pattern-path]

## Exclude file

An optional exclude file can be provided as a third parameter. It should be compatible with the `--exclude-from` parameter of rsync. See [this tutorial] (https://sites.google.com/site/rsync2u/home/rsync-tutorial/the-exclude-from-option) for more information.

# Features

* Destination directory is made read-only to user, group and others
* Safety check - the copy will only happen if the destination has explicitly been marked as a NAS copy destination

# LICENSE

The MIT License (MIT)

Copyright (c) 2013-2014 Laurent Cozic

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

[![Bitdeli Badge](https://d2weczhvl823v0.cloudfront.net/laurent22/rsync-time-backup/trend.png)](https://bitdeli.com/free "Bitdeli Badge")