#!/usr/bin/env python3
"""Copy the A/UX headers and libraries that build-cross.sh needs off an
install CD.

usage: extract-sysroot.py IMAGE SYSROOT

IMAGE is an image of an A/UX installation CD, such as an ISO or Toast
image of A/UX 3.0.1 or 3.1.0. Besides the Mac OS partition, the CD holds
an A/UX root file system, a big-endian Berkeley file system (UFS) in the
partition flagged as root. Its usr/include, lib and usr/lib are copied
below SYSROOT, which is then passed to build-cross.sh:

    extract-sysroot.py aux.iso sysroot
    build-cross.sh sysroot /path/to/binutils-aux /opt/aux
"""
import os
import stat
import struct
import sys

UFS_MAGIC = 0x011954
SBOFF = 8192
BZB_MAGIC = 0xABADBABE
BZB_ROOT = 0x80000000
PATHS = ('usr/include', 'lib', 'usr/lib')


class UFS:
    def __init__(self, f, start):
        self.f, self.start = f, start
        sb = self.read(SBOFF, 1400)
        if struct.unpack('>i', sb[1372:1376])[0] != UFS_MAGIC:
            raise ValueError('no UFS at sector %d' % (start // 512))

        def field(off):
            return struct.unpack('>i', sb[off:off + 4])[0]

        self.iblkno, self.cgoffset, self.cgmask = field(16), field(24), field(28)
        self.bsize, self.fsize, self.frag = field(48), field(52), field(56)
        self.nindir, self.inopb = field(116), field(120)
        self.ipg, self.fpg = field(184), field(188)

    def read(self, off, n):
        self.f.seek(self.start + off)
        return self.f.read(n)

    def inode(self, ino):
        cg, i = divmod(ino, self.ipg)
        cgstart = self.fpg * cg + self.cgoffset * (cg & ~self.cgmask)
        frag = cgstart + self.iblkno + (i // self.inopb) * self.frag
        d = self.read(frag * self.fsize + (i % self.inopb) * 128, 128)
        return {
            'mode': struct.unpack('>H', d[0:2])[0],
            # Only the low half of the 64-bit size is used, the high
            # half holds garbage on A/UX.
            'size': struct.unpack('>I', d[12:16])[0],
            'mtime': struct.unpack('>i', d[32:36])[0],
            'db': struct.unpack('>12i', d[40:88]),
            'ib': struct.unpack('>3i', d[88:100]),
            'raw': d,
        }

    def blocks(self, ino):
        yield from ino['db']
        for level, b in enumerate(ino['ib']):
            yield from self.indirect(b, level)

    def indirect(self, b, level):
        if not b:
            return
        data = self.read(b * self.fsize, self.bsize)
        for p in struct.unpack('>%di' % self.nindir, data):
            if level:
                yield from self.indirect(p, level - 1)
            else:
                yield p

    def data(self, ino):
        size = ino['size']
        # Short symbolic links keep their target in the block pointers.
        if stat.S_ISLNK(ino['mode']) and not any(ino['db']) and size < 48:
            return ino['raw'][40:40 + size]
        out = bytearray()
        for b in self.blocks(ino):
            if len(out) >= size:
                break
            n = min(self.bsize, size - len(out))
            out += self.read(b * self.fsize, n) if b else bytes(n)
        return bytes(out)

    def readdir(self, ino):
        d, off = self.data(self.inode(ino)), 0
        while off < len(d):
            num, reclen, namlen = struct.unpack('>IHH', d[off:off + 8])
            if reclen == 0:
                break
            if num:
                yield d[off + 8:off + 8 + namlen].decode('latin-1'), num
            off += reclen

    def lookup(self, path):
        ino = 2
        for name in path.strip('/').split('/'):
            if name:
                ino = dict(self.readdir(ino))[name]
        return ino

    def extract(self, num, dst):
        ino = self.inode(num)
        mode = ino['mode']
        if stat.S_ISDIR(mode):
            os.makedirs(dst, exist_ok=True)
            for name, child in self.readdir(num):
                if name not in ('.', '..'):
                    self.extract(child, os.path.join(dst, name))
        elif stat.S_ISLNK(mode):
            if not os.path.lexists(dst):
                os.symlink(self.data(ino).decode('latin-1'), dst)
        elif stat.S_ISREG(mode):
            with open(dst, 'wb') as out:
                out.write(self.data(ino))
            os.chmod(dst, (mode & 0o777) | 0o600)
            os.utime(dst, (ino['mtime'], ino['mtime']))


def root_partition(f):
    """Return the byte offset of the A/UX root file system."""
    for i in range(1, 64):
        f.seek(512 * i)
        entry = f.read(512)
        if entry[:2] != b'PM':
            break
        ptype = entry[48:80].split(b'\0')[0]
        # A/UX keeps a block zero block in the boot arguments.
        magic, flags = struct.unpack('>I4xI', entry[136:148])
        if (ptype == b'Apple_UNIX_SVR2' and magic == BZB_MAGIC
                and flags & BZB_ROOT):
            return 512 * struct.unpack('>I', entry[8:12])[0]
    return None


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__.strip().splitlines()[2])
    image, sysroot = sys.argv[1:]
    with open(image, 'rb') as f:
        start = root_partition(f)
        if start is None:
            sys.exit('%s: no A/UX root partition found' % image)
        fs = UFS(f, start)
        for path in PATHS:
            fs.extract(fs.lookup(path), os.path.join(sysroot, path))


if __name__ == '__main__':
    main()
